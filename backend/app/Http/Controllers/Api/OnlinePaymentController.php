<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\BookingResource;
use App\Models\Booking;
use App\Payments\PaymentException;
use App\Services\OnlinePaymentService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * The guest pays online. Three steps:
 *  1. pay-online      the guest chooses it. We save the discount and open the payment page.
 *  2. (the guest pays on Stripe's page, or presses the demo button)
 *  3. verify-payment  we ask Stripe if it really happened. Only then is the booking confirmed.
 */
class OnlinePaymentController extends Controller
{
    public function __construct(private OnlinePaymentService $online)
    {
    }

    public function start(Request $request, int $id): JsonResponse
    {
        try {
            [$booking, $info] = DB::transaction(function () use ($request, $id) {
                $booking = $this->ownBookingLocked($request, $id);

                return [$booking, $this->online->start($booking, $request->getSchemeAndHttpHost())];
            });
        } catch (PaymentException $e) {
            return $e->toResponse();
        }

        return response()->json([
            'data' => $this->resource($booking),
            'mode' => $info['mode'],
            'checkout_url' => $info['checkout_url'],
            'checkout_hint' => $info['hint'],
        ]);
    }

    public function verify(Request $request, int $id): JsonResponse
    {
        try {
            $result = DB::transaction(function () use ($request, $id) {
                return $this->online->verify($this->ownBookingLocked($request, $id));
            });
        } catch (PaymentException $e) {
            return $e->toResponse();
        }

        if ($result['outcome'] === 'refunded') {
            return response()->json([
                'message' => $result['message'],
                'code' => $result['code'],
                'data' => $this->resource($result['booking']),
            ], 409);
        }

        return response()->json(['data' => $this->resource($result['booking'])]);
    }

    public function demoPay(Request $request, int $id): JsonResponse
    {
        try {
            $booking = DB::transaction(function () use ($request, $id) {
                return $this->online->demoPay($this->ownBookingLocked($request, $id));
            });
        } catch (PaymentException $e) {
            return $e->toResponse();
        }

        return response()->json(['data' => $this->resource($booking)]);
    }

    /** A customer can only touch their own booking. The row is locked, so two taps cannot both pay. */
    private function ownBookingLocked(Request $request, int $id): Booking
    {
        return Booking::where('user_id', $request->user()->id)->lockForUpdate()->findOrFail($id);
    }

    private function resource(Booking $booking): array
    {
        return (new BookingResource($booking->fresh(['room.roomType.images'])))->resolve();
    }
}
