<?php

namespace App\Http\Requests\Staff;

use App\Models\Booking;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class SearchBookingsRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true; // the route is already limited to staff and admin
    }

    public function rules(): array
    {
        return [
            'search' => ['nullable', 'string', 'max:100'],
            'status' => ['nullable', 'string', Rule::in(Booking::STATUSES)],
        ];
    }

    public function messages(): array
    {
        return [
            'status.in' => 'Unknown status.',
        ];
    }
}
