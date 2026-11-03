<?php

namespace App\Http\Resources;

use App\Models\Booking;
use App\Models\Payment;
use App\Models\PaymentIntent;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * A booking as the customer who made it sees it.
 *
 * @mixin Booking
 */
class BookingResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $room = $this->room;
        $type = $room?->roomType;

        $secondsLeft = null;
        if ($this->status === Booking::STATUS_PENDING && $this->hold_expires_at) {
            // Sent as seconds so a wrong clock on the phone cannot break the countdown.
            $secondsLeft = max(0, (int) floor(now()->diffInSeconds($this->hold_expires_at, false)));
        }

        $paid = $this->payments()->where('status', Payment::STATUS_PAID)->first();
        $refunded = (float) $this->payments()->where('status', Payment::STATUS_REFUNDED)->sum('amount');

        // "Visa ending 4242" or "KHQR" for an online payment, found in the database by its reference.
        $detail = null;
        if ($paid?->method === Payment::METHOD_ONLINE) {
            $detail = PaymentIntent::where('reference', $paid->reference)->first()?->describe();
        }

        return [
            'id' => $this->id,
            'code' => $this->code,
            'status' => $this->status,
            'room_number' => $room?->room_number,
            'room_type' => $type ? [
                'id' => $type->id,
                'name' => $type->name,
                'cover_image' => $type->relationLoaded('images') ? $type->images->first()?->url : null,
            ] : null,
            'check_in_date' => $this->check_in_date->toDateString(),
            'check_out_date' => $this->check_out_date->toDateString(),
            'nights' => $this->nights,
            'guests' => $this->guests,
            'price_per_night' => (float) $this->price_per_night,
            'total_price' => (float) $this->total_price,
            'discount_percent' => $this->discount_percent,
            'discount_amount' => (float) $this->discount_amount,
            'amount_due' => $this->amount_due,
            'payment_choice' => $this->payment_choice,
            'paid' => $paid !== null,
            'payment_method' => $paid?->method,
            'payment_detail' => $detail,
            'refunded_amount' => round($refunded, 2),
            'can_cancel' => $this->canBeCancelledByGuest(),
            'hold_expires_at' => $this->hold_expires_at?->toIso8601String(),
            'hold_seconds_left' => $secondsLeft,
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
