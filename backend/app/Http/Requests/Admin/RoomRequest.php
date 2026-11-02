<?php

namespace App\Http\Requests\Admin;

use App\Models\Room;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/** Create (POST) or change (PATCH) one room. */
class RoomRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $req = $this->isMethod('post') ? 'required' : 'sometimes';

        return [
            'room_number' => [$req, 'string', 'max:10', 'regex:/^[A-Za-z0-9\-]+$/', Rule::unique('rooms', 'room_number')->ignore($this->route('id'))],
            'room_type_id' => [$req, 'integer', 'exists:room_types,id'],
            'floor' => [$req, 'integer', 'min:0', 'max:100'],
            'status' => ['sometimes', Rule::in([Room::STATUS_AVAILABLE, Room::STATUS_MAINTENANCE])],
        ];
    }

    public function messages(): array
    {
        return [
            'room_number.unique' => 'There is already a room with this number.',
            'room_number.regex' => 'Use letters, numbers and dashes only.',
        ];
    }
}
