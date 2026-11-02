<?php

namespace Tests\Feature;

use App\Models\Booking;
use App\Models\Payment;
use App\Models\Room;
use Database\Seeders\RoomSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\MakesBookings;
use Tests\Concerns\MakesUsers;
use Tests\TestCase;

/** Ticket 12: every dashboard number is counted from the database. */
class DashboardTest extends TestCase
{
    use MakesBookings;
    use MakesUsers;
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RoomSeeder::class);
    }

    private function room(string $n): Room
    {
        return Room::where('room_number', $n)->firstOrFail();
    }

    private function pay(Booking $b, float $amount, string $method, string $status = 'paid', $at = null): Payment
    {
        return Payment::create([
            'booking_id' => $b->id, 'amount' => $amount, 'method' => $method, 'status' => $status,
            'reference' => $method . '-' . $b->id, 'paid_at' => $at ?? now(),
        ]);
    }

    private function dashboard()
    {
        Sanctum::actingAs($this->makeUser('admin'));

        return $this->getJson('/api/admin/dashboard');
    }

    public function test_only_the_admin_can_see_it(): void
    {
        Sanctum::actingAs($this->makeUser('customer'));
        $this->getJson('/api/admin/dashboard')->assertForbidden();
        Sanctum::actingAs($this->makeUser('staff'));
        $this->getJson('/api/admin/dashboard')->assertForbidden();
    }

    public function test_an_empty_hotel_shows_zeros_and_all_rooms_free(): void
    {
        $this->dashboard()->assertOk()
            ->assertJsonPath('data.today.check_ins', 0)
            ->assertJsonPath('data.rooms.total', 15)
            ->assertJsonPath('data.rooms.free', 15)
            ->assertJsonPath('data.money.month', 0)
            ->assertJsonPath('data.pending.count', 0)
            ->assertJsonCount(7, 'data.last_7_days');
    }

    public function test_today_numbers(): void
    {
        $g = $this->makeUser('customer');
        // arriving today: one in, one paid but not in yet, one kept unpaid
        $this->makeBooking($g, ['room' => $this->room('101'), 'in' => 0, 'out' => 2, 'status' => 'checked_in', 'hold' => null]);
        $this->makeBooking($g, ['room' => $this->room('102'), 'in' => 0, 'out' => 2, 'status' => 'confirmed', 'hold' => null]);
        $this->makeKeptBooking($g, ['room' => $this->room('103'), 'in' => 0, 'out' => 1]);
        // never counted
        $this->makeBooking($g, ['room' => $this->room('104'), 'in' => 0, 'out' => 2, 'status' => 'cancelled', 'hold' => null]);
        $this->makeBooking($g, ['room' => $this->room('105'), 'in' => 0, 'out' => 2, 'hold' => now()->subMinute()]); // expired hold
        // leaving today: one still in, one gone
        $this->makeBooking($g, ['room' => $this->room('201'), 'in' => -2, 'out' => 0, 'status' => 'checked_in', 'hold' => null]);
        $this->makeBooking($g, ['room' => $this->room('202'), 'in' => -2, 'out' => 0, 'status' => 'checked_out', 'hold' => null]);

        $this->dashboard()->assertOk()
            ->assertJsonPath('data.today.check_ins', 3)
            ->assertJsonPath('data.today.checked_in_so_far', 1)
            ->assertJsonPath('data.today.check_outs', 2)
            ->assertJsonPath('data.today.checked_out_so_far', 1);
    }

    public function test_room_numbers_add_up(): void
    {
        $g = $this->makeUser('customer');
        $this->makeBooking($g, ['room' => $this->room('101'), 'in' => -1, 'out' => 1, 'status' => 'checked_in', 'hold' => null]);
        $this->makeBooking($g, ['room' => $this->room('102'), 'in' => -1, 'out' => 1, 'status' => 'checked_in', 'hold' => null]);
        $this->makeBooking($g, ['room' => $this->room('103'), 'in' => 3, 'out' => 5, 'status' => 'confirmed', 'hold' => null]); // future: not occupied
        $this->room('301')->update(['status' => Room::STATUS_MAINTENANCE]);

        $this->dashboard()->assertOk()
            ->assertJsonPath('data.rooms.total', 15)
            ->assertJsonPath('data.rooms.occupied', 2)
            ->assertJsonPath('data.rooms.maintenance', 1)
            ->assertJsonPath('data.rooms.free', 12);
    }

    public function test_money_splits_online_and_hotel_and_ignores_refunds_and_other_months(): void
    {
        $g = $this->makeUser('customer');
        $b = fn ($n) => $this->makeBooking($g, ['room' => $this->room($n), 'in' => 9, 'out' => 10, 'hold' => null, 'status' => 'confirmed']);

        $this->pay($b('101'), 25.50, 'online');                       // today, online
        $this->pay($b('102'), 30, 'cash');                            // today, hotel
        $this->pay($b('103'), 15, 'khqr', 'paid', now()->startOfMonth()); // earlier this month (if not the 1st it is not today)
        $this->pay($b('104'), 99, 'online', 'refunded');              // refunded: not income
        $this->pay($b('105'), 77, 'cash', 'paid', now()->subMonthNoOverflow()->startOfMonth()); // last month

        $res = $this->dashboard()->assertOk();
        $month = 25.5 + 30 + 15;
        $res->assertJsonPath('data.money.month', $month)
            ->assertJsonPath('data.money.month_online', 25.5)
            ->assertJsonPath('data.money.month_hotel', 45)
            ->assertJsonPath('data.money.month_refunded', 99);

        $todayExpected = now()->isSameDay(now()->startOfMonth()) ? $month : 55.5;
        $res->assertJsonPath('data.money.today', $todayExpected);
    }

    public function test_pending_list_has_kept_unpaid_bookings_soonest_first(): void
    {
        $g = $this->makeUser('customer', ['name' => 'Sokha']);
        $late = $this->makeKeptBooking($g, ['room' => $this->room('101'), 'in' => 20, 'out' => 22]);
        $soon = $this->makeKeptBooking($g, ['room' => $this->room('102'), 'in' => 2, 'out' => 3]);
        $this->makeBooking($g, ['room' => $this->room('103'), 'in' => 1]); // a running hold: not in the list
        $this->makeBooking($g, ['room' => $this->room('104'), 'in' => 1, 'status' => 'confirmed', 'hold' => null]);

        $this->dashboard()->assertOk()
            ->assertJsonPath('data.pending.count', 2)
            ->assertJsonPath('data.pending.items.0.id', $soon->id)
            ->assertJsonPath('data.pending.items.0.guest', 'Sokha')
            ->assertJsonPath('data.pending.items.0.amount_due', 15)
            ->assertJsonPath('data.pending.items.1.id', $late->id);
    }

    public function test_last_seven_days_are_oldest_first_and_count_bookings_made_each_day(): void
    {
        $g = $this->makeUser('customer');
        $a = $this->makeKeptBooking($g, ['room' => $this->room('101')]);
        $a->forceFill(['created_at' => now()->subDays(2)])->save();
        $this->makeKeptBooking($g, ['room' => $this->room('102'), 'in' => 8]); // today
        $this->makeKeptBooking($g, ['room' => $this->room('103'), 'in' => 9]); // today
        $old = $this->makeKeptBooking($g, ['room' => $this->room('104'), 'in' => 10]);
        $old->forceFill(['created_at' => now()->subDays(10)])->save(); // too old
        $c = $this->makeBooking($g, ['room' => $this->room('105'), 'in' => 11, 'status' => 'cancelled', 'hold' => null]); // cancelled: not counted

        $days = $this->dashboard()->assertOk()->json('data.last_7_days');

        $this->assertSame(now()->subDays(6)->toDateString(), $days[0]['date']);
        $this->assertSame(now()->toDateString(), $days[6]['date']);
        $this->assertSame(1, $days[4]['bookings']);
        $this->assertSame(2, $days[6]['bookings']);
        $this->assertSame(3, array_sum(array_column($days, 'bookings')));
    }
}
