<?php

namespace App\Http\Requests\Admin;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/** Create (POST: every field needed) or change (PATCH: only the fields sent) a room type. */
class RoomTypeRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $req = $this->isMethod('post') ? 'required' : 'sometimes';
        $ignore = $this->route('id');

        return [
            'name' => [$req, 'string', 'max:60', Rule::unique('room_types', 'name')->ignore($ignore)],
            'description' => [$req, 'string', 'max:2000'],
            'price_per_night' => [$req, 'numeric', 'min:1', 'max:100000'],
            'capacity' => [$req, 'integer', 'min:1', 'max:20'],
            // Photos are links. The list sent here replaces the old list; the first one is the cover.
            'images' => ['sometimes', 'array', 'max:10'],
            'images.*' => ['required', 'url:http,https', 'max:500'],
        ];
    }

    public function messages(): array
    {
        return [
            'name.unique' => 'There is already a room type with this name.',
            'images.*.url' => 'Each photo must be a web link starting with http:// or https://.',
        ];
    }
}
