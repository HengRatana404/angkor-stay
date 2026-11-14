<?php

namespace Tests\Feature;

use App\Models\Booking;
use App\Models\Payment;
use App\Models\User;
use Database\Seeders\RoomSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\MakesBookings;
use Tests\Concerns\MakesUsers;
use Tests\TestCase;

/**
 * One stay, followed from the guest's booking to check-out. After every step the DATABASE row,
 * what the GUEST reads, what STAFF read and what the ADMIN dashboard counts must all say the same.
 */
class StaySyncTest extends TestCase
{
    use MakesBookings;
    use MakesUsers;
    use RefreshDatabase;

    private User $guest;

    private User $staff;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RoomSeeder::class);
        $this->guest = $this->makeUser('customer', ['name' => 'Sok Dara']);
        $this->staff = $this->makeUser('staff', ['name' => 'Front Desk']);
        $this->admin = $this->makeUser('admin', ['name' => 'The Boss']);
    }

    /** What each person sees about one booking. */
    private function views(int $id): array
    {
        Sanctum::actingAs($this->guest);
        $guest = collect($this->getJson('/api/bookings')->assertOk()->json('data'))->firstWhere('id', $id);
        $guestOne = $this->getJson("/api/bookings/{$id}")->assertOk()->json('data');

        Sanctum::actingAs($this->staff);
        $staffList = collect($this->getJson('/api/staff/bookings')->assertOk()->json('data'))->firstWhere('id', $id);
        $staffOne = $this->getJson("/api/staff/bookings/{$id}")->assertOk()->json('data');

        Sanctum::actingAs($this->admin);
        $adminList = collect($this->getJson('/api/staff/bookings')->assertOk()->json('data'))->firstWhere('id', $id);
        $dashboard = $this->getJson('/api/admin/dashboard')->assertOk()->json('data');

        return compact('guest', 'guestOne', 'staffList', 'staffOne', 'adminList', 'dashboard');
    }

    /** The row in the database and every screen agree on the status and on "paid". */
    private function assertEveryoneAgrees(int $id, string $status, bool $paid): array
    {
        $row = Booking::findOrFail($id);
        $this->assertSame($status, $row->status, 'database');
        $this->assertSame($paid, $row->isPaid(), 'database: paid');

        $v = $this->views($id);
        foreach (['guest', 'guestOne', 'staffList', 'staffOne', 'adminList'] as $who) {
            $this->assertNotNull($v[$who], "$who cannot see the booking");
            $this->assertSame($status, $v[$who]['status'], "$who sees another status");
            $this->assertSame($paid, (bool) $v[$who]['paid'], "$who sees another paid state");
        }

        return $v;
    }

    public function test_an_online_paid_stay_stays_in_step_for_guest_staff_admin_and_the_database(): void
    {
        // 1. The guest books a Single room from today for 2 nights.
        Sanctum::actingAs($this->guest);
        $created = $this->postJson('/api/bookings', [
            'room_type_id' => $this->type('Single')->id,
            'check_in_date' => $this->day(0),
            'check_out_date' => $this->day(2),
            'guests' => 1,
        ])->assertCreated()->json('data');
        $id = $created['id'];

        // Only held for now: nobody sees it as paid, and nobody can check in.
        $v = $this->assertEveryoneAgrees($id, 'pending', false);
        $this->assertFalse($v['staffOne']['actions']['can_check_in']);

        // 2. The guest pays online by card. 15% off, one paid row in the database.
        Sanctum::actingAs($this->guest);
        $this->postJson("/api/bookings/{$id}/pay-card", [
            'number' => '4242 4242 4242 4242',
            'holder' => 'Sokha Demo',
            'expiry' => now()->addYear()->format('m/y'),
            'cvv' => '987',
        ])->assertOk();

        $v = $this->assertEveryoneAgrees($id, 'confirmed', true);
        $row = Booking::findOrFail($id);
        $payment = Payment::where('booking_id', $id)->sole();
        $this->assertSame(Payment::STATUS_PAID, $payment->status);
        $this->assertSame(Payment::METHOD_ONLINE, $payment->method);
        $this->assertEqualsWithDelta((float) $row->total_price - (float) $row->discount_amount, (float) $payment->amount, 0.001);
        $this->assertNull($row->checked_in_at);
        $this->assertTrue($v['staffOne']['actions']['can_check_in']);
        $this->assertSame(1, $v['dashboard']['today']['check_ins']);
        $this->assertSame(0, $v['dashboard']['today']['checked_in_so_far']);
        $this->assertSame(0, $v['dashboard']['rooms']['occupied']);

        // 3. Staff scan the guest's QR and check in. The database saves who and when.
        Sanctum::actingAs($this->staff);
        $this->postJson("/api/staff/bookings/{$id}/check-in")->assertOk()->assertJsonPath('data.status', 'checked_in');

        $v = $this->assertEveryoneAgrees($id, 'checked_in', true);
        $row = Booking::findOrFail($id);
        $this->assertSame($this->staff->id, $row->checked_in_by);
        $this->assertNotNull($row->checked_in_at);
        $this->assertNull($row->checked_out_at);
        $this->assertSame('Front Desk', $v['staffOne']['checked_in_by']['name']);
        $this->assertSame(1, $v['dashboard']['today']['checked_in_so_far']);
        $this->assertSame(1, $v['dashboard']['rooms']['occupied']);
        $this->assertFalse($v['staffOne']['actions']['can_check_in']);
        $this->assertTrue($v['staffOne']['actions']['can_check_out']);

        // A second scan of the same QR changes nothing.
        $stamp = $row->checked_in_at->toDateTimeString();
        Sanctum::actingAs($this->staff);
        $this->postJson("/api/staff/bookings/{$id}/check-in")->assertStatus(422);
        $this->assertSame($stamp, Booking::findOrFail($id)->checked_in_at->toDateTimeString());

        // 4. The admin checks the guest out (an admin may do what staff do). Saved with the admin's id.
        $this->travel(5)->hours();
        Sanctum::actingAs($this->admin);
        $this->postJson("/api/staff/bookings/{$id}/check-out")->assertOk()->assertJsonPath('data.status', 'checked_out');

        $v = $this->assertEveryoneAgrees($id, 'checked_out', true);
        $row = Booking::findOrFail($id);
        $this->assertSame($this->admin->id, $row->checked_out_by);
        $this->assertSame($this->staff->id, $row->checked_in_by); // the check-in is still the staff member's
        $this->assertTrue($row->checked_out_at->gte($row->checked_in_at));
        $this->assertSame('The Boss', $v['staffOne']['checked_out_by']['name']);
        $this->assertSame(0, $v['dashboard']['rooms']['occupied']); // the room is free again

        // The money is still one paid payment, and the guest cannot check out twice.
        $this->assertSame(1, Payment::where('booking_id', $id)->where('status', Payment::STATUS_PAID)->count());
        $this->postJson("/api/staff/bookings/{$id}/check-out")->assertStatus(422);
        $this->assertSame('checked_out', Booking::findOrFail($id)->status);
    }

    public function test_a_guest_cannot_move_their_own_booking_to_checked_in_or_out(): void
    {
        $booking = $this->makeBooking($this->guest, ['status' => 'confirmed', 'hold' => null, 'in' => 0, 'out' => 2]);
        Payment::create([
            'booking_id' => $booking->id, 'amount' => 25, 'method' => 'online', 'status' => 'paid',
            'reference' => 'x-'.$booking->id, 'paid_at' => now(),
        ]);

        Sanctum::actingAs($this->guest);
        $this->postJson("/api/staff/bookings/{$booking->id}/check-in")->assertForbidden();
        $this->postJson("/api/staff/bookings/{$booking->id}/check-out")->assertForbidden();

        $row = $booking->fresh();
        $this->assertSame('confirmed', $row->status);
        $this->assertNull($row->checked_in_at);
        $this->assertNull($row->checked_in_by);
    }

    public function test_a_failed_check_in_leaves_the_database_row_untouched(): void
    {
        // Pending (not paid): staff cannot check in, and nothing about the row changes.
        $booking = $this->makeBooking($this->guest, ['status' => 'pending', 'in' => 0, 'out' => 2]);
        $before = $booking->fresh()->only(['status', 'checked_in_at', 'checked_in_by', 'checked_out_at', 'checked_out_by']);

        Sanctum::actingAs($this->staff);
        $this->postJson("/api/staff/bookings/{$booking->id}/check-in")->assertStatus(422);
        $this->postJson("/api/staff/bookings/{$booking->id}/check-out")->assertStatus(422);

        $this->assertSame($before, $booking->fresh()->only(['status', 'checked_in_at', 'checked_in_by', 'checked_out_at', 'checked_out_by']));
    }
}
