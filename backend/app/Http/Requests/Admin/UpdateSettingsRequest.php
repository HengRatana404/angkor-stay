<?php

namespace App\Http\Requests\Admin;

use App\Services\SettingsService;
use Illuminate\Contracts\Validation\Validator;
use Illuminate\Foundation\Http\FormRequest;

class UpdateSettingsRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true; // the route is already limited to admins
    }

    protected function prepareForValidation(): void
    {
        // Clean the list first: trim, make "10.0.0.5" into "10.0.0.5/32", drop doubles.
        // Entries that are not networks are kept as they are, so validation can reject them.
        $networks = $this->input('allowed_networks');

        if (is_array($networks)) {
            $clean = [];
            foreach ($networks as $entry) {
                if (! is_string($entry) || trim($entry) === '') {
                    continue;
                }
                $clean[] = SettingsService::normalizeNetwork($entry) ?? trim($entry);
            }
            $this->merge(['allowed_networks' => array_values(array_unique($clean))]);
        }
    }

    public function rules(): array
    {
        return [
            'online_discount_percent' => ['required', 'integer', 'between:0,50'],
            'check_in_time' => ['required', 'date_format:H:i'],
            'check_out_time' => ['required', 'date_format:H:i'],
            'staff_login_restricted' => ['required', 'boolean'],
            'allowed_networks' => ['required', 'array', 'min:1', 'max:20'],
            'allowed_networks.*' => ['string', function (string $attribute, mixed $value, \Closure $fail) {
                if (SettingsService::normalizeNetwork((string) $value) === null) {
                    $fail("\"{$value}\" is not a network. Use a form like 192.168.1.0/24.");
                }
            }],
            'demo_payment_mode' => ['required', 'boolean'],
        ];
    }

    public function messages(): array
    {
        return [
            'online_discount_percent.between' => 'The discount must be between 0 and 50 percent.',
            'check_in_time.date_format' => 'Use a time like 14:00.',
            'check_out_time.date_format' => 'Use a time like 12:00.',
            'allowed_networks.min' => 'Add at least one network.',
        ];
    }

    public function after(): array
    {
        return [
            function (Validator $validator) {
                if ($validator->errors()->isNotEmpty()) {
                    return;
                }

                // Lock-out guard: the admin must still be able to log in
                // from the device they are using right now.
                if ($this->boolean('staff_login_restricted')
                    && ! app(SettingsService::class)->isInAllowedNetwork($this->ip(), $this->input('allowed_networks'))) {
                    $validator->errors()->add(
                        'allowed_networks',
                        "These networks do not include the device you are using now ({$this->ip()}), "
                        . 'so you would lock yourself out. Add this device\'s network or switch the rule off.',
                    );
                }
            },
        ];
    }
}
