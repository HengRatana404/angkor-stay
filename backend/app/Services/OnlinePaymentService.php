<?php

namespace App\Services;

use App\Models\Booking;
use App\Models\Payment;
use App\Models\PaymentIntent;
use App\Payments\KhqrPayload;
use App\Payments\PaymentException;
use Illuminate\Support\Str;

/**
 * Paying online. The payments are SIMULATED: no bank, no real money, any card works
 * (unless it has expired). But the rules are the real ones:
 *
 *  - every payment is first written to the database as a payment intent;
 *  - a booking is confirmed only after the SERVER re-reads that intent from the database
 *    and checks it (still open, not expired, right booking, right amount);
 *  - nothing the app says is trusted.
 *
 * Every method expects the booking row to be locked by the caller (inside a transaction).
 */
class OnlinePaymentService
{
    /** A guest who starts paying online gets this long to finish, instead of the first 5 minutes. */
    public const PAYMENT_WINDOW_MINUTES = 15;

    public function __construct(private SettingsService $settings)
    {
    }

    /** The discount for a price, from the admin's setting. @return array{percent: int, amount: float} */
    public function discountFor(float $total): array
    {
        $percent = max(0, min(50, (int) $this->settings->get('online_discount_percent')));

        return ['percent' => $percent, 'amount' => round($total * $percent / 100, 2)];
    }

    /**
     * The guest pays with a QR code. Opens a QR payment and returns it. The QR text is a real-format
     * KHQR payload. The payment is only confirmed later, when the guest presses "I have paid" and
     * the server verifies the intent in the database.
     *
     * @throws PaymentException
     */
    public function startQr(Booking $booking): PaymentIntent
    {
        $this->assertPayable($booking);

        $intent = $this->openIntent($booking, PaymentIntent::CHANNEL_QR);
        $intent->update([
            'qr_payload' => KhqrPayload::build($intent->reference, (float) $intent->amount, $intent->expires_at),
        ]);

        return $intent;
    }

    /**
     * The guest pays with a card. No bank is called, so any card number works. The payment is written to the
     * database, checked there, and settled in one go. Only the brand and the last 4 digits are kept.
     *
     * @param  array{number: string, brand: string}  $card
     *
     * @throws PaymentException
     */
    public function payByCard(Booking $booking, array $card): PaymentIntent
    {
        $this->assertPayable($booking);

        $intent = $this->openIntent($booking, PaymentIntent::CHANNEL_CARD, [
            'card_brand' => $card['brand'],
            'card_last4' => substr($card['number'], -4),
        ]);

        return $this->settle($booking, $intent);
    }

    /**
     * The guest says they paid with the QR code. We do not take their word: we look for their open
     * QR payment in the database, check it, and only then confirm the booking.
     *
     * @throws PaymentException
     */
    public function verify(Booking $booking): Booking
    {
        if ($booking->isPaid()) {
            return $booking; // asked twice: no harm
        }

        $intent = $booking->intents()
            ->where('channel', PaymentIntent::CHANNEL_QR)
            ->pending()
            ->latest('id')
            ->first();

        if (! $intent) {
            $expired = $booking->intents()->where('status', PaymentIntent::STATUS_EXPIRED)->exists();

            throw $expired
                ? new PaymentException('The QR code expired. Please start again.', 'payment_expired', 409)
                : new PaymentException('No QR payment was started for this booking.', 'no_payment_started', 409);
        }

        $this->assertPayable($booking);
        $this->settle($booking, $intent);

        return $booking;
    }

    /**
     * The guest went another way (hotel, cancel) or staff took the money at the desk.
     * Close every open payment, so it can never be settled later, and forget the discount,
     * which only belongs to paying online.
     */
    public function abandon(Booking $booking): void
    {
        $booking->intents()->pending()->update(['status' => PaymentIntent::STATUS_CANCELLED]);

        $booking->update(['discount_percent' => 0, 'discount_amount' => 0]);
    }

