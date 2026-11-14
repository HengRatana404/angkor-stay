<?php

namespace Database\Seeders;

use App\Models\Room;
use App\Models\RoomType;
use Illuminate\Database\Seeder;

class RoomSeeder extends Seeder
{
    private function photo(int $id): string
    {
        return "https://images.pexels.com/photos/{$id}/pexels-photo-{$id}.jpeg?auto=compress&cs=tinysrgb&w=800";
    }

    /** Safe to run again: it updates what exists and never makes duplicates. */
    public function run(): void
    {
        $types = [
            [
                'name' => 'Single',
                'description' => 'A bright, quiet room with one comfortable bed, air conditioning, free Wi-Fi and a private bathroom. Good for one traveller or a short stay.',
                'price_per_night' => 15,
                'capacity' => 2,
                'floor' => 1,
                'first_room' => 101,
                'photos' => [39894364, 39894350, 31488380],
            ],
            [
                'name' => 'Double',
                'description' => 'A roomy room with a large bed, a small seating area, air conditioning, free Wi-Fi and a private bathroom. Good for families and friends.',
                'price_per_night' => 25,
                'capacity' => 4,
                'floor' => 2,
                'first_room' => 201,
                'photos' => [36916378, 39894345, 14750392],
            ],
            [
                'name' => 'VIP',
                'description' => 'Our best suite with a big bed, a living area, large windows, a minibar, free Wi-Fi and a bathroom with a bathtub. Room for a whole group.',
                'price_per_night' => 50,
                'capacity' => 6,
                'floor' => 3,
                'first_room' => 301,
                'photos' => [34496702, 7722164, 34496715],
            ],
        ];

        foreach ($types as $data) {
            $type = RoomType::updateOrCreate(
                ['name' => $data['name']],
                [
                    'description' => $data['description'],
                    'price_per_night' => $data['price_per_night'],
                    'capacity' => $data['capacity'],
                ],
            );

            foreach ($data['photos'] as $order => $photoId) {
                $type->images()->updateOrCreate(
                    ['sort_order' => $order],
                    ['url' => $this->photo($photoId)],
                );
            }

            for ($i = 0; $i < 5; $i++) {
                Room::updateOrCreate(
                    ['room_number' => (string) ($data['first_room'] + $i)],
                    ['room_type_id' => $type->id, 'floor' => $data['floor']],
                );
            }
        }
    }
}
