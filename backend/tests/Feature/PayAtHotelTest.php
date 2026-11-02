<?php

namespace Tests\Feature;

use App\Models\Booking;
use App\Models\Room;
use Database\Seeders\RoomSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\MakesBookings;
use Tests\Concerns\MakesUsers;
use Tests\TestCase;

/** The customer's side: "I will pay at the hotel". */
class PayAtHotelTest extends TestCase
{
    use MakesBookings;
    use MakesUsers;
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RoomSeeder::class);
    }

    private function bookViaApi($guest, string $type = 'VIP')
    {
        Sanctum::actingAs($guest);

        return $this->postJson('/api/bookings', [
            'room_type_id' => $this->type($type)->id,
            'check_in_date' => $this->day(10),
            'check_out_date' => $this->day(12),
            'guests' => 2,
        ])->assertCreated();
    }

    private function payAtHotel($guest, int $bookingId)
    {
        Sanctum::actingAs($guest);

        return $this->postJson("/api/bookings/{$bookingId}/pay-at-hotel");
    }

    public function test_choosing_to_pay_at_the_hotel_keeps_the_room_with_no_countdown(): void
    {
        $guest = $this->makeUser('customer');
        $id = $this->bookViaApi($guest)->json('data.id');

        $this->payAtHotel($guest, $id)
            ->assertOk()
            ->assertJsonPath('data.status', 'pending')
            ->assertJsonPath('data.payment_choice', 'hotel')
            ->assertJsonPath('data.hold_seconds_left', null)
            ->assertJsonPath('data.hold_expires_at', null)
            ->assertJsonPath('data.paid', false);

        $booking = Booking::findOrFail($id);
        $this->assertNull($booking->hold_expires_at);
        $this->assertSame('hotel', $booking->payment_choice);
        $this->assertSame(0, $booking->payments()->count());
    }

    public function test_there_is_no_discount_for_paying_at_the_hotel(): void
    {
        $guest = $this->makeUser('customer');
        $created = $this->bookViaApi($guest)->json('data');

        $kept = $this->payAtHotel($guest, $created['id'])->assertOk()->json('data');

        // 2 nights x $50 = $100, the full price.
        $this->assertSame(100, $kept['total_price']);
        $this->assertSame($created['total_price'], $kept['total_price']);
    }

    public function test_a_kept_room_stays_taken_after_five_minutes(): void
    {
        $this->leaveOnlyOneVipRoom();
        $guest = $this->makeUser('customer');
        $id = $this->bookViaApi($guest)->json('data.id');
        $this->payAtHotel($guest, $id)->assertOk();

        $this->travel(30)->minutes();

        $other = $this->makeUser('customer');
        Sanctum::actingAs($other);
        $this->postJson('/api/bookings', [
            'room_type_id' => $this->type('VIP')->id,
            'check_in_date' => $this->day(10),
            'check_out_date' => $this->day(12),
            'guests' => 2,
        ])->assertStatus(409)->assertJsonPath('code', 'no_room_left');
    }

    public function test_pressing_the_button_twice_does_no_harm(): void
    {
        $guest = $this->makeUser('customer');
        $id = $this->bookViaApi($guest)->json('data.id');

        $this->payAtHotel($guest, $id)->assertOk();
        $this->payAtHotel($guest, $id)->assertOk()->assertJsonPath('data.payment_choice', 'hotel');
    }

    public function test_after_the_five_minutes_the_choice_is_refused_and_the_room_is_free(): void
    {
        $this->leaveOnlyOneVipRoom();
        $guest = $this->makeUser('customer');
        $id = $this->bookViaApi($guest)->json('data.id');

        $this->travel(6)->minutes();

        $this->payAtHotel($guest, $id)->assertStatus(409)->assertJsonPath('code', 'hold_expired');

        $booking = Booking::findOrFail($id);
        $this->assertNull($booking->payment_choice);
        $this->assertNotNull($booking->hold_expires_at);

        // Someone else can have the room.
        $other = $this->makeUser('customer');
        Sanctum::actingAs($other);
        $this->postJson('/api/bookings', [
            'room_type_id' => $this->type('VIP')->id,
            'check_in_date' => $this->day(10),
            'check_out_date' => $this->day(12),
            'guests' => 2,
        ])->assertCreated();
    }

    public function test_nobody_can_choose_for_someone_elses_booking(): void
    {
        $id = $this->bookViaApi($this->makeUser('customer'))->json('data.id');

        $this->payAtHotel($this->makeUser('customer'), $id)->assertNotFound();

        $this->assertNull(Booking::findOrFail($id)->payment_choice);
    }

    public function test_it_needs_a_login(): void
    {
        $this->postJson('/api/bookings/1/pay-at-hotel')->assertUnauthorized();
    }

    public function test_a_booking_that_is_no_longer_pending_cannot_be_changed(): void
    {
        $guest = $this->makeUser('customer');

        foreach ([Booking::STATUS_CONFIRMED, Booking::STATUS_CANCELLED, Booking::STATUS_CHECKED_IN, Booking::STATUS_NO_SHOW] as $status) {
            $booking = $this->makeBooking($guest, ['status' => $status, 'hold' => null]);

            $this->payAtHotel($guest, $booking->id)
                ->assertStatus(422)
                ->assertJsonPath('code', 'not_pending');
        }
    }

    public function test_a_customer_keeps_at_most_three_unpaid_rooms(): void
    {
        $guest = $this->makeUser('customer');
        $rooms = Room::whereIn('room_number', ['101', '102', '103', '104'])->orderBy('room_number')->get();

        $kept = [];
        foreach ($rooms->take(3) as $room) {
            $kept[] = $this->makeKeptBooking($guest, ['room' => $room]);
        }
        $fourth = $this->makeBooking($guest, ['room' => $rooms[3]]);

        $this->payAtHotel($guest, $fourth->id)
            ->assertStatus(409)
            ->assertJsonPath('code', 'too_many_unpaid');
        $this->assertNotNull($fourth->fresh()->hold_expires_at);

        // Letting one go makes space.
        Sanctum::actingAs($guest);
        $this->postJson("/api/bookings/{$kept[0]->id}/release")->assertOk();

        $this->payAtHotel($guest, $fourth->id)->assertOk();
    }

    public function test_old_unpaid_bookings_do_not_count_against_the_limit(): void
    {
        $guest = $this->makeUser('customer');
        $rooms = Room::whereIn('room_number', ['101', '102', '103', '104'])->orderBy('room_number')->get();

        // Three stays that ended already: nobody came, ticket 10 will tidy them.
        foreach ($rooms->take(3) as $room) {
            $this->makeKeptBooking($guest, ['room' => $room, 'in' => -10, 'out' => -8]);
        }
        $fresh = $this->makeBooking($guest, ['room' => $rooms[3]]);

        $this->payAtHotel($guest, $fresh->id)->assertOk();
    }

    public function test_kept_rooms_do_not_use_up_the_two_running_holds(): void
    {
        $guest = $this->makeUser('customer');
        foreach (Room::whereIn('room_number', ['101', '102', '103'])->get() as $room) {
            $this->makeKeptBooking($guest, ['room' => $room]);
        }

        Sanctum::actingAs($guest);
        $payload = [
            'room_type_id' => $this->type('VIP')->id,
            'check_in_date' => $this->day(20),
            'check_out_date' => $this->day(21),
            'guests' => 1,
        ];

        $this->postJson('/api/bookings', $payload)->assertCreated();
        $this->postJson('/api/bookings', $payload)->assertCreated();
        $this->postJson('/api/bookings', $payload)->assertStatus(409)->assertJsonPath('code', 'too_many_holds');
    }

    public function test_the_guest_can_cancel_a_kept_room_and_it_is_free_again(): void
    {
        $this->leaveOnlyOneVipRoom();
        $guest = $this->makeUser('customer');
        $id = $this->bookViaApi($guest)->json('data.id');
        $this->payAtHotel($guest, $id)->assertOk();

        Sanctum::actingAs($guest);
        $this->postJson("/api/bookings/{$id}/release")->assertOk();
        $this->assertSame('cancelled', Booking::findOrFail($id)->status);

        $other = $this->makeUser('customer');
        Sanctum::actingAs($other);
        $this->postJson('/api/bookings', [
            'room_type_id' => $this->type('VIP')->id,
            'check_in_date' => $this->day(10),
            'check_out_date' => $this->day(12),
            'guests' => 2,
        ])->assertCreated();
    }

    public function test_every_booking_has_a_short_code(): void
    {
        $guest = $this->makeUser('customer');
        $data = $this->bookViaApi($guest)->json('data');

        $this->assertMatchesRegularExpression('/^AS-\d{4,}$/', $data['code']);
        $this->assertSame('AS-' . str_pad((string) $data['id'], 4, '0', STR_PAD_LEFT), $data['code']);
    }

    public function test_the_customer_never_sees_staff_only_details(): void
    {
        $guest = $this->makeUser('customer');
        $id = $this->bookViaApi($guest)->json('data.id');

        $data = $this->payAtHotel($guest, $id)->assertOk()->json('data');

        foreach (['guest', 'payments', 'actions', 'checked_in_by', 'received_by'] as $key) {
            $this->assertArrayNotHasKey($key, $data);
        }
    }
}
