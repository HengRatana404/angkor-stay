<?php

namespace Tests\Feature;

use App\Models\Room;
use App\Models\RoomType;
use Database\Seeders\RoomSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class RoomTypeApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_seeder_makes_3_types_15_rooms_and_9_photos(): void
    {
        $this->seed(RoomSeeder::class);

        $this->assertSame(3, RoomType::count());
        $this->assertSame(15, Room::count());
        $this->assertSame(5, Room::where('room_type_id', RoomType::where('name', 'Single')->value('id'))->count());
        $this->assertDatabaseCount('room_type_images', 9);
    }

    public function test_seeder_can_run_twice_without_duplicates(): void
    {
        $this->seed(RoomSeeder::class);
        $this->seed(RoomSeeder::class);

        $this->assertSame(3, RoomType::count());
        $this->assertSame(15, Room::count());
        $this->assertDatabaseCount('room_type_images', 9);
    }

    public function test_seeded_prices_and_capacities_match_the_plan(): void
    {
        $this->seed(RoomSeeder::class);

        $expected = ['Single' => [15, 2], 'Double' => [25, 4], 'VIP' => [50, 6]];
        foreach ($expected as $name => [$price, $capacity]) {
            $type = RoomType::where('name', $name)->first();
            $this->assertEquals($price, $type->price_per_night, $name);
            $this->assertSame($capacity, $type->capacity, $name);
        }
    }

    public function test_list_is_public_and_sorted_by_price(): void
    {
        $this->seed(RoomSeeder::class);

        $this->getJson('/api/room-types')
            ->assertOk()
            ->assertJsonCount(3, 'data')
            ->assertJsonPath('data.0.name', 'Single')
            ->assertJsonPath('data.1.name', 'Double')
            ->assertJsonPath('data.2.name', 'VIP')
            ->assertJsonStructure(['data' => [['id', 'name', 'description', 'price_per_night', 'capacity', 'total_rooms', 'cover_image', 'images']]]);
    }

    public function test_list_gives_price_as_a_number_and_a_cover_photo(): void
    {
        $this->seed(RoomSeeder::class);

        $first = $this->getJson('/api/room-types')->json('data.0');

        // JSON writes 15.0 as 15. Either way it is a number, not the text "15.00".
        $this->assertIsNotString($first['price_per_night']);
        $this->assertEquals(15, $first['price_per_night']);
        $this->assertStringStartsWith('https://', $first['cover_image']);
        $this->assertSame($first['images'][0], $first['cover_image']);
        $this->assertCount(3, $first['images']);
    }

    public function test_total_rooms_does_not_count_rooms_in_maintenance(): void
    {
        $this->seed(RoomSeeder::class);
        Room::where('room_number', '301')->update(['status' => Room::STATUS_MAINTENANCE]);

        $vip = collect($this->getJson('/api/room-types')->json('data'))->firstWhere('name', 'VIP');

        $this->assertSame(4, $vip['total_rooms']);
    }

    public function test_show_returns_one_type_with_its_photos(): void
    {
        $this->seed(RoomSeeder::class);
        $vip = RoomType::where('name', 'VIP')->first();

        $this->getJson("/api/room-types/{$vip->id}")
            ->assertOk()
            ->assertJsonPath('data.name', 'VIP')
            ->assertJsonPath('data.capacity', 6)
            ->assertJsonPath('data.total_rooms', 5)
            ->assertJsonCount(3, 'data.images');
    }

    public function test_unknown_room_type_is_404(): void
    {
        $this->getJson('/api/room-types/999')->assertNotFound();
    }

    public function test_a_room_type_id_that_is_not_a_number_is_404_not_a_server_error(): void
    {
        // Found by the stress test: "abc" used to reach the database and give a 500.
        $this->getJson('/api/room-types/abc')->assertNotFound();
        $this->getJson('/api/room-types/1%20OR%201=1')->assertNotFound();
        // A number too big for the database used to give a 500 as well.
        $this->getJson('/api/room-types/99999999999999999999')->assertNotFound();
    }

    public function test_a_room_type_with_rooms_cannot_be_deleted(): void
    {
        $this->seed(RoomSeeder::class);

        $this->expectException(\Illuminate\Database\QueryException::class);
        RoomType::where('name', 'Single')->first()->delete();
    }

    public function test_deleting_a_room_type_without_rooms_removes_its_photos(): void
    {
        $type = RoomType::create(['name' => 'Suite', 'description' => 'x', 'price_per_night' => 90, 'capacity' => 2]);
        $type->images()->create(['url' => 'https://example.com/a.jpg', 'sort_order' => 0]);

        $type->delete();

        $this->assertDatabaseCount('room_type_images', 0);
    }
}
