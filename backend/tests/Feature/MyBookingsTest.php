<?php

namespace Tests\Feature;

use App\Models\Booking;
use App\Models\Payment;
use App\Payments\PaymentGateway;
use Database\Seeders\RoomSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\MakesBookings;
use Tests\Concerns\MakesUsers;
use Tests\Support\FakeGateway;
use Tests\TestCase;

/** Ticket 09: my bookings, cancel with refund, profile. */
class MyBookingsTest extends TestCase
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

    private function pay(Booking $b, string $method, string $ref = 'ref-1'): Payment
    {
        $b->update(['status' => Booking::STATUS_CONFIRMED, 'hold_expires_at' => null]);

        return Payment::create([
            'booking_id' => $b->id,
            'amount' => $b->total_price,
            'method' => $method,
            'status' => Payment::STATUS_PAID,
            'reference' => $ref,
            'paid_at' => now(),
        ]);
    }

    public function test_list_shows_only_my_bookings_and_hides_expired_holds(): void
    {
        $me = $this->makeUser('customer');
        $other = $this->makeUser('customer');
        $kept = $this->makeKeptBooking($me);
        $this->makeBooking($me, ['hold' => now()->subMinute(), 'in' => 20]);
        $this->makeBooking($other, ['in' => 30]);

        Sanctum::actingAs($me);
        $this->getJson('/api/bookings')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $kept->id);
    }

    public function test_list_needs_login(): void
    {
        $this->getJson('/api/bookings')->assertUnauthorized();
    }

    public function test_cancel_unpaid_booking_frees_the_room(): void
    {
        $me = $this->makeUser('customer');
        $b = $this->makeKeptBooking($me);

        Sanctum::actingAs($me);
        $this->postJson("/api/bookings/{$b->id}/cancel")
            ->assertOk()
            ->assertJsonPath('data.status', 'cancelled');

        $this->assertSame(Booking::STATUS_CANCELLED, $b->fresh()->status);
    }

    public function test_cancel_online_paid_refunds_in_full(): void
    {
        $me = $this->makeUser('customer');
        $b = $this->makeBooking($me);
        $p = $this->pay($b, Payment::METHOD_ONLINE, 'AS1-REAL');

        Sanctum::actingAs($me);
        $this->postJson("/api/bookings/{$b->id}/cancel")
            ->assertOk()
            ->assertJsonPath('data.status', 'cancelled')
            ->assertJsonPath('data.refunded_amount', 30);

        $this->assertSame(['AS1-REAL'], $this->gateway->refunds);
        $this->assertSame(Payment::STATUS_REFUNDED, $p->fresh()->status);
    }

    public function test_demo_payment_is_marked_refunded_without_calling_the_gateway(): void
    {
        $me = $this->makeUser('customer');
        $b = $this->makeBooking($me);
        $p = $this->pay($b, Payment::METHOD_ONLINE, 'demo-123');

        Sanctum::actingAs($me);
        $this->postJson("/api/bookings/{$b->id}/cancel")->assertOk();

        $this->assertSame([], $this->gateway->refunds);
        $this->assertSame(Payment::STATUS_REFUNDED, $p->fresh()->status);
    }

    public function test_failed_refund_cancels_nothing(): void
    {
        $me = $this->makeUser('customer');
        $b = $this->makeBooking($me);
        $p = $this->pay($b, Payment::METHOD_ONLINE, 'AS1-REAL');
        $this->gateway->failRefund = true;

        Sanctum::actingAs($me);
        $this->postJson("/api/bookings/{$b->id}/cancel")
            ->assertStatus(502)
            ->assertJsonPath('code', 'refund_failed');

        $this->assertSame(Booking::STATUS_CONFIRMED, $b->fresh()->status);
        $this->assertSame(Payment::STATUS_PAID, $p->fresh()->status);
    }

    public function test_paid_at_front_desk_cannot_be_cancelled_by_guest(): void
    {
        $me = $this->makeUser('customer');
        $b = $this->makeKeptBooking($me);
        $this->pay($b, Payment::METHOD_CASH);

        Sanctum::actingAs($me);
        $this->postJson("/api/bookings/{$b->id}/cancel")
            ->assertStatus(422)
            ->assertJsonPath('code', 'paid_at_hotel');

        $this->assertSame(Booking::STATUS_CONFIRMED, $b->fresh()->status);
    }

    public function test_checked_in_booking_cannot_be_cancelled(): void
    {
        $me = $this->makeUser('customer');
        $b = $this->makeBooking($me, ['status' => Booking::STATUS_CHECKED_IN, 'hold' => null]);

        Sanctum::actingAs($me);
        $this->postJson("/api/bookings/{$b->id}/cancel")
            ->assertStatus(422)
            ->assertJsonPath('code', 'cannot_cancel');
    }

    public function test_cannot_cancel_someone_elses_booking(): void
    {
        $b = $this->makeKeptBooking($this->makeUser('customer'));

        Sanctum::actingAs($this->makeUser('customer'));
        $this->postJson("/api/bookings/{$b->id}/cancel")->assertNotFound();
        $this->assertSame(Booking::STATUS_PENDING, $b->fresh()->status);
    }

    public function test_cancel_twice_is_refused_and_refunds_once(): void
    {
        $me = $this->makeUser('customer');
        $b = $this->makeBooking($me);
        $this->pay($b, Payment::METHOD_ONLINE, 'AS1-REAL');

        Sanctum::actingAs($me);
        $this->postJson("/api/bookings/{$b->id}/cancel")->assertOk();
        $this->postJson("/api/bookings/{$b->id}/cancel")->assertStatus(422);

        $this->assertCount(1, $this->gateway->refunds);
    }

    public function test_profile_changes_name_and_phone_but_never_email_or_role(): void
    {
        $me = $this->makeUser('customer');

        Sanctum::actingAs($me);
        $this->patchJson('/api/auth/profile', [
            'name' => 'New Name', 'phone' => '012 345 678',
            'email' => 'hacker@x.test', 'role' => 'admin',
        ])->assertOk()->assertJsonPath('data.name', 'New Name');

        $me->refresh();
        $this->assertSame('012 345 678', $me->phone);
        $this->assertSame('customer', $me->role);
        $this->assertNotSame('hacker@x.test', $me->email);
    }

    public function test_profile_rejects_a_bad_phone(): void
    {
        Sanctum::actingAs($this->makeUser('customer'));
        $this->patchJson('/api/auth/profile', ['phone' => 'abc'])->assertStatus(422)->assertJsonValidationErrors('phone');
    }

    public function test_change_password_needs_the_current_one(): void
    {
        $me = $this->makeUser('customer');
        Sanctum::actingAs($me);

        $this->postJson('/api/auth/change-password', [
            'current_password' => 'wrong-one', 'password' => 'brand-new-pass', 'password_confirmation' => 'brand-new-pass',
        ])->assertStatus(422)->assertJsonValidationErrors('current_password');
    }

    public function test_change_password_works_and_logs_out_other_phones(): void
    {
        $me = $this->makeUser('customer', ['password' => 'old-password-1']);
        $other = $me->createToken('other-phone');
        $me->createToken('this-phone');
        Sanctum::actingAs($me, [], 'sanctum');

        $this->postJson('/api/auth/change-password', [
            'current_password' => 'old-password-1', 'password' => 'brand-new-pass', 'password_confirmation' => 'brand-new-pass',
        ])->assertOk();

        $this->assertTrue(Hash::check('brand-new-pass', $me->fresh()->password));
        $this->assertDatabaseMissing('personal_access_tokens', ['id' => $other->accessToken->id]);
    }
}
