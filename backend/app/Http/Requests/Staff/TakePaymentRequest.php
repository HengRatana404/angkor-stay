<?php

namespace App\Http\Requests\Staff;

use App\Models\Payment;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class TakePaymentRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true; // the route is already limited to staff and admin
    }

    /**
     * Only the method is sent. The amount is always the booking's saved total,
     * so staff cannot type a wrong amount. There is no discount at the hotel.
     */
    public function rules(): array
    {
        return [
            'method' => ['required', 'string', Rule::in(Payment::HOTEL_METHODS)],
        ];
    }

    public function messages(): array
    {
        return [
            'method.required' => 'Choose how the guest paid.',
            'method.in' => 'Choose KHQR, cash or card.',
        ];
    }
}
