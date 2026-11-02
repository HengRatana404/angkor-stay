<?php

namespace App\Http\Requests\Admin;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Password;

class UpdateStaffRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true; // the route is already limited to admins
    }

    public function rules(): array
    {
        $id = (int) $this->route('id');

        return [
            'name' => ['sometimes', 'required', 'string', 'max:100'],
            'phone' => [
                'sometimes', 'required', 'string', 'regex:/^[0-9+\- ]{8,20}$/',
                Rule::unique('users', 'phone')->ignore($id)->whereNotNull('email_verified_at'),
            ],
            'is_active' => ['sometimes', 'required', 'boolean'],
            // The admin can set a new password for a staff member who forgot theirs.
            'password' => ['sometimes', 'required', 'string', Password::min(8)],
        ];
    }

    public function messages(): array
    {
        return [
            'phone.unique' => 'Another account already uses this phone number.',
            'phone.regex' => 'Enter a valid phone number (8-20 digits).',
        ];
    }
}
