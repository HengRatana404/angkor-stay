<?php

namespace App\Http\Requests\Auth;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/** The guest changes their own name or phone. The email and the role can never be changed here. */
class UpdateProfileRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'name' => ['sometimes', 'required', 'string', 'max:100'],
            'phone' => [
                'sometimes', 'required', 'string', 'regex:/^[0-9+\- ]{8,20}$/',
                Rule::unique('users', 'phone')->ignore($this->user()->id)->whereNotNull('email_verified_at'),
            ],
        ];
    }

    public function messages(): array
    {
        return [
            'phone.unique' => 'This phone number is already registered.',
            'phone.regex' => 'Enter a valid phone number (8-20 digits).',
        ];
    }
}
