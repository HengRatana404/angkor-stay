<?php

namespace App\Http\Requests\Auth;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Password;

class RegisterRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        // An email or phone only counts as taken once its owner verified it.
        // Someone who never verified can register again.
        return [
            'name' => ['required', 'string', 'max:100'],
            'email' => [
                'required', 'email:rfc', 'max:150',
                Rule::unique('users', 'email')->whereNotNull('email_verified_at'),
            ],
            'phone' => [
                'required', 'string', 'regex:/^[0-9+\- ]{8,20}$/',
                Rule::unique('users', 'phone')->whereNotNull('email_verified_at'),
            ],
            'password' => ['required', 'confirmed', Password::min(8)],
        ];
    }

    public function messages(): array
    {
        return [
            'email.unique' => 'This email is already registered. Please log in.',
            'phone.unique' => 'This phone number is already registered.',
            'phone.regex' => 'Enter a valid phone number (8-20 digits).',
        ];
    }
}
