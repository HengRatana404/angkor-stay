<?php

namespace Tests\Concerns;

use App\Models\Booking;
use App\Models\Room;
use App\Models\RoomType;
use App\Models\User;

trait MakesBookings
{
    protected function day(int $daysFromToday): string
    {
        return now()->addDays($daysFromToday)->toDateString();
    }

    /**
     * Saves a booking straight into the database, so a test can pick any
     * status, hold time and dates.
     *
     * Options: room, in, out (days from today), status, hold, choice.
     * Pass 'hold' => null for a booking kept with no countdown.
     */
    protected function makeBooking(User $guest, array $o = []): Booking
    {
        $room = $o['room'] ?? Room::where('room_number', '101')->firstOrFail();
        $in = $o['in'] ?? 5;
        $out = $o['out'] ?? ($in + 2);
        $nights = $out - $in;
        $price = (float) $room->roomType->price_per_night;

        return Booking::create([
            'user_id' => $guest->id,
            'room_id' => $room->id,
            'check_in_date' => $this->day($in),
            'check_out_date' => $this->day($out),
            'guests' => 1,
            'nights' => $nights,
            'price_per_night' => $price,
            'total_price' => $nights * $price,
            'status' => $o['status'] ?? Booking::STATUS_PENDING,
            'payment_choice' => $o['choice'] ?? null,
            'hold_expires_at' => array_key_exists('hold', $o) ? $o['hold'] : now()->addMinutes(5),
        ]);
    }

    /** A booking the guest chose to pay at the hotel: pending, kept, no countdown. */
    protected function makeKeptBooking(User $guest, array $o = []): Booking
    {
        return $this->makeBooking($guest, array_merge(['hold' => null, 'choice' => Booking::CHOICE_HOTEL], $o));
    }

    /** Puts 4 of the 5 VIP rooms into maintenance, so only room 301 can be booked. */
    protected function leaveOnlyOneVipRoom(): void
    {
        Room::whereIn('room_number', ['302', '303', '304', '305'])
            ->update(['status' => Room::STATUS_MAINTENANCE]);
    }

    protected function type(string $name): RoomType
    {
        return RoomType::where('name', $name)->firstOrFail();
    }
}