    /**
     * Gives the money back for every online payment of this booking (always the full amount).
     * The payment is simulated, so a refund is a record in the database: the payment and its
     * intent are marked refunded. Returns the money given back.
     */
    public function refundOnlinePayments(Booking $booking): float
    {
        $total = 0.0;

        $payments = $booking->payments()
            ->where('status', Payment::STATUS_PAID)
            ->where('method', Payment::METHOD_ONLINE)
            ->lockForUpdate()
            ->get();

        foreach ($payments as $payment) {
            $payment->update(['status' => Payment::STATUS_REFUNDED]);
            PaymentIntent::where('reference', $payment->reference)->update(['status' => PaymentIntent::STATUS_REFUNDED]);
            $total += (float) $payment->amount;
        }

        return round($total, 2);
    }

    // --------------------------------------------------------------- inside

    /** @throws PaymentException */
    private function assertPayable(Booking $booking): void
    {
        if ($booking->status !== Booking::STATUS_PENDING || $booking->isPaid()) {
            throw new PaymentException('This booking can no longer be changed.', 'not_pending', 422);
        }
        if ($booking->isExpiredHold()) {
            throw new PaymentException(
                'Your 5 minutes ran out and the room may be taken. Please book again.',
                'hold_expired',
                409,
            );
        }
    }

    /**
     * Saves the discount, gives the guest more time, closes any earlier open payment and
     * writes a new payment intent for the amount to pay.
     */
    private function openIntent(Booking $booking, string $channel, array $extra = []): PaymentIntent
    {
        $discount = $this->discountFor((float) $booking->total_price);

        $booking->update([
            'payment_choice' => Booking::CHOICE_ONLINE,
            'discount_percent' => $discount['percent'],
            'discount_amount' => $discount['amount'],
            // A running hold gets more time. A room already kept for the hotel stays kept.
            'hold_expires_at' => $booking->hold_expires_at === null
                ? null
                : now()->addMinutes(self::PAYMENT_WINDOW_MINUTES),
        ]);

        // A guest who starts again must not be able to pay on the old one.
        $booking->intents()->pending()->update(['status' => PaymentIntent::STATUS_CANCELLED]);

        return $booking->intents()->create(array_merge([
            'channel' => $channel,
            'amount' => $booking->amount_due,
            'status' => PaymentIntent::STATUS_PENDING,
            'reference' => 'AS' . $booking->id . '-' . Str::upper(Str::random(8)),
            'expires_at' => now()->addMinutes(self::PAYMENT_WINDOW_MINUTES),
        ], $extra));
    }

    /**
     * The simulated bank says yes, but only after the server has checked the intent in the database.
     * Re-reads the row (locked), so two taps can never settle it twice.
     *
     * @throws PaymentException
     */
    private function settle(Booking $booking, PaymentIntent $intent): PaymentIntent
    {
        $row = PaymentIntent::whereKey($intent->id)->lockForUpdate()->firstOrFail();

        if ($row->status !== PaymentIntent::STATUS_PENDING) {
            throw new PaymentException('This payment is not open any more. Please start again.', 'payment_not_open', 409);
        }
        if ($row->booking_id !== $booking->id) {
            throw new PaymentException('The payment does not match this booking.', 'payment_mismatch', 422);
        }
        if ($row->isExpired()) {
            // (The row is tidied to "expired" by the clean-up job. We cannot write it here:
            // this error rolls the transaction back.)
            throw new PaymentException('The payment expired. Please start again.', 'payment_expired', 409);
        }
        if (round((float) $row->amount, 2) !== round((float) $booking->amount_due, 2)) {
            throw new PaymentException('The amount does not match this booking. Please start again.', 'payment_mismatch', 422);
        }

        $row->update(['status' => PaymentIntent::STATUS_PAID, 'paid_at' => now()]);

        Payment::create([
            'booking_id' => $booking->id,
            'amount' => $row->amount,
            'method' => Payment::METHOD_ONLINE,
            'status' => Payment::STATUS_PAID,
            'received_by' => null, // nobody took this money by hand
            'reference' => $row->reference,
            'paid_at' => now(),
        ]);

        $booking->update([
            'status' => Booking::STATUS_CONFIRMED,
            'payment_choice' => Booking::CHOICE_ONLINE,
            'hold_expires_at' => null,
        ]);

        return $row;
    }
}
