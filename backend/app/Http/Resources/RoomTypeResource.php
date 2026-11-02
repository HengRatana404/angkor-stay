<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class RoomTypeResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'description' => $this->description,
            'price_per_night' => (float) $this->price_per_night,
            'capacity' => $this->capacity,
            // Rooms that can be booked (not in maintenance).
            'total_rooms' => $this->whenCounted('rooms'),
            // Only there when dates were sent: rooms free for those nights.
            'available_rooms' => $this->when(
                array_key_exists('available_rooms', $this->resource->getAttributes()),
                fn () => (int) $this->resource->getAttribute('available_rooms'),
            ),
            'cover_image' => $this->relationLoaded('images')
                ? $this->images->first()?->url
                : null,
            'images' => $this->when(
                $this->relationLoaded('images'),
                fn () => $this->images->pluck('url')->values(),
            ),
        ];
    }
}
