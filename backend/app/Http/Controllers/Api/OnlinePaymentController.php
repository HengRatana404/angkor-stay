<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\PayByCardRequest;
use App\Http\Resources\BookingResource;
use App\Models\Booking;
use App\Models\PaymentIntent;
use App\Payments\PaymentException;
use App\Services\OnlinePaymentService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * The guest pays online. The payments are simulated, but the booking is only confirmed
 * after the server checks the payment in the database.
 *
 *  pay-card          the guest types a card. It is saved and checked in the database at once.
 *  pay-qr            the guest gets a QR code (a payment is opened in the database).
 *  verify-payment    the guest presses "I have paid". The server finds the open QR payment in the database,
 *                    checks it, and only then confirms the booking.
 */
class OnlinePaymentController extends Controller
{
    public function __construct(private OnlinePaymentService $online)
    {
    }

    public function payByCard(PayByCardRequest $request, int $id): JsonResponse
    {
        try {
            [$booking, $intent] = DB::transaction(function () use ($request, $id) {
                $booking = $this->ownBookingLocked($request, $id);
                $number = $request->validated('number');

                $intent = $this->online->payByCard($booking, [
                    'number' => $number,
                    'brand' => PayByCardRequest::brandOf($number),
                ]);

                return [$booking, $intent];
            });
        } catch (PaymentException $e) {
            return $e->toResponse();
        }

        return response()->json([
            'data' => $this->resource($booking),
            'payment' => [
                'reference' => $intent->reference,
                'channel' => $intent->channel,
                'description' => $intent->describe(),
                'amount' => (float) $intent->amount,
            ],
        ]);
    }

    public function startQr(Request $request, int $id): JsonResponse
    {
        try {
            [$booking, $intent] = DB::transaction(function () use ($request, $id) {
                $booking = $this->ownBookingLocked($request, $id);

                return [$booking, $this->online->startQr($booking)];
            });
        } catch (PaymentException $e) {
            return $e->toResponse();
        }

        return response()->json([
            'data' => $this->resource($booking),
            'qr' => $this->qr($intent),
        ]);
    }

    public function verify(Request $request, int $id): JsonResponse
    {
        try {
            $booking = DB::transaction(function () use ($request, $id) {
                return $this->online->verify($this->ownBookingLocked($request, $id));
            });
        } catch (PaymentException $e) {
            return $e->toResponse();
        }

        return response()->json(['data' => $this->resource($booking)]);
    }

    /** A customer can only touch their own booking. The row is locked, so two taps cannot both pay. */
    private function ownBookingLocked(Request $request, int $id): Booking
    {
        return Booking::forGuest($request->user()->id)->lockForUpdate()->findOrFail($id);
    }

    private function qr(PaymentIntent $intent): array
    {
        return [
            'reference' => $intent->reference,
            'payload' => $intent->qr_payload,
            'amount' => (float) $intent->amount,
            'currency' => 'USD',
            'merchant' => 'Angkor Stay',
            'expires_at' => $intent->expires_at->toIso8601String(),
            'seconds_left' => max(0, (int) floor(now()->diffInSeconds($intent->expires_at, false))),
        ];
    }

    private function resource(Booking $booking): array
    {
        return (new BookingResource($booking->fresh(['room.roomType.images'])))->resolve();
    }
}
