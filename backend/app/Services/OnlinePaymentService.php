<?php

namespace App\Services;

use App\Models\Booking;
use App\Models\Payment;
use App\Models\RoomType;
use App\Payments\GatewayException;
use App\Payments\PaymentException;
use App\Payments\PaymentGateway;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

/**
 * The rules for paying online. Every method expects the booking row to be
 * locked by the caller (inside a database transaction).
 *
 * The one rule that matters most: a booking is confirmed only after the
 * SERVER has checked the payment itself. Nothing the app says is trusted.
 */
class OnlinePaymentService
{
    /** A guest who starts paying online gets this long to finish, instead of the first 5 minutes. */
    public const PAYMENT_WINDOW_MINUTES = 15;

    public const MODE_DEMO = 'demo';

    /** A real payment page from the payment company (PayWay, or Stripe). */
    public const MODE_ONLINE = 'online';

    /** Stripe cannot take less than 50 cents. */
    private const MIN_CENTS = 50;

    public function __construct(
        private PaymentGateway $gateway,
        private SettingsService $settings,
    ) {
    }

    /** 'demo' (faked, switched on by the admin), 'stripe', or null when nothing is set up. */
    public function mode(): ?string
    {
        if ($this->settings->get('demo_payment_mode')) {
            return self::MODE_DEMO;
        }

        return $this->gateway->isConfigured() ? self::MODE_ONLINE : null;
    }

    /** The discount for a price, from the admin's setting. @return array{percent: int, amount: float} */
    public function discountFor(float $total): array
    {
        $percent = max(0, min(50, (int) $this->settings->get('online_discount_percent')));

        return ['percent' => $percent, 'amount' => round($total * $percent / 100, 2)];
    }

    /**
     * The guest chose to pay online. Saves the discount, gives them more time,
     * and (outside demo mode) opens a Stripe payment page.
     *
     * @return array{mode: string, checkout_url: ?string, hint: ?string}
     *
     * @throws PaymentException
     */
    public function start(Booking $booking, string $baseUrl): array
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

        $mode = $this->mode();
        if ($mode === null) {
            throw new PaymentException(
                'Online payment is not set up yet. Please choose to pay at the hotel.',
                'online_payment_unavailable',
                503,
            );
        }

        $discount = $this->discountFor((float) $booking->total_price);
        $due = round((float) $booking->total_price - $discount['amount'], 2);
        $cents = (int) round($due * 100);

        $session = null;
        if ($mode === self::MODE_ONLINE) {
            if ($cents < self::MIN_CENTS) {
                throw new PaymentException('This amount is too small to pay online.', 'amount_too_small', 422);
            }

            // Make the new page first. If Stripe fails, the old state stays as it was.
            try {
                $session = $this->gateway->createCheckout(
                    $booking,
                    $cents,
                    rtrim($baseUrl, '/') . '/payment/success?booking=' . $booking->id,
                    rtrim($baseUrl, '/') . '/payment/cancelled?booking=' . $booking->id,
                );
            } catch (GatewayException $e) {
                Log::warning('Stripe could not open a payment page: ' . $e->getMessage());
                throw new PaymentException('The payment company is not answering. Please try again.', 'provider_error', 502);
            }
        }

        $oldSession = $booking->checkout_session_id;

        $booking->update([
            'payment_choice' => Booking::CHOICE_ONLINE,
            'discount_percent' => $discount['percent'],
            'discount_amount' => $discount['amount'],
            'checkout_session_id' => $session['id'] ?? null,
            // A running hold gets more time. A room already kept for the hotel stays kept.
            'hold_expires_at' => $booking->hold_expires_at === null
                ? null
                : now()->addMinutes(self::PAYMENT_WINDOW_MINUTES),
        ]);

        // A guest who starts again must not be able to pay on the old page.
        if ($oldSession && $oldSession !== ($session['id'] ?? null)) {
            $this->closePageOrRefund($booking, $oldSession);
        }

