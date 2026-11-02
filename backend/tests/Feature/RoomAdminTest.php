<?php

namespace Tests\Feature;

use App\Models\Booking;
use App\Models\Room;
use App\Models\RoomType;
use Database\Seeders\RoomSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\MakesBookings;
use Tests\Concerns\MakesUsers;
use Tests\TestCase;

/** Ticket 11: the admin manages room types and rooms. */
class RoomAdminTest extends TestCase
{
    use MakesBookings;
    use MakesUsers;
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RoomSeeder::class);
    }

    private function asAdmin(): void
    {
        Sanctum::actingAs($this->makeUser('admin'));
    }

    private function typeBody(array $over = []): array
    {
        return array_merge([
            'name' => 'Suite', 'description' => 'Big room', 'price_per_night' => 80, 'capacity' => 6,
            'images' => ['https://example.com/a.jpg', 'https://example.com/b.jpg'],
        ], $over);
    }

    public function test_only_the_admin_may_use_these_routes(): void
    {
        Sanctum::actingAs($this->makeUser('customer'));
        $this->getJson('/api/admin/room-types')->assertForbidden();
        $this->postJson('/api/admin/rooms', [])->assertForbidden();

        Sanctum::actingAs($this->makeUser('staff'));
        $this->getJson('/api/admin/room-types')->assertForbidden();
        $this->deleteJson('/api/admin/rooms/1')->assertForbidden();
    }

    public function test_list_shows_types_with_photos_and_rooms(): void
    {
        $this->asAdmin();
        $this->getJson('/api/admin/room-types')
            ->assertOk()
            ->assertJsonCount(3, 'data')
            ->assertJsonCount(5, 'data.0.rooms')
            ->assertJsonPath('data.0.name', 'Single');
    }

    public function test_create_a_room_type_with_photos_and_guests_can_see_it(): void
    {
        $this->asAdmin();
        $this->postJson('/api/admin/room-types', $this->typeBody())
            ->assertCreated()
            ->assertJsonPath('data.name', 'Suite')
            ->assertJsonPath('data.images.0', 'https://example.com/a.jpg');

        $this->assertDatabaseCount('room_types', 4);
        $this->getJson('/api/room-types')->assertJsonCount(4, 'data');
    }

    public function test_create_validates_everything(): void
    {
        $this->asAdmin();
        $this->postJson('/api/admin/room-types', [])->assertStatus(422)
            ->assertJsonValidationErrors(['name', 'description', 'price_per_night', 'capacity']);

        $this->postJson('/api/admin/room-types', $this->typeBody(['name' => 'Single']))
            ->assertStatus(422)->assertJsonValidationErrors('name');

        $this->postJson('/api/admin/room-types', $this->typeBody(['price_per_night' => -5, 'capacity' => 0]))
            ->assertStatus(422)->assertJsonValidationErrors(['price_per_night', 'capacity']);

        $this->postJson('/api/admin/room-types', $this->typeBody(['images' => ['javascript:alert(1)']]))
            ->assertStatus(422)->assertJsonValidationErrors('images.0');
    }

    public function test_a_new_price_does_not_change_old_bookings(): void
    {
        $this->asAdmin();
        $guest = $this->makeUser('customer');
        $b = $this->makeKeptBooking($guest); // Single, 2 nights x 15 = 30
        $single = $this->type('Single');

        $this->patchJson("/api/admin/room-types/{$single->id}", ['price_per_night' => 40])->assertOk();

        $this->assertEquals(30, $b->fresh()->total_price);
        $this->assertEquals(15, $b->fresh()->price_per_night);

        Sanctum::actingAs($guest);
        $new = $this->postJson('/api/bookings', [
            'room_type_id' => $single->id, 'check_in_date' => $this->day(20),
            'check_out_date' => $this->day(21), 'guests' => 1,
        ])->assertCreated();
        $this->assertEquals(40, $new->json('data.total_price'));
    }

    public function test_update_can_replace_photos_and_leave_them_alone(): void
    {
        $this->asAdmin();
        $id = $this->type('Single')->id;

        $this->patchJson("/api/admin/room-types/{$id}", ['name' => 'Single Plus'])
            ->assertOk()->assertJsonCount(3, 'data.images');

        $this->patchJson("/api/admin/room-types/{$id}", ['images' => ['https://example.com/only.jpg']])
            ->assertOk()->assertJsonCount(1, 'data.images');
    }

    public function test_cannot_delete_a_type_that_still_has_rooms_but_an_empty_one_goes(): void
    {
        $this->asAdmin();
        $this->deleteJson('/api/admin/room-types/' . $this->type('VIP')->id)
            ->assertStatus(409)->assertJsonPath('code', 'has_rooms');

        $id = $this->postJson('/api/admin/room-types', $this->typeBody())->json('data.id');
        $this->deleteJson("/api/admin/room-types/{$id}")->assertOk();
        $this->assertDatabaseMissing('room_types', ['id' => $id]);
        $this->assertDatabaseMissing('room_type_images', ['room_type_id' => $id]);
    }

    public function test_add_a_room_and_it_can_be_booked(): void
    {
        $this->asAdmin();
        $type = $this->type('VIP');

        $this->postJson('/api/admin/rooms', ['room_number' => '306', 'room_type_id' => $type->id, 'floor' => 3])
            ->assertCreated()->assertJsonPath('data.status', 'available');

        $this->assertSame(6, Room::where('room_type_id', $type->id)->count());
    }

    public function test_room_number_must_be_new_and_the_type_must_exist(): void
    {
        $this->asAdmin();
        $type = $this->type('VIP');

        $this->postJson('/api/admin/rooms', ['room_number' => '101', 'room_type_id' => $type->id, 'floor' => 1])
            ->assertStatus(422)->assertJsonValidationErrors('room_number');
        $this->postJson('/api/admin/rooms', ['room_number' => '999', 'room_type_id' => 9999, 'floor' => 1])
            ->assertStatus(422)->assertJsonValidationErrors('room_type_id');
    }

    public function test_cannot_delete_or_retype_a_room_that_has_bookings(): void
    {
        $this->asAdmin();
        $room = Room::where('room_number', '101')->first();
        $this->makeKeptBooking($this->makeUser('customer'), ['room' => $room]);

        $this->deleteJson("/api/admin/rooms/{$room->id}")->assertStatus(409)->assertJsonPath('code', 'room_has_bookings');
        $this->patchJson("/api/admin/rooms/{$room->id}", ['room_type_id' => $this->type('VIP')->id])
            ->assertStatus(409);

        $this->assertDatabaseHas('rooms', ['id' => $room->id, 'room_type_id' => $room->room_type_id]);
    }

    public function test_cannot_put_a_room_in_maintenance_while_a_guest_is_coming(): void
    {
        $this->asAdmin();
        $room = Room::where('room_number', '101')->first();
        $this->makeKeptBooking($this->makeUser('customer'), ['room' => $room]);

        $this->patchJson("/api/admin/rooms/{$room->id}", ['status' => 'maintenance'])
            ->assertStatus(409)->assertJsonPath('code', 'room_has_upcoming');

        // A free room can go to maintenance, and a room with no bookings can be deleted.
        $free = Room::where('room_number', '102')->first();
        $this->patchJson("/api/admin/rooms/{$free->id}", ['status' => 'maintenance'])->assertOk();
        $this->deleteJson("/api/admin/rooms/{$free->id}")->assertOk();
    }

    public function test_a_room_without_bookings_can_change_type(): void
    {
        $this->asAdmin();
        $room = Room::where('room_number', '101')->first();
        $vip = $this->type('VIP');

        $this->patchJson("/api/admin/rooms/{$room->id}", ['room_type_id' => $vip->id])
            ->assertOk()->assertJsonPath('data.room_type_id', $vip->id);
    }
}
