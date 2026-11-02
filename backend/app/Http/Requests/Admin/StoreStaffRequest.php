<?php

namespace App\Http\Requests\Admin;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Password;

class StoreStaffRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true; // the route is already limited to admins
    }

    public function rules(): array
    {
        return [
            'name' => ['required', 'string', 'max:100'],
            // Any account with this email, even an unverified customer one,
            // blocks it. A staff member must not share an email with someone else.
            'email' => ['required', 'email:rfc', 'max:150', 'unique:users,email'],
            'phone' => [
                'required', 'string', 'regex:/^[0-9+\- ]{8,20}$/',
                Rule::unique('users', 'phone')->whereNotNull('email_verified_at'),
            ],
            'password' => ['required', 'string', Password::min(8)],
        ];
    }

    public function messages(): array
    {
        return [
            'email.unique' => 'Another account already uses this email.',
            'phone.unique' => 'Another account already uses this phone number.',
            'phone.regex' => 'Enter a valid phone number (8-20 digits).',
        ];
    }
}
