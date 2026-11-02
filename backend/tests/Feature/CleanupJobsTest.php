<?php

namespace Tests\Feature;

use App\Models\Booking;
use App\Models\Payment;
use App\Payments\PaymentGateway;
use Database\Seeders\RoomSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\MakesBookings;
use Tests\Concerns\MakesUsers;
use Tests\Support\FakeGateway;
use Tests\TestCase;

/** Ticket 10: the automatic jobs. */
class CleanupJobsTest extends TestCase
{
    use MakesBookings;
    use MakesUsers;
    use RefreshDatabase;

    private FakeGateway $gateway;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RoomSeeder::class);
        $this->gateway = new FakeGateway();
        $this->app->instance(PaymentGateway::class, $this->gateway);
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

    public function test_no_show_refunds_online_money_in_full(): void
    {
        $g = $this->makeUser('customer');
        $b = $this->makeBooking($g, ['in' => 0, 'out' => 2]);
        $p = $this->paidOnline($b);

        $this->travelTo(now()->addDay()->setTime(13, 0));
        $this->artisan('hotel:clean-up')->assertSuccessful();

        $this->assertSame('no_show', $b->fresh()->status);
        $this->assertSame(['AS1-REAL'], $this->gateway->refunds);
        $this->assertSame(Payment::STATUS_REFUNDED, $p->fresh()->status);
    }

    public function test_failed_refund_leaves_the_booking_for_the_next_run(): void
    {
        $g = $this->makeUser('customer');
        $b = $this->makeBooking($g, ['in' => 0, 'out' => 2]);
        $p = $this->paidOnline($b);
        $this->gateway->failRefund = true;

        $this->travelTo(now()->addDay()->setTime(13, 0));
        $this->artisan('hotel:clean-up')->assertFailed();

        $this->assertSame('confirmed', $b->fresh()->status);
        $this->assertSame(Payment::STATUS_PAID, $p->fresh()->status);

        $this->gateway->failRefund = false;
        $this->artisan('hotel:clean-up')->assertSuccessful();
        $this->assertSame('no_show', $b->fresh()->status);
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

        $this->assertCount(1, $this->gateway->refunds);
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
