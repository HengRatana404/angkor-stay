<?php

namespace Tests\Feature;

use App\Models\Booking;
use App\Models\Payment;
use App\Models\Room;
use App\Models\User;
use App\Services\SettingsService;
use Database\Seeders\RoomSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\MakesBookings;
use Tests\Concerns\MakesUsers;
use Tests\TestCase;

/** The staff side: find a booking, take payment, check in, check out. */
class StaffBookingApiTest extends TestCase
{
    use MakesBookings;
    use MakesUsers;
    use RefreshDatabase;

    private User $staff;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RoomSeeder::class);
        $this->staff = $this->makeUser('staff', ['name' => 'Front Desk']);
    }

    private function asStaff(): void
    {
        Sanctum::actingAs($this->staff);
    }

    private function guest(array $extra = []): User
    {
        return $this->makeUser('customer', $extra);
    }

    private function room(string $number): Room
    {
        return Room::where('room_number', $number)->firstOrFail();
    }

    private function pay(Booking $booking, string $method = 'cash')
    {
        return $this->postJson("/api/staff/bookings/{$booking->id}/payments", ['method' => $method]);
    }

    // ----------------------------------------------------------------- access

    public function test_a_guest_who_is_not_logged_in_cannot_use_any_staff_route(): void
    {
        $this->getJson('/api/staff/bookings')->assertUnauthorized();
        $this->getJson('/api/staff/bookings/1')->assertUnauthorized();
        $this->postJson('/api/staff/bookings/1/payments', ['method' => 'cash'])->assertUnauthorized();
        $this->postJson('/api/staff/bookings/1/check-in')->assertUnauthorized();
        $this->postJson('/api/staff/bookings/1/check-out')->assertUnauthorized();
    }

    public function test_a_customer_cannot_use_any_staff_route(): void
    {
        $guest = $this->guest();
        $booking = $this->makeKeptBooking($guest);
        Sanctum::actingAs($guest);

        $this->getJson('/api/staff/bookings')->assertStatus(403)->assertJsonPath('code', 'forbidden_role');
        $this->getJson("/api/staff/bookings/{$booking->id}")->assertStatus(403);
        $this->pay($booking)->assertStatus(403);
        $this->postJson("/api/staff/bookings/{$booking->id}/check-in")->assertStatus(403);
        $this->postJson("/api/staff/bookings/{$booking->id}/check-out")->assertStatus(403);

        $this->assertSame(0, Payment::count());
        $this->assertSame('pending', $booking->fresh()->status);
    }

    public function test_the_admin_can_do_everything_staff_can(): void
    {
        $admin = $this->makeUser('admin', ['name' => 'Boss']);
        $booking = $this->makeKeptBooking($this->guest());
        Sanctum::actingAs($admin);

        $this->getJson('/api/staff/bookings')->assertOk();
        $this->pay($booking, 'card')
            ->assertCreated()
            ->assertJsonPath('data.payments.0.received_by.name', 'Boss');
    }

    public function test_staff_outside_the_hotel_network_are_stopped(): void
    {
        $booking = $this->makeKeptBooking($this->guest());
        $this->asStaff();

        $this->fromIp('8.8.8.8')->getJson('/api/staff/bookings')
            ->assertStatus(403)->assertJsonPath('code', 'outside_hotel_network');
        $this->fromIp('8.8.8.8')->postJson("/api/staff/bookings/{$booking->id}/payments", ['method' => 'cash'])
            ->assertStatus(403);

        $this->assertSame(0, Payment::count());
    }

    // ------------------------------------------------------------------- list

    public function test_the_list_shows_real_bookings_and_leaves_out_holds_that_ran_out(): void
    {
        $guest = $this->guest();
        $kept = $this->makeKeptBooking($guest, ['room' => $this->room('101')]);
        $confirmed = $this->makeBooking($guest, ['room' => $this->room('102'), 'status' => 'confirmed', 'hold' => null]);
        $running = $this->makeBooking($guest, ['room' => $this->room('103')]);
        $dead = $this->makeBooking($guest, ['room' => $this->room('104'), 'hold' => now()->subMinute()]);
        $cancelled = $this->makeBooking($guest, ['room' => $this->room('105'), 'status' => 'cancelled', 'hold' => null]);
        $this->asStaff();

        $ids = collect($this->getJson('/api/staff/bookings')->assertOk()->json('data'))->pluck('id')->all();

        $this->assertEqualsCanonicalizing([$kept->id, $confirmed->id, $running->id, $cancelled->id], $ids);
        $this->assertNotContains($dead->id, $ids);
    }

    public function test_the_list_is_newest_first(): void
    {
        $guest = $this->guest();
        $first = $this->makeKeptBooking($guest, ['room' => $this->room('101')]);
        $second = $this->makeKeptBooking($guest, ['room' => $this->room('102')]);
        $third = $this->makeKeptBooking($guest, ['room' => $this->room('103')]);
        $this->asStaff();

        $ids = collect($this->getJson('/api/staff/bookings')->json('data'))->pluck('id')->all();

        $this->assertSame([$third->id, $second->id, $first->id], $ids);
    }

    public function test_the_list_shows_the_guest_and_never_a_password(): void
    {
        $this->makeKeptBooking($this->guest(['name' => 'Sok Dara', 'phone' => '012345678', 'email' => 'dara@example.com']));
        $this->asStaff();

        $row = $this->getJson('/api/staff/bookings')->assertOk()->json('data.0');

        $this->assertSame('Sok Dara', $row['guest']['name']);
        $this->assertSame('012345678', $row['guest']['phone']);
        $this->assertSame('dara@example.com', $row['guest']['email']);
        $this->assertStringNotContainsString('password', json_encode($row));
        $this->assertStringNotContainsString('remember_token', json_encode($row));
    }

    public function test_search_finds_by_name_phone_email_and_room_number(): void
    {
        $dara = $this->guest(['name' => 'Sok Dara', 'phone' => '012345678', 'email' => 'dara.sok@example.com']);
        $vanna = $this->guest(['name' => 'Chan Vanna', 'phone' => '099888777', 'email' => 'vanna@example.org']);
        $a = $this->makeKeptBooking($dara, ['room' => $this->room('101')]);
        $b = $this->makeKeptBooking($vanna, ['room' => $this->room('202')]);
        $this->asStaff();

        $find = fn (string $term) => collect($this->getJson('/api/staff/bookings?search=' . urlencode($term))->assertOk()->json('data'))->pluck('id')->all();

        $this->assertSame([$a->id], $find('sok'));        // part of a name
        $this->assertSame([$a->id], $find('SOK DARA'));    // capital letters do not matter
        $this->assertSame([$b->id], $find('vanna'));
        $this->assertSame([$a->id], $find('012345'));      // part of a phone number
        $this->assertSame([$b->id], $find('099888777'));
        $this->assertSame([$a->id], $find('dara.sok@'));   // part of an email
        $this->assertSame([$b->id], $find('example.org'));
        $this->assertSame([$a->id], $find('101'));         // room number
        $this->assertSame([$b->id], $find('202'));
        $this->assertSame([], $find('nobody-here'));
    }

    public function test_search_finds_by_booking_code(): void
    {
        $guest = $this->guest(['name' => 'Sok Dara']);
        $a = $this->makeKeptBooking($guest, ['room' => $this->room('101')]);
        $b = $this->makeKeptBooking($guest, ['room' => $this->room('102')]);
        $this->asStaff();

        $find = fn (string $term) => collect($this->getJson('/api/staff/bookings?search=' . urlencode($term))->json('data'))->pluck('id')->all();

        $this->assertSame([$b->id], $find($b->code));                                   // AS-0042
        $this->assertSame([$b->id], $find(strtolower($b->code)));                       // as-0042
        $this->assertSame([$b->id], $find('as' . str_pad((string) $b->id, 4, '0', STR_PAD_LEFT)));
        $this->assertSame([$a->id], $find($a->code));
    }

    public function test_search_symbols_are_treated_as_plain_letters(): void
    {
        $this->makeKeptBooking($this->guest(['name' => 'Sok Dara']));
        $this->asStaff();

        // "%" and "_" must not work as "match everything".
        $this->assertCount(0, $this->getJson('/api/staff/bookings?search=%25')->json('data'));
        $this->assertCount(0, $this->getJson('/api/staff/bookings?search=_')->json('data'));
        $this->assertCount(0, $this->getJson('/api/staff/bookings?search=' . urlencode("' OR 1=1 --"))->json('data'));
    }

    public function test_the_list_can_be_filtered_by_status(): void
    {
        $guest = $this->guest();
        $kept = $this->makeKeptBooking($guest, ['room' => $this->room('101')]);
        $confirmed = $this->makeBooking($guest, ['room' => $this->room('102'), 'status' => 'confirmed', 'hold' => null]);
        $this->makeBooking($guest, ['room' => $this->room('103'), 'status' => 'checked_in', 'hold' => null]);
        $this->asStaff();

        $ids = fn (string $status) => collect($this->getJson("/api/staff/bookings?status={$status}")->assertOk()->json('data'))->pluck('id')->all();

        $this->assertSame([$kept->id], $ids('pending'));
        $this->assertSame([$confirmed->id], $ids('confirmed'));
        $this->assertCount(1, $ids('checked_in'));
        $this->assertSame([], $ids('cancelled'));
    }

    public function test_an_unknown_status_is_refused(): void
    {
        $this->asStaff();

        $this->getJson('/api/staff/bookings?status=banana')->assertStatus(422)->assertJsonValidationErrors(['status']);
    }

    public function test_search_and_status_work_together(): void
    {
        $dara = $this->guest(['name' => 'Sok Dara']);
        $kept = $this->makeKeptBooking($dara, ['room' => $this->room('101')]);
        $this->makeBooking($dara, ['room' => $this->room('102'), 'status' => 'confirmed', 'hold' => null]);
        $this->asStaff();

        $ids = collect($this->getJson('/api/staff/bookings?search=dara&status=pending')->json('data'))->pluck('id')->all();

        $this->assertSame([$kept->id], $ids);
    }

    public function test_the_list_stops_at_100_bookings(): void
    {
        $guest = $this->guest();
        $room = $this->room('101');
        for ($i = 0; $i < 105; $i++) {
            $this->makeBooking($guest, ['room' => $room, 'status' => 'cancelled', 'hold' => null]);
        }
        $this->asStaff();

        $this->assertCount(100, $this->getJson('/api/staff/bookings')->json('data'));
    }

    public function test_one_booking_can_be_opened_and_an_unknown_one_is_404(): void
    {
        $booking = $this->makeKeptBooking($this->guest(['name' => 'Sok Dara']));
        $this->asStaff();

        $this->getJson("/api/staff/bookings/{$booking->id}")
            ->assertOk()
            ->assertJsonPath('data.id', $booking->id)
            ->assertJsonPath('data.guest.name', 'Sok Dara')
            ->assertJsonPath('data.room_number', '101');

        $this->getJson('/api/staff/bookings/999999')->assertNotFound();
    }

    // ---------------------------------------------------------------- payment

    public function test_taking_payment_saves_the_amount_the_method_and_the_staff_name(): void
    {
        $booking = $this->makeKeptBooking($this->guest()); // 2 nights x $15 = $30
        $this->asStaff();

        $this->pay($booking, 'cash')
            ->assertCreated()
            ->assertJsonPath('data.status', 'confirmed')
            ->assertJsonPath('data.paid', true)
            ->assertJsonPath('data.payments.0.amount', 30)
            ->assertJsonPath('data.payments.0.method', 'cash')
            ->assertJsonPath('data.payments.0.status', 'paid')
            ->assertJsonPath('data.payments.0.received_by.name', 'Front Desk')
            ->assertJsonPath('data.actions.can_take_payment', false);

        $payment = Payment::firstOrFail();
        $this->assertSame($booking->id, $payment->booking_id);
        $this->assertEquals(30, $payment->amount);
        $this->assertSame($this->staff->id, $payment->received_by);
        $this->assertNotNull($payment->paid_at);

        $booking->refresh();
        $this->assertSame('confirmed', $booking->status);
        $this->assertSame('hotel', $booking->payment_choice);
        $this->assertNull($booking->hold_expires_at);
    }

    public function test_khqr_cash_and_card_are_all_accepted(): void
    {
        $this->asStaff();

        foreach (['khqr' => '101', 'cash' => '102', 'card' => '103'] as $method => $roomNumber) {
            $booking = $this->makeKeptBooking($this->guest(), ['room' => $this->room($roomNumber)]);

            $this->pay($booking, $method)->assertCreated()->assertJsonPath('data.payments.0.method', $method);
        }

        $this->assertSame(['card', 'cash', 'khqr'], Payment::orderBy('method')->pluck('method')->all());
    }

    public function test_there_is_no_discount_when_paying_at_the_hotel(): void
    {
        app(SettingsService::class)->update(['online_discount_percent' => 20]);
        $booking = $this->makeKeptBooking($this->guest(), ['room' => $this->room('301'), 'in' => 5, 'out' => 8]); // 3 x $50
        $this->asStaff();

        $this->pay($booking)->assertCreated()->assertJsonPath('data.payments.0.amount', 150);

        $this->assertEquals(150, Payment::firstOrFail()->amount);
    }

    public function test_staff_cannot_choose_the_amount_or_the_payer(): void
    {
        $booking = $this->makeKeptBooking($this->guest());
        $other = $this->makeUser('staff');
        $this->asStaff();

        $this->postJson("/api/staff/bookings/{$booking->id}/payments", [
            'method' => 'cash', 'amount' => 1, 'received_by' => $other->id, 'status' => 'refunded',
        ])->assertCreated();

        $payment = Payment::firstOrFail();
        $this->assertEquals(30, $payment->amount);
        $this->assertSame($this->staff->id, $payment->received_by);
        $this->assertSame('paid', $payment->status);
    }

    public function test_only_khqr_cash_and_card_are_allowed(): void
    {
        $booking = $this->makeKeptBooking($this->guest());
        $this->asStaff();

        foreach (['online', 'bitcoin', '', 'CASH ', null] as $bad) {
            $this->postJson("/api/staff/bookings/{$booking->id}/payments", ['method' => $bad])
                ->assertStatus(422)->assertJsonValidationErrors(['method']);
        }
        $this->postJson("/api/staff/bookings/{$booking->id}/payments", [])
            ->assertStatus(422)->assertJsonValidationErrors(['method']);

        $this->assertSame(0, Payment::count());
        $this->assertSame('pending', $booking->fresh()->status);
    }

    public function test_the_same_booking_cannot_be_paid_twice(): void
    {
        $booking = $this->makeKeptBooking($this->guest());
        $this->asStaff();

        $this->pay($booking)->assertCreated();
        $this->pay($booking, 'card')->assertStatus(409)->assertJsonPath('code', 'already_paid');

        $this->assertSame(1, Payment::count());
    }

    public function test_a_guest_can_be_paid_while_the_five_minutes_still_run(): void
    {
        // The guest is standing at the desk and has not pressed "pay at hotel" yet.
        $booking = $this->makeBooking($this->guest());
        $this->asStaff();

        $this->pay($booking)->assertCreated()->assertJsonPath('data.status', 'confirmed');

        $this->assertNull($booking->fresh()->hold_expires_at);
    }

    public function test_a_hold_that_ran_out_cannot_be_paid(): void
    {
        $booking = $this->makeBooking($this->guest(), ['hold' => now()->subMinute()]);
        $this->asStaff();

        $this->pay($booking)->assertStatus(409)->assertJsonPath('code', 'hold_expired');

        $this->assertSame(0, Payment::count());
        $this->assertSame('pending', $booking->fresh()->status);
    }

    public function test_a_booking_that_is_not_pending_cannot_be_paid(): void
    {
        $this->asStaff();

        foreach (['cancelled', 'no_show', 'checked_out'] as $i => $status) {
            $booking = $this->makeBooking($this->guest(), ['room' => $this->room('10' . ($i + 1)), 'status' => $status, 'hold' => null]);

            $this->pay($booking)->assertStatus(422)->assertJsonPath('code', 'not_pending');
        }

        $this->assertSame(0, Payment::count());
    }

    public function test_paying_an_unknown_booking_is_404(): void
    {
        $this->asStaff();

        $this->postJson('/api/staff/bookings/999999/payments', ['method' => 'cash'])->assertNotFound();
    }

    // --------------------------------------------------------------- check-in

    public function test_check_in_saves_the_staff_name_and_the_time(): void
    {
        $booking = $this->makeBooking($this->guest(), ['in' => 0, 'out' => 2, 'status' => 'confirmed', 'hold' => null]);
        $this->asStaff();

        $this->postJson("/api/staff/bookings/{$booking->id}/check-in")
            ->assertOk()
            ->assertJsonPath('data.status', 'checked_in')
            ->assertJsonPath('data.checked_in_by.name', 'Front Desk')
            ->assertJsonPath('data.actions.can_check_in', false)
            ->assertJsonPath('data.actions.can_check_out', true);

        $booking->refresh();
        $this->assertSame('checked_in', $booking->status);
        $this->assertSame($this->staff->id, $booking->checked_in_by);
        $this->assertNotNull($booking->checked_in_at);
    }

    public function test_a_guest_can_check_in_in_the_middle_of_the_booked_stay(): void
    {
        // Fixed morning clock: the no-show cutoff is noon the day after check-in,
        // so with the real clock this test failed every day after 12:00.
        \Illuminate\Support\Carbon::setTestNow(now()->setTime(9, 0));

        try {
            $booking = $this->makeBooking($this->guest(), ['in' => -1, 'out' => 2, 'status' => 'confirmed', 'hold' => null]);
            $this->asStaff();

            $this->postJson("/api/staff/bookings/{$booking->id}/check-in")->assertOk();
        } finally {
            \Illuminate\Support\Carbon::setTestNow();
        }
    }

    public function test_check_in_is_refused_before_the_check_in_date(): void
    {
        $booking = $this->makeBooking($this->guest(), ['in' => 5, 'out' => 7, 'status' => 'confirmed', 'hold' => null]);
        $this->asStaff();

        $this->postJson("/api/staff/bookings/{$booking->id}/check-in")
            ->assertStatus(422)
            ->assertJsonPath('code', 'cannot_check_in');

        $message = $this->postJson("/api/staff/bookings/{$booking->id}/check-in")->json('message');
        $this->assertStringContainsString('Check-in opens on', $message);
        $this->assertSame('confirmed', $booking->fresh()->status);
        $this->assertNull($booking->fresh()->checked_in_by);
    }

    public function test_check_in_is_refused_when_the_stay_is_over(): void
    {
        $this->asStaff();

        foreach ([['in' => -4, 'out' => -2], ['in' => -2, 'out' => 0]] as $i => $dates) {
            $booking = $this->makeBooking($this->guest(), $dates + ['room' => $this->room('10' . ($i + 1)), 'status' => 'confirmed', 'hold' => null]);

            $this->postJson("/api/staff/bookings/{$booking->id}/check-in")
                ->assertStatus(422)
                ->assertJsonPath('message', 'This stay is already over.');
        }
    }

    public function test_check_in_needs_payment_first(): void
    {
        $booking = $this->makeKeptBooking($this->guest(), ['in' => 0, 'out' => 2]);
        $this->asStaff();

        $this->postJson("/api/staff/bookings/{$booking->id}/check-in")
            ->assertStatus(422)
            ->assertJsonPath('message', 'Take payment first.');

        $this->assertSame('pending', $booking->fresh()->status);
    }

    public function test_check_in_is_refused_for_a_hold_that_ran_out(): void
    {
        $booking = $this->makeBooking($this->guest(), ['in' => 0, 'out' => 2, 'hold' => now()->subMinute()]);
        $this->asStaff();

        $this->postJson("/api/staff/bookings/{$booking->id}/check-in")->assertStatus(422);
    }

    public function test_a_guest_cannot_check_in_twice_or_after_leaving_or_when_cancelled(): void
    {
        $this->asStaff();
        $cases = [
            'checked_in' => 'This guest is already checked in.',
            'checked_out' => 'This guest already checked out.',
            'cancelled' => 'This booking is cancelled.',
            'no_show' => 'This booking is no show.',
        ];

        $i = 0;
        foreach ($cases as $status => $message) {
            $booking = $this->makeBooking($this->guest(), ['in' => 0, 'out' => 2, 'room' => $this->room('10' . (++$i)), 'status' => $status, 'hold' => null]);

            $this->postJson("/api/staff/bookings/{$booking->id}/check-in")
                ->assertStatus(422)->assertJsonPath('message', $message);
        }
    }

    // -------------------------------------------------------------- check-out

    public function test_check_out_saves_the_staff_name_and_the_time(): void
    {
        $booking = $this->makeBooking($this->guest(), ['in' => -1, 'out' => 1, 'status' => 'checked_in', 'hold' => null]);
        $this->asStaff();

        $this->postJson("/api/staff/bookings/{$booking->id}/check-out")
            ->assertOk()
            ->assertJsonPath('data.status', 'checked_out')
            ->assertJsonPath('data.checked_out_by.name', 'Front Desk')
            ->assertJsonPath('data.actions.can_check_out', false);

        $booking->refresh();
        $this->assertSame($this->staff->id, $booking->checked_out_by);
        $this->assertNotNull($booking->checked_out_at);
    }

    public function test_a_guest_can_check_out_early(): void
    {
        $booking = $this->makeBooking($this->guest(), ['in' => 0, 'out' => 5, 'status' => 'checked_in', 'hold' => null]);
        $this->asStaff();

        $this->postJson("/api/staff/bookings/{$booking->id}/check-out")->assertOk();
    }

    public function test_check_out_needs_a_guest_who_is_checked_in(): void
    {
        $this->asStaff();
        $i = 0;

        foreach (['confirmed', 'pending', 'cancelled'] as $status) {
            $booking = $this->makeBooking($this->guest(), ['room' => $this->room('10' . (++$i)), 'status' => $status, 'hold' => null]);

            $this->postJson("/api/staff/bookings/{$booking->id}/check-out")
                ->assertStatus(422)->assertJsonPath('message', 'This guest is not checked in.');
        }
    }

    public function test_a_guest_cannot_check_out_twice(): void
    {
        $booking = $this->makeBooking($this->guest(), ['in' => -1, 'out' => 1, 'status' => 'checked_in', 'hold' => null]);
        $this->asStaff();

        $this->postJson("/api/staff/bookings/{$booking->id}/check-out")->assertOk();
        $this->postJson("/api/staff/bookings/{$booking->id}/check-out")
            ->assertStatus(422)->assertJsonPath('message', 'This guest already checked out.');
    }

    public function test_after_check_out_the_room_is_free_again(): void
    {
        $this->leaveOnlyOneVipRoom();
        $booking = $this->makeBooking($this->guest(), ['room' => $this->room('301'), 'in' => 0, 'out' => 3, 'status' => 'checked_in', 'hold' => null]);
        $this->asStaff();

        $query = '?check_in_date=' . $this->day(1) . '&check_out_date=' . $this->day(2);
        $left = fn () => collect($this->getJson('/api/room-types' . $query)->json('data'))->firstWhere('name', 'VIP')['available_rooms'];

        $this->assertSame(0, $left());

        $this->postJson("/api/staff/bookings/{$booking->id}/check-out")->assertOk();

        $this->assertSame(1, $left());
    }

    // ------------------------------------------------- what the app may show

    public function test_the_server_tells_the_app_which_buttons_to_show(): void
    {
        $guest = $this->guest();
        $kept = $this->makeKeptBooking($guest, ['room' => $this->room('101')]);
        $today = $this->makeBooking($guest, ['room' => $this->room('102'), 'in' => 0, 'out' => 2, 'status' => 'confirmed', 'hold' => null]);
        $later = $this->makeBooking($guest, ['room' => $this->room('103'), 'in' => 6, 'out' => 8, 'status' => 'confirmed', 'hold' => null]);
        $inside = $this->makeBooking($guest, ['room' => $this->room('104'), 'in' => -1, 'out' => 2, 'status' => 'checked_in', 'hold' => null]);
        $this->asStaff();

        $actions = fn (Booking $b) => $this->getJson("/api/staff/bookings/{$b->id}")->json('data.actions');

        $this->assertSame(
            ['can_take_payment' => true, 'can_check_in' => false, 'check_in_problem' => 'Take payment first.', 'can_check_out' => false],
            $actions($kept),
        );
        $this->assertSame(
            ['can_take_payment' => false, 'can_check_in' => true, 'check_in_problem' => null, 'can_check_out' => false],
            $actions($today),
        );
        $this->assertFalse($actions($later)['can_check_in']);
        $this->assertStringContainsString('Check-in opens on', $actions($later)['check_in_problem']);
        $this->assertSame(
            ['can_take_payment' => false, 'can_check_in' => false, 'check_in_problem' => 'This guest is already checked in.', 'can_check_out' => true],
            $actions($inside),
        );
    }

    // --------------------------------------------------------------- full flow

    public function test_a_whole_stay_from_booking_to_check_out(): void
    {
        // 1. The customer books online and chooses to pay at the hotel.
        $this->leaveOnlyOneVipRoom();
        $customer = $this->guest(['name' => 'Sok Dara', 'phone' => '012345678']);
        Sanctum::actingAs($customer);
        $created = $this->postJson('/api/bookings', [
            'room_type_id' => $this->type('VIP')->id,
            'check_in_date' => $this->day(0),
            'check_out_date' => $this->day(2),
            'guests' => 2,
        ])->assertCreated()->json('data');

        $this->postJson("/api/bookings/{$created['id']}/pay-at-hotel")
            ->assertOk()->assertJsonPath('data.hold_seconds_left', null);

        // 2. A day later the guest walks in. Staff find the booking by its code.
        $this->travel(10)->hours();
        $this->asStaff();
        $found = $this->getJson('/api/staff/bookings?search=' . urlencode($created['code']))->assertOk()->json('data');
        $this->assertCount(1, $found);
        $this->assertSame('Sok Dara', $found[0]['guest']['name']);
        $this->assertFalse($found[0]['paid']);

        // 3. They cannot check in before paying.
        $this->postJson("/api/staff/bookings/{$created['id']}/check-in")->assertStatus(422);

        // 4. Staff take payment in cash: the full $100.
        $this->postJson("/api/staff/bookings/{$created['id']}/payments", ['method' => 'cash'])
            ->assertCreated()
            ->assertJsonPath('data.payments.0.amount', 100);

        // 5. Check in, and later check out.
        $this->postJson("/api/staff/bookings/{$created['id']}/check-in")->assertOk();
        $this->postJson("/api/staff/bookings/{$created['id']}/check-out")->assertOk();

        // 6. The record shows who did every step.
        $final = $this->getJson("/api/staff/bookings/{$created['id']}")->assertOk()->json('data');
        $this->assertSame('checked_out', $final['status']);
        $this->assertSame('Front Desk', $final['payments'][0]['received_by']['name']);
        $this->assertSame('Front Desk', $final['checked_in_by']['name']);
        $this->assertSame('Front Desk', $final['checked_out_by']['name']);

        // 7. The customer sees it paid, without staff details.
        Sanctum::actingAs($customer);
        $mine = $this->getJson("/api/bookings/{$created['id']}")->assertOk()->json('data');
        $this->assertTrue($mine['paid']);
        $this->assertSame('cash', $mine['payment_method']);
        $this->assertSame('checked_out', $mine['status']);
        $this->assertArrayNotHasKey('payments', $mine);
        $this->assertArrayNotHasKey('checked_in_by', $mine);
    }
}
