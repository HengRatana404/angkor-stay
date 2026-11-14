<?php

namespace Tests\Feature;

use App\Models\Booking;
use App\Models\Room;
use App\Models\RoomType;
use App\Models\User;
use Database\Seeders\RoomSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class BookingApiTest extends TestCase
{
    use RefreshDatabase;

    private int $userCount = 0;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RoomSeeder::class);
    }

    private function day(int $daysFromToday): string
    {
        return now()->addDays($daysFromToday)->toDateString();
    }

    private function customer(): User
    {
        $this->userCount++;
        $user = User::create([
            'name' => "Customer {$this->userCount}",
            'email' => "customer{$this->userCount}@example.com",
            'phone' => '01200000' . str_pad((string) $this->userCount, 2, '0', STR_PAD_LEFT),
            'password' => 'secret1234',
        ]);
        $user->forceFill(['email_verified_at' => now()])->save();

        return $user;
    }

    private function type(string $name): RoomType
    {
        return RoomType::where('name', $name)->firstOrFail();
    }

    private function payload(string $type = 'Single', int $in = 10, int $out = 12, int $guests = 1): array
    {
        return [
            'room_type_id' => $this->type($type)->id,
            'check_in_date' => $this->day($in),
            'check_out_date' => $this->day($out),
            'guests' => $guests,
        ];
    }

    private function book(User $user, array $payload)
    {
        Sanctum::actingAs($user);

        return $this->postJson('/api/bookings', $payload);
    }

    /** Puts 4 of the 5 VIP rooms into maintenance, so only room 301 can be booked. */
    private function leaveOnlyOneVipRoom(): void
    {
        Room::whereIn('room_number', ['302', '303', '304', '305'])
            ->update(['status' => Room::STATUS_MAINTENANCE]);
    }

    private function makeBooking(Room $room, User $user, int $in, int $out, string $status, $hold = null): Booking
    {
        return Booking::create([
            'user_id' => $user->id,
            'room_id' => $room->id,
            'check_in_date' => $this->day($in),
            'check_out_date' => $this->day($out),
            'guests' => 1,
            'nights' => $out - $in,
            'price_per_night' => 15,
            'total_price' => 15 * ($out - $in),
            'status' => $status,
            'hold_expires_at' => $hold,
        ]);
    }

    // ---------------------------------------------------------------- booking

    public function test_booking_picks_the_lowest_free_room_and_holds_it_for_five_minutes(): void
    {
        $response = $this->book($this->customer(), $this->payload('Single'))
            ->assertCreated()
            ->assertJsonPath('data.status', 'pending')
            ->assertJsonPath('data.room_number', '101')
            ->assertJsonPath('data.room_type.name', 'Single')
            ->assertJsonPath('data.nights', 2)
            ->assertJsonPath('data.guests', 1);

        $left = $response->json('data.hold_seconds_left');
        $this->assertGreaterThan(290, $left);
        $this->assertLessThanOrEqual(300, $left);
    }

    public function test_total_price_is_nights_times_the_price(): void
    {
        $this->book($this->customer(), $this->payload('Double', 10, 13, 2))
            ->assertCreated()
            ->assertJsonPath('data.nights', 3)
            ->assertJsonPath('data.price_per_night', 25)
            ->assertJsonPath('data.total_price', 75);
    }

    public function test_the_saved_price_does_not_change_when_the_room_price_changes_later(): void
    {
        $id = $this->book($this->customer(), $this->payload('Double', 10, 12, 2))
            ->assertCreated()->json('data.id');

        $this->type('Double')->update(['price_per_night' => 99]);

        $this->assertEquals(50, Booking::findOrFail($id)->total_price);
    }

    public function test_booking_needs_a_login(): void
    {
        $this->postJson('/api/bookings', $this->payload())->assertUnauthorized();
    }

    public function test_booking_with_too_many_guests_is_rejected(): void
    {
        $this->book($this->customer(), $this->payload('Single', 10, 12, 3))
            ->assertStatus(422)
            ->assertJsonPath('errors.guests.0', 'A Single room fits up to 2 guests.');

        $this->assertDatabaseCount('bookings', 0);
    }

    public function test_booking_accepts_exactly_the_room_capacity(): void
    {
        $this->book($this->customer(), $this->payload('VIP', 10, 12, 6))->assertCreated();
    }

    public function test_date_rules(): void
    {
        $user = $this->customer();

        $this->book($user, $this->payload('Single', -1, 2))
            ->assertStatus(422)->assertJsonValidationErrors(['check_in_date']);

        $this->book($user, $this->payload('Single', 5, 5))
            ->assertStatus(422)->assertJsonValidationErrors(['check_out_date']);

        $this->book($user, $this->payload('Single', 5, 4))
            ->assertStatus(422)->assertJsonValidationErrors(['check_out_date']);

        $this->book($user, $this->payload('Single', 5, 36))
            ->assertStatus(422)->assertJsonPath('errors.check_out_date.0', 'You can stay up to 30 nights in one booking.');

        $this->book($user, $this->payload('Single', 400, 402))
            ->assertStatus(422)->assertJsonValidationErrors(['check_in_date']);

        $this->assertDatabaseCount('bookings', 0);
    }

    public function test_checking_in_today_is_allowed_and_thirty_nights_is_the_maximum(): void
    {
        $user = $this->customer();

        $this->book($user, $this->payload('Single', 0, 1))->assertCreated();
        $this->book($user, $this->payload('Double', 5, 35, 2))->assertCreated();
    }

    public function test_missing_or_wrong_fields_are_rejected(): void
    {
        $user = $this->customer();

        $this->book($user, [])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['room_type_id', 'check_in_date', 'check_out_date', 'guests']);

        $this->book($user, array_merge($this->payload(), ['room_type_id' => 999]))
            ->assertStatus(422)->assertJsonValidationErrors(['room_type_id']);

        $this->book($user, array_merge($this->payload(), ['guests' => 0]))
            ->assertStatus(422)->assertJsonValidationErrors(['guests']);

        $this->book($user, array_merge($this->payload(), ['check_in_date' => '10/11/2026']))
            ->assertStatus(422)->assertJsonValidationErrors(['check_in_date']);
    }

    // -------------------------------------------------------------- no room left

    public function test_when_every_room_is_taken_the_answer_is_no_room_left(): void
    {
        // 5 VIP rooms, each customer can hold 2, so 3 customers fill all 5.
        $a = $this->customer();
        $b = $this->customer();
        $c = $this->customer();
        $d = $this->customer();

        foreach ([$a, $a, $b, $b, $c] as $user) {
            $this->book($user, $this->payload('VIP', 10, 12, 2))->assertCreated();
        }

        $this->book($d, $this->payload('VIP', 10, 12, 2))
            ->assertStatus(409)
            ->assertJsonPath('code', 'no_room_left')
            ->assertJsonPath('message', 'No VIP room left for these dates.');

        $this->assertSame(5, Booking::count());
    }

    public function test_the_first_customer_gets_the_last_room_and_the_second_gets_no_room_left(): void
    {
        $this->leaveOnlyOneVipRoom();

        $first = $this->book($this->customer(), $this->payload('VIP', 10, 12, 2))->assertCreated();
        $this->assertSame('301', $first->json('data.room_number'));

        $this->book($this->customer(), $this->payload('VIP', 10, 12, 2))
            ->assertStatus(409)
            ->assertJsonPath('code', 'no_room_left');

        $this->assertSame(1, Booking::count());
    }

    public function test_a_room_in_maintenance_is_never_given(): void
    {
        Room::where('room_number', '101')->update(['status' => Room::STATUS_MAINTENANCE]);

        $this->book($this->customer(), $this->payload('Single'))
            ->assertCreated()
            ->assertJsonPath('data.room_number', '102');
    }

    // ----------------------------------------------------------- date overlap

    public function test_overlapping_dates_conflict_but_back_to_back_stays_do_not(): void
    {
        $this->leaveOnlyOneVipRoom();
        $this->book($this->customer(), $this->payload('VIP', 10, 12, 2))->assertCreated();

        // Shares night 11: conflict.
        $this->book($this->customer(), $this->payload('VIP', 11, 13, 2))->assertStatus(409);
        // Same nights: conflict.
        $this->book($this->customer(), $this->payload('VIP', 10, 12, 2))->assertStatus(409);
        // Inside the stay: conflict.
        $this->book($this->customer(), $this->payload('VIP', 10, 11, 2))->assertStatus(409);
        // Around the stay: conflict.
        $this->book($this->customer(), $this->payload('VIP', 9, 13, 2))->assertStatus(409);

        // Leaves the morning the other guest arrives: fine.
        $this->book($this->customer(), $this->payload('VIP', 8, 10, 2))->assertCreated();
        // Arrives the morning the other guest leaves: fine.
        $this->book($this->customer(), $this->payload('VIP', 12, 14, 2))->assertCreated();
    }

    // -------------------------------------------------------------- hold rules

    public function test_an_expired_hold_frees_the_room_for_the_next_customer(): void
    {
        $this->leaveOnlyOneVipRoom();
        $this->book($this->customer(), $this->payload('VIP', 10, 12, 2))->assertCreated();
        $this->book($this->customer(), $this->payload('VIP', 10, 12, 2))->assertStatus(409);

        $this->travel(6)->minutes();

        $this->book($this->customer(), $this->payload('VIP', 10, 12, 2))
            ->assertCreated()
            ->assertJsonPath('data.room_number', '301');
    }

    public function test_the_hold_is_still_valid_just_before_five_minutes(): void
    {
        $this->leaveOnlyOneVipRoom();
        $this->book($this->customer(), $this->payload('VIP', 10, 12, 2))->assertCreated();

        $this->travel(4)->minutes();

        $this->book($this->customer(), $this->payload('VIP', 10, 12, 2))->assertStatus(409);
    }

    public function test_releasing_a_hold_frees_the_room(): void
    {
        $this->leaveOnlyOneVipRoom();
        $owner = $this->customer();
        $id = $this->book($owner, $this->payload('VIP', 10, 12, 2))->assertCreated()->json('data.id');

        Sanctum::actingAs($owner);
        $this->postJson("/api/bookings/{$id}/release")->assertOk();
        $this->assertSame('cancelled', Booking::findOrFail($id)->status);

        $this->book($this->customer(), $this->payload('VIP', 10, 12, 2))->assertCreated();
    }

    public function test_only_a_pending_booking_can_be_released(): void
    {
        $owner = $this->customer();
        $booking = $this->makeBooking(Room::where('room_number', '101')->first(), $owner, 10, 12, Booking::STATUS_CONFIRMED);

        Sanctum::actingAs($owner);
        $this->postJson("/api/bookings/{$booking->id}/release")->assertStatus(422);
        $this->assertSame('confirmed', $booking->fresh()->status);
    }

    public function test_one_customer_cannot_hold_more_than_two_rooms(): void
    {
        $user = $this->customer();

        $first = $this->book($user, $this->payload('Single'))->assertCreated()->json('data.id');
        $this->book($user, $this->payload('Single'))->assertCreated();
        $this->book($user, $this->payload('Single'))
            ->assertStatus(409)
            ->assertJsonPath('code', 'too_many_holds');

        Sanctum::actingAs($user);
        $this->postJson("/api/bookings/{$first}/release")->assertOk();

        $this->book($user, $this->payload('Single'))->assertCreated();
    }

    public function test_an_expired_hold_does_not_count_against_the_limit(): void
    {
        $user = $this->customer();
        $this->book($user, $this->payload('Single'))->assertCreated();
        $this->book($user, $this->payload('Single'))->assertCreated();

        $this->travel(6)->minutes();

        $this->book($user, $this->payload('Single'))->assertCreated();
    }

    // ---------------------------------------------- which statuses keep a room

    public function test_confirmed_and_checked_in_bookings_keep_the_room(): void
    {
        $this->leaveOnlyOneVipRoom();
        $room = Room::where('room_number', '301')->first();
        $other = $this->customer();

        foreach ([Booking::STATUS_CONFIRMED, Booking::STATUS_CHECKED_IN] as $status) {
            $booking = $this->makeBooking($room, $other, 10, 12, $status);
            $this->book($this->customer(), $this->payload('VIP', 10, 12, 2))->assertStatus(409);
            $booking->delete();
        }
    }

    public function test_a_pending_booking_without_a_hold_time_keeps_the_room(): void
    {
        // This is how "pay at hotel" bookings will be kept later.
        $this->leaveOnlyOneVipRoom();
        $this->makeBooking(Room::where('room_number', '301')->first(), $this->customer(), 10, 12, Booking::STATUS_PENDING, null);

        $this->book($this->customer(), $this->payload('VIP', 10, 12, 2))->assertStatus(409);
    }

    public function test_cancelled_no_show_and_checked_out_bookings_do_not_keep_the_room(): void
    {
        $this->leaveOnlyOneVipRoom();
        $room = Room::where('room_number', '301')->first();
        $other = $this->customer();

        foreach ([Booking::STATUS_CANCELLED, Booking::STATUS_NO_SHOW, Booking::STATUS_CHECKED_OUT] as $status) {
            $this->makeBooking($room, $other, 10, 12, $status);
        }

        $this->book($this->customer(), $this->payload('VIP', 10, 12, 2))->assertCreated();
    }

    // ------------------------------------------------------------ viewing one

    public function test_the_owner_can_see_the_booking_with_the_countdown(): void
    {
        $owner = $this->customer();
        $id = $this->book($owner, $this->payload('Double', 10, 12, 2))->assertCreated()->json('data.id');

        Sanctum::actingAs($owner);
        $this->getJson("/api/bookings/{$id}")
            ->assertOk()
            ->assertJsonPath('data.id', $id)
            ->assertJsonPath('data.room_type.name', 'Double')
            ->assertJsonPath('data.status', 'pending')
            ->assertJsonStructure(['data' => ['hold_expires_at', 'hold_seconds_left', 'room_number', 'total_price']]);
    }

    public function test_the_countdown_reaches_zero_after_five_minutes(): void
    {
        $owner = $this->customer();
        $id = $this->book($owner, $this->payload())->assertCreated()->json('data.id');

        $this->travel(6)->minutes();

        Sanctum::actingAs($owner);
        $this->getJson("/api/bookings/{$id}")->assertOk()->assertJsonPath('data.hold_seconds_left', 0);
    }

    public function test_nobody_else_can_see_or_release_a_booking(): void
    {
        $id = $this->book($this->customer(), $this->payload())->assertCreated()->json('data.id');

        Sanctum::actingAs($this->customer());
        $this->getJson("/api/bookings/{$id}")->assertNotFound();
        $this->postJson("/api/bookings/{$id}/release")->assertNotFound();
        $this->assertSame('pending', Booking::findOrFail($id)->status);
    }

    public function test_viewing_needs_a_login(): void
    {
        $this->getJson('/api/bookings/1')->assertUnauthorized();
    }

    // ---------------------------------------------- rooms left on the room list

    public function test_room_list_shows_rooms_left_for_the_chosen_dates(): void
    {
        $query = '?check_in_date=' . $this->day(10) . '&check_out_date=' . $this->day(12);

        $left = fn () => collect($this->getJson('/api/room-types' . $query)->assertOk()->json('data'))
            ->pluck('available_rooms', 'name')->all();

        $this->assertSame(['Single' => 5, 'Double' => 5, 'VIP' => 5], $left());

        $this->book($this->customer(), $this->payload('Double', 10, 12, 2))->assertCreated();
        $this->assertSame(['Single' => 5, 'Double' => 4, 'VIP' => 5], $left());

        Room::where('room_number', '101')->update(['status' => Room::STATUS_MAINTENANCE]);
        $this->assertSame(['Single' => 4, 'Double' => 4, 'VIP' => 5], $left());
    }

    public function test_rooms_left_ignores_stays_that_only_touch_the_dates(): void
    {
        $this->book($this->customer(), $this->payload('Double', 8, 10, 2))->assertCreated();
        $this->book($this->customer(), $this->payload('Double', 12, 14, 2))->assertCreated();

        $double = collect($this->getJson('/api/room-types?check_in_date=' . $this->day(10) . '&check_out_date=' . $this->day(12))
            ->json('data'))->firstWhere('name', 'Double');

        $this->assertSame(5, $double['available_rooms']);
    }

    public function test_rooms_left_goes_back_up_when_a_hold_runs_out(): void
    {
        $query = '?check_in_date=' . $this->day(10) . '&check_out_date=' . $this->day(12);
        $this->book($this->customer(), $this->payload('VIP', 10, 12, 2))->assertCreated();

        $vip = fn () => collect($this->getJson('/api/room-types' . $query)->json('data'))->firstWhere('name', 'VIP')['available_rooms'];

        $this->assertSame(4, $vip());
        $this->travel(6)->minutes();
        $this->assertSame(5, $vip());
    }

    public function test_room_list_without_dates_has_no_rooms_left_numbers(): void
    {
        $first = $this->getJson('/api/room-types')->assertOk()->json('data.0');

        $this->assertArrayNotHasKey('available_rooms', $first);
    }

    public function test_room_list_rejects_bad_dates(): void
    {
        $this->getJson('/api/room-types?check_in_date=' . $this->day(-2) . '&check_out_date=' . $this->day(1))
            ->assertStatus(422)->assertJsonValidationErrors(['check_in_date']);

        $this->getJson('/api/room-types?check_in_date=' . $this->day(5))
            ->assertStatus(422)->assertJsonValidationErrors(['check_out_date']);

        $this->getJson('/api/room-types?check_in_date=' . $this->day(5) . '&check_out_date=' . $this->day(5))
            ->assertStatus(422)->assertJsonValidationErrors(['check_out_date']);
    }

    public function test_one_room_type_can_also_show_rooms_left(): void
    {
        $vip = $this->type('VIP');

        $this->getJson("/api/room-types/{$vip->id}?check_in_date={$this->day(10)}&check_out_date={$this->day(12)}")
            ->assertOk()
            ->assertJsonPath('data.available_rooms', 5);
    }

    // ----------------------------------------------------------------- misc

    public function test_the_hotel_runs_on_phnom_penh_time(): void
    {
        $this->assertSame('Asia/Phnom_Penh', config('app.timezone'));
    }
}
