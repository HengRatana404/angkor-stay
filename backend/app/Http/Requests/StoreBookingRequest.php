<?php

namespace App\Http\Requests;

/**
 * A booking needs the same dates as a search, plus the room type and guests.
 */
class StoreBookingRequest extends StayDatesRequest
{
    public function rules(): array
    {
        return array_merge(parent::rules(), [
            'room_type_id' => ['required', 'integer', 'exists:room_types,id'],
            'guests' => ['required', 'integer', 'min:1', 'max:20'],
            'check_in_date' => [
                'required', 'date_format:Y-m-d', 'after_or_equal:today',
                'before_or_equal:' . now()->addDays(self::MAX_DAYS_AHEAD)->toDateString(),
            ],
            'check_out_date' => ['required', 'date_format:Y-m-d', 'after:check_in_date'],
        ]);
    }
}
