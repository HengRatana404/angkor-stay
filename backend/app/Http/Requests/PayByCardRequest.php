<?php

namespace App\Http\Requests;

use Carbon\Carbon;
use Illuminate\Contracts\Validation\Validator;
use Illuminate\Foundation\Http\FormRequest;

/**
 * A simulated card payment. Any card number of 12 to 19 digits works, because no bank is called.
 * What IS checked: the shape of each field, and that the card has not expired. A card is good
 * until the end of the month printed on it, so 11/26 works all through November 2026.
 * The full number and the CVV are never saved: only the brand and the last 4 digits.
 */
class PayByCardRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    protected function prepareForValidation(): void
    {
        // People type spaces and dashes in a card number: ignore them.
        if (is_string($this->input('number'))) {
            $this->merge(['number' => preg_replace('/[\s-]+/', '', $this->input('number'))]);
        }
        if (is_string($this->input('expiry'))) {
            $this->merge(['expiry' => trim($this->input('expiry'))]);
        }
    }

    public function rules(): array
    {
        return [
            'number' => ['required', 'string', 'regex:/^\d{12,19}$/'],
            'holder' => ['required', 'string', 'max:60'],
            'expiry' => ['required', 'string', 'regex:/^(0[1-9]|1[0-2])\/\d{2}$/'],
            'cvv' => ['required', 'string', 'regex:/^\d{3,4}$/'],
        ];
    }

    public function messages(): array
    {
        return [
            'number.required' => 'Enter the card number.',
            'number.regex' => 'The card number must have 12 to 19 digits.',
            'holder.required' => 'Enter the name on the card.',
            'expiry.required' => 'Enter the expiry date.',
            'expiry.regex' => 'Write the expiry date as MM/YY, for example 11/26.',
            'cvv.required' => 'Enter the security code (CVV).',
            'cvv.regex' => 'The security code has 3 or 4 digits.',
        ];
    }

    public function after(): array
    {
        return [
            function (Validator $validator) {
                if ($validator->errors()->has('expiry')) {
                    return;
                }
                if (self::hasExpired((string) $this->input('expiry'))) {
                    $validator->errors()->add('expiry', 'This card has expired.');
                }
            },
        ];
    }

    /** "11/26" is valid until the last second of 30 November 2026 (hotel time). */
    public static function hasExpired(string $expiry): bool
    {
        [$month, $year] = array_map('intval', explode('/', $expiry));

        $lastMoment = Carbon::create(2000 + $year, $month, 1, 0, 0, 0, config('app.timezone'))->endOfMonth();

        return now()->gt($lastMoment);
    }

    /** Visa, Mastercard or Amex, from the first digits. Anything else is just "Card". */
    public static function brandOf(string $number): string
    {
        return match (true) {
            str_starts_with($number, '4') => 'Visa',
            (bool) preg_match('/^(5[1-5]|2[2-7])/', $number) => 'Mastercard',
            (bool) preg_match('/^3[47]/', $number) => 'Amex',
            default => 'Card',
        };
    }
}
