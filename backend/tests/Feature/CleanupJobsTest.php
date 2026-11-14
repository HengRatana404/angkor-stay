<?php

namespace Tests\Feature;

use App\Models\Booking;
use App\Models\Payment;
use Database\Seeders\RoomSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\MakesBookings;
use Tests\Concerns\MakesUsers;
use Tests\TestCase;

/** Ticket 10: the automatic jobs. */
class CleanupJobsTest extends TestCase
{
    use MakesBookings;
    use MakesUsers;
    use RefreshDatabase;


    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RoomSeeder::class);
    }

    private function paidOnline(Booking $b, string $ref = 'AS1-REAL'): Payment
    {
        $b->update(['status' => Booking::STATUS_CONFIRMED, 'hold_expires_at' => null]);

        return Payment::create([
            'booking_id' => $b->id, 'amount' => $b->total_price, 'method' => Payment::METHOD_ONLINE,
            'status' => Payment::STATUS_PAID, 'reference' => $ref, 'paid_at' => now(),
        ]);
    }

    public function test_expired_hold_is_cancelled_but_running_and_kept_ones_stay(): void
    {
        $g = $this->makeUser('customer');
        $old = $this->makeBooking($g, ['hold' => now()->subMinute()]);
        $running = $this->makeBooking($g, ['hold' => now()->addMinutes(3), 'in' => 20]);
        $kept = $this->makeKeptBooking($g, ['in' => 30]);

        $this->artisan('hotel:clean-up')->assertSuccessful();

        $this->assertSame('cancelled', $old->fresh()->status);
        $this->assertSame('pending', $running->fresh()->status);
        $this->assertSame('pending', $kept->fresh()->status);
    }

    public function test_no_show_waits_until_noon_the_day_after_check_in(): void
    {
        $g = $this->makeUser('customer');
        $b = $this->makeKeptBooking($g, ['in' => 0, 'out' => 2]); // check-in today

        $this->travelTo(now()->addDay()->setTime(11, 59));
        $this->artisan('hotel:clean-up');
        $this->assertSame('pending', $b->fresh()->status);

        $this->travelTo(now()->setTime(12, 0));
        $this->artisan('hotel:clean-up');
        $this->assertSame('no_show', $b->fresh()->status);
    }

    public function test_a_late_guest_cannot_be_checked_in_once_the_clean_up_would_call_it_a_no_show(): void
    {
        // One rule for both: noon the day after check-in (found by the code review: the desk
        // used to allow check-in until the last day while the clean-up refunded and cancelled).
        $g = $this->makeUser('customer');
        $b = $this->makeBooking($g, ['in' => 0, 'out' => 3]);
        $b->update(['status' => Booking::STATUS_CONFIRMED, 'hold_expires_at' => null]);

        $this->travelTo(now()->addDay()->setTime(11, 59));
        $this->assertNull($b->fresh()->checkInProblem());

        $this->travelTo(now()->setTime(12, 0));
        $this->assertStringContainsString('no-show', (string) $b->fresh()->checkInProblem());

        $this->artisan('hotel:clean-up');
        $this->assertSame('no_show', $b->fresh()->status);
    }

    public function test_no_show_refunds_online_money_in_full(): void
    {
        $g = $this->makeUser('customer');
        $b = $this->makeBooking($g, ['in' => 0, 'out' => 2]);
        $p = $this->paidOnline($b);

        $this->travelTo(now()->addDay()->setTime(13, 0));
        $this->artisan('hotel:clean-up')->assertSuccessful();

        $this->assertSame('no_show', $b->fresh()->status);
        $this->assertSame('refunded', Payment::firstOrFail()->status);
        $this->assertSame(Payment::STATUS_REFUNDED, $p->fresh()->status);
    }

    public function test_checked_in_and_future_bookings_are_never_touched(): void
    {
        $g = $this->makeUser('customer');
        $in = $this->makeBooking($g, ['in' => -1, 'out' => 2, 'status' => Booking::STATUS_CHECKED_IN, 'hold' => null]);
        $future = $this->makeKeptBooking($g, ['in' => 10, 'out' => 12]);

        $this->travelTo(now()->addDay()->setTime(13, 0));
        $this->artisan('hotel:clean-up')->assertSuccessful();

        $this->assertSame('checked_in', $in->fresh()->status);
        $this->assertSame('pending', $future->fresh()->status);
    }

    public function test_running_it_twice_changes_nothing_the_second_time(): void
    {
        $g = $this->makeUser('customer');
        $b = $this->makeBooking($g, ['in' => 0, 'out' => 2]);
        $this->paidOnline($b);

        $this->travelTo(now()->addDay()->setTime(13, 0));
        $this->artisan('hotel:clean-up');
        $this->artisan('hotel:clean-up');

        $this->assertSame(1, Payment::where('status', Payment::STATUS_REFUNDED)->count());
    }

    public function test_a_freed_room_can_be_booked_again(): void
    {
        $g = $this->makeUser('customer');
        $this->leaveOnlyOneVipRoom();
        $room = \App\Models\Room::where('room_number', '301')->first();
        $this->makeKeptBooking($g, ['room' => $room, 'in' => 0, 'out' => 2]);

        $this->travelTo(now()->addDay()->setTime(13, 0));
        $this->artisan('hotel:clean-up');

        $this->assertSame(
            1,
            app(\App\Services\AvailabilityService::class)
                ->freeRooms($this->type('VIP'), now()->addDay()->toDateString(), now()->addDays(3)->toDateString())->count()
        );
    }

    public function test_admin_can_run_it_from_the_api_but_staff_and_guests_cannot(): void
    {
        $g = $this->makeUser('customer');
        $this->makeBooking($g, ['hold' => now()->subMinute()]);

        Sanctum::actingAs($this->makeUser('customer'));
        $this->postJson('/api/admin/maintenance/run')->assertForbidden();

        Sanctum::actingAs($this->makeUser('staff'));
        $this->postJson('/api/admin/maintenance/run')->assertForbidden();

        Sanctum::actingAs($this->makeUser('admin'));
        $this->postJson('/api/admin/maintenance/run')
            ->assertOk()
            ->assertJsonPath('data.expired_holds', 1)
            ->assertJsonPath('data.no_shows', 0);
    }
}