        return [
            'mode' => $mode,
            'checkout_url' => $session['url'] ?? null,
            'hint' => $mode === self::MODE_ONLINE ? $this->gateway->checkoutHint() : null,
        ];
    }

    /**
     * The guest says they paid. We do not take their word: ask Stripe.
     *
     * @return array{outcome: string, booking: Booking, code?: string, message?: string}
     *         outcome is "confirmed" or "refunded"
     *
     * @throws PaymentException
     */
    public function verify(Booking $booking): array
    {
        if ($booking->isPaid()) {
            return ['outcome' => 'confirmed', 'booking' => $booking]; // asked twice: no harm
        }

        $sessionId = $booking->checkout_session_id;
        if (! $sessionId) {
            throw new PaymentException('No online payment was started for this booking.', 'no_payment_started', 409);
        }

        try {
            $info = $this->gateway->retrieveCheckout($sessionId);
        } catch (GatewayException $e) {
            Log::warning('Stripe could not check a payment: ' . $e->getMessage());
            throw new PaymentException('We could not check the payment yet. Please try again.', 'provider_error', 502);
        }

        if (! $info['paid']) {
            if ($info['expired']) {
                throw new PaymentException('The payment page expired. Please start again.', 'session_expired', 409);
            }
            throw new PaymentException('The payment is not finished yet.', 'payment_not_completed', 409);
        }

        // Stripe says it was paid. Make sure it was paid for THIS booking and the RIGHT amount.
        $expectedCents = (int) round($booking->amount_due * 100);
        if ($info['booking_id'] !== $booking->id || $info['amount_cents'] !== $expectedCents || $info['currency'] !== 'usd') {
            Log::error("Payment check failed for booking {$booking->id}: Stripe reports "
                . "booking {$info['booking_id']}, {$info['amount_cents']} {$info['currency']}, expected {$expectedCents} usd.");
            throw new PaymentException(
                'The payment does not match this booking. Please contact the hotel.',
                'payment_mismatch',
                422,
            );
        }

        $reference = $info['payment_reference'] ?: $sessionId;

        // The guest paid. But was the room still theirs?
        if ($booking->status !== Booking::STATUS_PENDING) {
            return $this->refundAndRecord(
                $booking, $reference, 'booking_cancelled_refunded',
                'This booking was cancelled before the payment arrived. Your money was sent back.',
            );
        }

        if ($booking->isExpiredHold() && ! $this->roomStillFree($booking)) {
            return $this->refundAndRecord(
                $booking, $reference, 'room_gone_refunded',
                'The room was taken before your payment arrived. Your money was sent back.',
            );
        }

        $this->confirm($booking, $reference);

        return ['outcome' => 'confirmed', 'booking' => $booking];
    }

    /**
     * Demo mode: no company, no money. The admin switched this on for the
     * presentation. The server still does every check a real payment would need.
     *
     * @throws PaymentException
     */
    public function demoPay(Booking $booking): Booking
    {
        if (! $this->settings->get('demo_payment_mode')) {
            throw new PaymentException('Demo payment is switched off.', 'demo_mode_off', 403);
        }
        if ($booking->isPaid()) {
            return $booking;
        }
        if ($booking->status !== Booking::STATUS_PENDING) {
            throw new PaymentException('This booking can no longer be paid.', 'not_pending', 422);
        }
        if ($booking->payment_choice !== Booking::CHOICE_ONLINE) {
            throw new PaymentException('Choose to pay online first.', 'no_payment_started', 409);
        }
        if ($booking->isExpiredHold()) {
            throw new PaymentException(
                'Your time ran out and the room may be taken. Please book again.',
                'hold_expired',
                409,
            );
        }

        $this->confirm($booking, 'demo-' . Str::lower(Str::random(12)));

        return $booking;
    }

    /**
     * The guest went another way (hotel, cancel) or staff took the money at
     * the desk. Close any open payment page, so it can never be paid later,
     * and forget the discount, which only belongs to paying online.
     */
    public function abandon(Booking $booking): void
    {
        if ($booking->checkout_session_id) {
            $this->closePageOrRefund($booking, $booking->checkout_session_id);
        }

        $booking->update([
            'checkout_session_id' => null,
            'discount_percent' => 0,
            'discount_amount' => 0,
        ]);
    }

    /**
     * Gives the money back for every online payment of this booking (always the full amount).
     * Demo payments were never real, so they are only marked as refunded.
     * Returns the money given back. The caller holds a lock on the booking and a transaction.
     *
     * @throws PaymentException when the payment company refuses, so nothing else should change
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
            if (! str_starts_with((string) $payment->reference, 'demo-')) {
                try {
                    $this->gateway->refund((string) $payment->reference);
                } catch (GatewayException $e) {
                    Log::critical("REFUND FAILED for booking {$booking->id} ({$payment->reference}): " . $e->getMessage());
                    throw new PaymentException(
                        'We could not send your money back yet. Nothing was cancelled. '
                        . "Please try again, or contact the hotel with booking number {$booking->code}.",
                        'refund_failed',
                        502,
                    );
                }
            }

            $payment->update(['status' => Payment::STATUS_REFUNDED]);
            $total += (float) $payment->amount;
        }

        return round($total, 2);
    }

    // --------------------------------------------------------------- inside

    private function confirm(Booking $booking, string $reference): void
    {
        Payment::create([
            'booking_id' => $booking->id,
            'amount' => $booking->amount_due,
            'method' => Payment::METHOD_ONLINE,
            'status' => Payment::STATUS_PAID,
            'received_by' => null, // nobody took this money by hand
            'reference' => $reference,
            'paid_at' => now(),
        ]);

        $booking->update([
            'status' => Booking::STATUS_CONFIRMED,
            'payment_choice' => Booking::CHOICE_ONLINE,
            'hold_expires_at' => null,
            'checkout_session_id' => null,
        ]);
    }

    /** The money arrived but the room cannot be given. Pay it back and keep a record. */
    private function refundAndRecord(Booking $booking, string $reference, string $code, string $message): array
    {
        try {
            $this->gateway->refund($reference);
        } catch (GatewayException $e) {
            Log::critical("MONEY STUCK: booking {$booking->id} was paid ({$reference}) but could not be refunded: " . $e->getMessage());
            throw new PaymentException(
                'Your payment arrived but the room is gone, and the automatic refund failed. '
                . "Please contact the hotel and tell them your booking number {$booking->code}.",
                'refund_failed',
                502,
            );
        }

        Payment::create([
            'booking_id' => $booking->id,
            'amount' => $booking->amount_due,
            'method' => Payment::METHOD_ONLINE,
            'status' => Payment::STATUS_REFUNDED,
            'reference' => $reference,
            'paid_at' => now(),
        ]);

        if ($booking->status === Booking::STATUS_PENDING) {
            $booking->update(['status' => Booking::STATUS_CANCELLED, 'hold_expires_at' => null]);
        }
        $booking->update(['checkout_session_id' => null]);

        return ['outcome' => 'refunded', 'booking' => $booking, 'code' => $code, 'message' => $message];
    }

    /** After the 5 minutes the room may have gone to someone else. Is it still free? */
    private function roomStillFree(Booking $booking): bool
    {
        $room = $booking->room;

        // Lock the room type, the same way booking does, so nobody books it at this very moment.
        RoomType::whereKey($room->room_type_id)->lockForUpdate()->first();

        if ($room->status !== 'available') {
            return false;
        }

        return ! Booking::where('room_id', $booking->room_id)
            ->where('id', '!=', $booking->id)
            ->blocking()
            ->overlapping($booking->check_in_date->toDateString(), $booking->check_out_date->toDateString())
            ->exists();
    }

    /**
     * Closes a payment page so nobody can pay on it later. Closing fails when the
     * page was already paid, perhaps at this very moment, while the guest was
     * cancelling. Then the money must go back, so we check and refund.
     */
    private function closePageOrRefund(Booking $booking, string $sessionId): void
    {
        try {
            $this->gateway->expireCheckout($sessionId);

            return;
        } catch (GatewayException $e) {
            Log::notice("Could not close payment page {$sessionId}: " . $e->getMessage());
        }

        try {
            $info = $this->gateway->retrieveCheckout($sessionId);

            if ($info['paid']) {
                $reference = $info['payment_reference'] ?: $sessionId;
                $this->gateway->refund($reference);

                Payment::create([
                    'booking_id' => $booking->id,
                    'amount' => round($info['amount_cents'] / 100, 2),
                    'method' => Payment::METHOD_ONLINE,
                    'status' => Payment::STATUS_REFUNDED,
                    'reference' => $reference,
                    'paid_at' => now(),
                ]);

                Log::notice("Booking {$booking->id}: the guest paid while changing their mind, so the payment was refunded.");
            }
        } catch (GatewayException $e) {
            Log::critical("MONEY MAY BE STUCK: could not close or check payment page {$sessionId} (booking {$booking->id}): " . $e->getMessage());
        }
    }
}
