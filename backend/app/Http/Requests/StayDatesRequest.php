<?php

namespace App\Http\Requests;

use Illuminate\Contracts\Validation\Validator;
use Illuminate\Foundation\Http\FormRequest;

/**
 * Check-in and check-out dates, for looking at free rooms.
 * Both dates are optional together: without them the room list
 * simply has no "rooms left" numbers.
 */
class StayDatesRequest extends FormRequest
{
    public const MAX_NIGHTS = 30;
    public const MAX_DAYS_AHEAD = 365;

    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'check_in_date' => [
                'required_with:check_out_date', 'date_format:Y-m-d',
                'after_or_equal:today', 'before_or_equal:' . now()->addDays(self::MAX_DAYS_AHEAD)->toDateString(),
            ],
            'check_out_date' => [
                'required_with:check_in_date', 'date_format:Y-m-d', 'after:check_in_date',
            ],
        ];
    }

    public function messages(): array
    {
        return [
            'check_in_date.after_or_equal' => 'Check-in cannot be in the past.',
            'check_in_date.before_or_equal' => 'You can book up to ' . self::MAX_DAYS_AHEAD . ' days ahead.',
            'check_out_date.after' => 'Check-out must be after check-in.',
        ];
    }

    public function after(): array
    {
        return [
            function (Validator $validator) {
                if ($validator->errors()->isNotEmpty()) {
                    return;
                }
                $in = $this->input('check_in_date');
                $out = $this->input('check_out_date');
                if ($in && $out && $this->nights() > self::MAX_NIGHTS) {
                    $validator->errors()->add(
                        'check_out_date',
                        'You can stay up to ' . self::MAX_NIGHTS . ' nights in one booking.',
                    );
                }
            },
        ];
    }

    public function nights(): int
    {
        return (int) \Illuminate\Support\Carbon::parse($this->input('check_in_date'))
            ->diffInDays(\Illuminate\Support\Carbon::parse($this->input('check_out_date')));
    }
}
