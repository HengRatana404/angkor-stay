<?php

namespace App\Http\Resources;

use App\Models\Booking;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * A booking as staff see it: the guest, the payments and who did what.
 *
 * @mixin Booking
 */
class StaffBookingResource extends JsonResource
{
    private function person($user): ?array
    {
        return $user ? ['id' => $user->id, 'name' => $user->name] : null;
    }

    public function toArray(Request $request): array
    {
        $room = $this->room;
        $guest = $this->user;

        $secondsLeft = null;
        if ($this->status === Booking::STATUS_PENDING && $this->hold_expires_at && ! $this->isExpiredHold()) {
            $secondsLeft = max(0, (int) floor(now()->diffInSeconds($this->hold_expires_at, false)));
        }

        return [
            'id' => $this->id,
            'code' => $this->code,
            'status' => $this->status,
            'room_number' => $room?->room_number,
            'room_type' => $room?->roomType ? ['id' => $room->roomType->id, 'name' => $room->roomType->name] : null,
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
            'paid' => $this->isPaid(),
            'hold_seconds_left' => $secondsLeft,
            'is_expired_hold' => $this->isExpiredHold(),
            'guest' => $guest ? [
                'id' => $guest->id,
                'name' => $guest->name,
                'phone' => $guest->phone,
                'email' => $guest->email,
            ] : null,
            'payments' => $this->payments->map(fn ($p) => [
                'id' => $p->id,
                'amount' => (float) $p->amount,
                'method' => $p->method,
                'status' => $p->status,
                'received_by' => $this->person($p->receivedBy),
                'paid_at' => $p->paid_at?->toIso8601String(),
            ])->values(),
            'checked_in_at' => $this->checked_in_at?->toIso8601String(),
            'checked_in_by' => $this->person($this->checkedInBy),
            'checked_out_at' => $this->checked_out_at?->toIso8601String(),
            'checked_out_by' => $this->person($this->checkedOutBy),
            // The server decides what staff may do, so the app never has to guess.
            'actions' => [
                'can_take_payment' => $this->canTakePayment(),
                'can_check_in' => $this->canCheckIn(),
                'check_in_problem' => $this->canCheckIn() ? null : $this->checkInProblem(),
                'can_check_out' => $this->canCheckOut(),
            ],
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
