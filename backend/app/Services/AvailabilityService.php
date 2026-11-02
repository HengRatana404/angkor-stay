<?php

namespace App\Services;

use App\Models\Booking;
use App\Models\Room;
use App\Models\RoomType;
use Illuminate\Database\Eloquent\Builder;

class AvailabilityService
{
    /**
     * Rooms of one type that nobody has for the given nights
     * and that are not in maintenance.
     */
    public function freeRooms(RoomType $type, string $checkIn, string $checkOut): Builder
    {
        return Room::query()
            ->where('room_type_id', $type->id)
            ->where('status', Room::STATUS_AVAILABLE)
            ->whereDoesntHave('bookings', function (Builder $q) use ($checkIn, $checkOut) {
                $q->blocking()->overlapping($checkIn, $checkOut);
            });
    }

    public function countFree(RoomType $type, string $checkIn, string $checkOut): int
    {
        return $this->freeRooms($type, $checkIn, $checkOut)->count();
    }
}
