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

/** A guest deletes a finished booking from their account; the hotel keeps its record. */
class BookingDeleteTest extends TestCase
{
    use MakesBookings;
    use MakesUsers;
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RoomSeeder::class);
    }

    private function finished(\App\Models\User $guest, string $status, array $o = []): Booking
    {
        $b = $this->makeBooking($guest, $o);
        $b->update(['status' => $status, 'hold_expires_at' => null]);

        return $b;
    }

    public function test_a_guest_can_delete_a_cancelled_booking_and_it_is_gone_for_good(): void
    {
        $guest = $this->makeUser('customer');
        $b = $this->finished($guest, Booking::STATUS_CANCELLED);
        Sanctum::actingAs($guest);

        $this->deleteJson("/api/bookings/{$b->id}")->assertOk();

        $this->getJson('/api/bookings')->assertOk()->assertJsonCount(0, 'data');
        $this->getJson("/api/bookings/{$b->id}")->assertNotFound();
        $this->deleteJson("/api/bookings/{$b->id}")->assertNotFound(); // nothing left to delete
    }

    public function test_no_show_and_checked_out_bookings_can_be_deleted_too(): void
    {
        $guest = $this->makeUser('customer');
        $a = $this->finished($guest, Booking::STATUS_NO_SHOW, ['in' => 10]);
        $c = $this->finished($guest, Booking::STATUS_CHECKED_OUT, ['in' => 20]);
        Sanctum::actingAs($guest);

        $this->deleteJson("/api/bookings/{$a->id}")->assertOk();
        $this->deleteJson("/api/bookings/{$c->id}")->assertOk();
    }

    public function test_a_running_booking_cannot_be_deleted_it_must_be_cancelled_first(): void
    {
        $guest = $this->makeUser('customer');
        $pending = $this->makeBooking($guest, ['in' => 10]);
        $confirmed = $this->finished($guest, Booking::STATUS_CONFIRMED, ['in' => 20]);
        $checkedIn = $this->finished($guest, Booking::STATUS_CHECKED_IN, ['in' => 30]);
        Sanctum::actingAs($guest);

        foreach ([$pending, $confirmed, $checkedIn] as $b) {
            $this->deleteJson("/api/bookings/{$b->id}")
                ->assertStatus(422)
                ->assertJsonPath('code', 'cannot_delete');
            $this->assertNull($b->fresh()->guest_deleted_at);
        }
    }

    public function test_a_guest_cannot_delete_someone_elses_booking(): void
    {
        $owner = $this->makeUser('customer');
        $other = $this->makeUser('customer');
        $b = $this->finished($owner, Booking::STATUS_CANCELLED);

        Sanctum::actingAs($other);
        $this->deleteJson("/api/bookings/{$b->id}")->assertNotFound();
        $this->assertNull($b->fresh()->guest_deleted_at);
    }

    public function test_you_must_be_logged_in(): void
    {
        $b = $this->finished($this->makeUser('customer'), Booking::STATUS_CANCELLED);

        $this->deleteJson("/api/bookings/{$b->id}")->assertUnauthorized();
    }

    public function test_the_hotel_keeps_the_booking_and_its_money_record(): void
    {
        $guest = $this->makeUser('customer');
        $b = $this->finished($guest, Booking::STATUS_NO_SHOW);
        Payment::create([
            'booking_id' => $b->id, 'amount' => $b->total_price, 'method' => Payment::METHOD_KHQR,
            'status' => Payment::STATUS_PAID, 'reference' => 'DEL-1', 'paid_at' => now(),
        ]);

        Sanctum::actingAs($guest);
        $this->deleteJson("/api/bookings/{$b->id}")->assertOk();

        // The row and the payment are still there, and staff still see them.
        $this->assertDatabaseHas('bookings', ['id' => $b->id]);
        $this->assertDatabaseCount('payments', 1);

        Sanctum::actingAs($this->makeUser('staff'));
        $this->getJson("/api/staff/bookings/{$b->id}")
            ->assertOk()
            ->assertJsonPath('data.status', 'no_show');
    }

    public function test_a_deleted_booking_cannot_be_used_by_the_guest_any_more(): void
    {
        $guest = $this->makeUser('customer');
        $b = $this->finished($guest, Booking::STATUS_CANCELLED);
        Sanctum::actingAs($guest);
        $this->deleteJson("/api/bookings/{$b->id}")->assertOk();

        $this->postJson("/api/bookings/{$b->id}/cancel")->assertNotFound();
        $this->postJson("/api/bookings/{$b->id}/pay-at-hotel")->assertNotFound();
        $this->postJson("/api/bookings/{$b->id}/pay-qr")->assertNotFound();
    }
}
