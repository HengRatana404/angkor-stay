<?php

namespace Tests\Feature;

use App\Models\Booking;
use App\Models\Payment;
use App\Models\Room;
use App\Models\User;
use App\Payments\PaymentGateway;
use App\Services\SettingsService;
use Database\Seeders\RoomSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\MakesBookings;
use Tests\Concerns\MakesUsers;
use Tests\Support\FakeGateway;
use Tests\TestCase;

/** Paying online: the discount, the payment page, and the server checking the payment itself. */
class OnlinePaymentTest extends TestCase
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

    private function settings(): SettingsService
    {
        return app(SettingsService::class);
    }

    private function demoMode(bool $on = true): void
    {
        $this->settings()->update(['demo_payment_mode' => $on]);
    }

    private function startOnline(User $guest, Booking $booking)
    {
        Sanctum::actingAs($guest);

        return $this->postJson("/api/bookings/{$booking->id}/pay-online");
    }

    private function verify(User $guest, Booking $booking)
    {
        Sanctum::actingAs($guest);

        return $this->postJson("/api/bookings/{$booking->id}/verify-payment");
    }

    private function demoPay(User $guest, Booking $booking)
    {
        Sanctum::actingAs($guest);

        return $this->postJson("/api/bookings/{$booking->id}/demo-pay");
    }

    /** A guest who started paying online and then paid on Stripe's page. */
    private function paidOnStripe(?array $override = []): array
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest); // 2 nights x $15 = $30, 15% off = $25.50
        $this->startOnline($guest, $booking)->assertOk();
        $session = $this->gateway->lastSessionId();
        $this->gateway->pay($session, $override);

        return [$guest, $booking, $session];
    }

    // ------------------------------------------------------- public settings

    public function test_the_discount_and_times_are_public_and_follow_the_admin(): void
    {
        $this->getJson('/api/settings/public')
            ->assertOk()
            ->assertExactJson(['data' => [
                'online_discount_percent' => 15,
                'check_in_time' => '14:00',
                'check_out_time' => '12:00',
            ]]);

        $this->settings()->update(['online_discount_percent' => 25, 'check_in_time' => '13:30']);

        $this->getJson('/api/settings/public')
            ->assertOk()
            ->assertJsonPath('data.online_discount_percent', 25)
            ->assertJsonPath('data.check_in_time', '13:30');
    }

    // ------------------------------------------------------ starting (Stripe)

    public function test_starting_opens_a_payment_page_for_the_discounted_price(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);

        $response = $this->startOnline($guest, $booking)
            ->assertOk()
            ->assertJsonPath('mode', 'online')
            ->assertJsonPath('data.payment_choice', 'online')
            ->assertJsonPath('data.discount_percent', 15)
            ->assertJsonPath('data.discount_amount', 4.5)
            ->assertJsonPath('data.amount_due', 25.5)
            ->assertJsonPath('data.total_price', 30);

        $this->assertCount(1, $this->gateway->created);
        $page = $this->gateway->created[0];
        $this->assertSame(2550, $page['amount_cents']); // $25.50 in cents
        $this->assertSame($booking->id, $page['booking_id']);
        $this->assertSame($this->gateway->lastSessionId(), $booking->fresh()->checkout_session_id);
        $this->assertStringContainsString('/payment/success?booking=' . $booking->id, $page['success_url']);
        $this->assertStringContainsString('/payment/cancelled?booking=' . $booking->id, $page['cancel_url']);
        $this->assertStringStartsWith('https://checkout.stripe.test/pay/', $response->json('checkout_url'));
    }

    public function test_the_discount_follows_the_admin_setting_and_rounds_to_cents(): void
    {
        $guest = $this->makeUser('customer');

        $this->settings()->update(['online_discount_percent' => 20]);
        $a = $this->makeBooking($guest, ['room' => Room::where('room_number', '101')->first()]);
        $this->startOnline($guest, $a)->assertOk()->assertJsonPath('data.amount_due', 24);
        $this->assertSame(2400, $this->gateway->created[0]['amount_cents']);

        $this->settings()->update(['online_discount_percent' => 0]);
        $b = $this->makeBooking($guest, ['room' => Room::where('room_number', '102')->first()]);
        $this->startOnline($guest, $b)->assertOk()->assertJsonPath('data.discount_percent', 0)->assertJsonPath('data.amount_due', 30);
        $this->assertSame(3000, $this->gateway->created[1]['amount_cents']);

        // 1 night x $15 = $15. 15% off = $2.25, so $12.75.
        $this->settings()->update(['online_discount_percent' => 15]);
        $guest2 = $this->makeUser('customer');
        $c = $this->makeBooking($guest2, ['room' => Room::where('room_number', '103')->first(), 'in' => 5, 'out' => 6]);
        $this->startOnline($guest2, $c)->assertOk()
            ->assertJsonPath('data.discount_amount', 2.25)
            ->assertJsonPath('data.amount_due', 12.75);
        $this->assertSame(1275, $this->gateway->created[2]['amount_cents']);
    }

    public function test_a_later_change_of_the_setting_does_not_change_a_started_payment(): void
    {
        [$guest, $booking] = $this->paidOnStripe(); // started at 15%
        $this->settings()->update(['online_discount_percent' => 40]);

        $this->assertEquals(25.5, $booking->fresh()->amount_due);

        // Stripe was asked for $25.50, so $25.50 is what the server expects, and it still works.
        $this->verify($guest, $booking)->assertOk()->assertJsonPath('data.status', 'confirmed');
    }

    public function test_starting_gives_a_running_hold_more_time(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest); // 5 minutes

        $response = $this->startOnline($guest, $booking)->assertOk();

        $left = $response->json('data.hold_seconds_left');
        $this->assertGreaterThan(890, $left);
        $this->assertLessThanOrEqual(900, $left);
    }

    public function test_a_room_kept_for_the_hotel_stays_kept_when_the_guest_tries_online(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeKeptBooking($guest);

        $this->startOnline($guest, $booking)->assertOk()->assertJsonPath('data.hold_seconds_left', null);

        $this->assertNull($booking->fresh()->hold_expires_at);
    }

    public function test_starting_again_closes_the_first_page_and_uses_a_new_one(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);

        $this->startOnline($guest, $booking)->assertOk();
        $first = $this->gateway->lastSessionId();
        $this->startOnline($guest, $booking)->assertOk();
        $second = $this->gateway->lastSessionId();

        $this->assertNotSame($first, $second);
        $this->assertSame([$first], $this->gateway->expired);
        $this->assertSame($second, $booking->fresh()->checkout_session_id);
    }

    // ----------------------------------------------------- starting: refusals

    public function test_starting_needs_a_login_and_your_own_booking(): void
    {
        $booking = $this->makeBooking($this->makeUser('customer'));

        $this->postJson("/api/bookings/{$booking->id}/pay-online")->assertUnauthorized();

        $this->startOnline($this->makeUser('customer'), $booking)->assertNotFound();
        $this->assertSame([], $this->gateway->created);
    }

    public function test_a_booking_that_is_not_pending_cannot_start_paying(): void
    {
        $guest = $this->makeUser('customer');

        foreach (['confirmed', 'cancelled', 'checked_in', 'no_show'] as $i => $status) {
            $booking = $this->makeBooking($guest, ['room' => Room::where('room_number', '10' . ($i + 1))->first(), 'status' => $status, 'hold' => null]);

            $this->startOnline($guest, $booking)->assertStatus(422)->assertJsonPath('code', 'not_pending');
        }

        $this->assertSame([], $this->gateway->created);
    }

    public function test_after_the_five_minutes_the_guest_cannot_start_paying_and_is_never_charged(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest, ['hold' => now()->subMinute()]);

        $this->startOnline($guest, $booking)->assertStatus(409)->assertJsonPath('code', 'hold_expired');

        $this->assertSame([], $this->gateway->created);
        $this->assertNull($booking->fresh()->payment_choice);
    }

    public function test_without_a_stripe_key_and_without_demo_mode_online_payment_is_unavailable(): void
    {
        $this->gateway->configured = false;
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);

        $this->startOnline($guest, $booking)
            ->assertStatus(503)
            ->assertJsonPath('code', 'online_payment_unavailable');

        $fresh = $booking->fresh();
        $this->assertNull($fresh->payment_choice);
        $this->assertSame(0, $fresh->discount_percent);
        $this->assertSame([], $this->gateway->created);
    }

    public function test_when_stripe_fails_nothing_changes(): void
    {
        $this->gateway->failCreate = true;
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);
        $holdBefore = $booking->hold_expires_at->toDateTimeString();

        $this->startOnline($guest, $booking)->assertStatus(502)->assertJsonPath('code', 'provider_error');

        $fresh = $booking->fresh();
        $this->assertNull($fresh->payment_choice);
        $this->assertSame(0, $fresh->discount_percent);
        $this->assertNull($fresh->checkout_session_id);
        $this->assertSame($holdBefore, $fresh->hold_expires_at->toDateTimeString());
    }

    public function test_an_amount_under_50_cents_is_refused_for_stripe(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);
        $booking->forceFill(['total_price' => 0.40])->save();

        $this->startOnline($guest, $booking)->assertStatus(422)->assertJsonPath('code', 'amount_too_small');
    }

    // --------------------------------------------------- verifying the payment

    public function test_the_server_confirms_the_booking_only_after_stripe_says_paid(): void
    {
        [$guest, $booking, $session] = $this->paidOnStripe();

        $this->verify($guest, $booking)
            ->assertOk()
            ->assertJsonPath('data.status', 'confirmed')
            ->assertJsonPath('data.paid', true)
            ->assertJsonPath('data.payment_method', 'online')
            ->assertJsonPath('data.amount_due', 25.5)
            ->assertJsonPath('data.hold_seconds_left', null);

        $payment = Payment::firstOrFail();
        $this->assertSame($booking->id, $payment->booking_id);
        $this->assertEquals(25.5, $payment->amount);
        $this->assertSame('online', $payment->method);
        $this->assertSame('paid', $payment->status);
        $this->assertNull($payment->received_by); // no staff member took this money
        $this->assertSame('pi_test_' . $session, $payment->reference);

        $fresh = $booking->fresh();
        $this->assertSame('confirmed', $fresh->status);
        $this->assertNull($fresh->hold_expires_at);
        $this->assertNull($fresh->checkout_session_id);
    }

    public function test_asking_twice_does_not_pay_twice(): void
    {
        [$guest, $booking] = $this->paidOnStripe();

        $this->verify($guest, $booking)->assertOk();
        $this->verify($guest, $booking)->assertOk()->assertJsonPath('data.status', 'confirmed');

        $this->assertSame(1, Payment::count());
    }

    public function test_nothing_is_confirmed_while_the_guest_has_not_paid(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);
        $this->startOnline($guest, $booking)->assertOk();

        $this->verify($guest, $booking)->assertStatus(409)->assertJsonPath('code', 'payment_not_completed');

        $this->assertSame(0, Payment::count());
        $this->assertSame('pending', $booking->fresh()->status);
    }

    public function test_a_payment_for_the_wrong_amount_is_not_accepted(): void
    {
        [$guest, $booking] = $this->paidOnStripe(['amount_cents' => 100]); // $1 instead of $25.50

        $this->verify($guest, $booking)->assertStatus(422)->assertJsonPath('code', 'payment_mismatch');

        $this->assertSame(0, Payment::count());
        $this->assertSame('pending', $booking->fresh()->status);
    }

    public function test_a_payment_for_another_booking_is_not_accepted(): void
    {
        [$guest, $booking] = $this->paidOnStripe(['booking_id' => 999999]);

        $this->verify($guest, $booking)->assertStatus(422)->assertJsonPath('code', 'payment_mismatch');

        $this->assertSame(0, Payment::count());
    }

    public function test_a_payment_in_another_currency_is_not_accepted(): void
    {
        [$guest, $booking] = $this->paidOnStripe(['currency' => 'khr']);

        $this->verify($guest, $booking)->assertStatus(422)->assertJsonPath('code', 'payment_mismatch');

        $this->assertSame(0, Payment::count());
    }

    public function test_a_guest_cannot_use_someone_elses_paid_page_for_their_own_booking(): void
    {
        // Guest A pays for booking A. Guest B points booking B at A's page.
        [, , $sessionA] = $this->paidOnStripe();
        $guestB = $this->makeUser('customer');
        $bookingB = $this->makeBooking($guestB, ['room' => Room::where('room_number', '102')->first()]);
        $this->startOnline($guestB, $bookingB)->assertOk();
        $bookingB->forceFill(['checkout_session_id' => $sessionA])->save();

        $this->verify($guestB, $bookingB)->assertStatus(422)->assertJsonPath('code', 'payment_mismatch');

        $this->assertSame('pending', $bookingB->fresh()->status);
    }

    public function test_verifying_without_a_started_payment_is_refused(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);

        $this->verify($guest, $booking)->assertStatus(409)->assertJsonPath('code', 'no_payment_started');
    }

    public function test_verifying_needs_a_login_and_your_own_booking(): void
    {
        [$guest, $booking] = $this->paidOnStripe();

        $this->verify($this->makeUser('customer'), $booking)->assertNotFound();

        $this->app['auth']->forgetGuards(); // nobody is logged in any more
        $this->postJson("/api/bookings/{$booking->id}/verify-payment")->assertUnauthorized();
        $this->assertSame('pending', $booking->fresh()->status);
    }

    public function test_a_page_that_expired_unpaid_says_so(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);
        $this->startOnline($guest, $booking)->assertOk();
        $this->gateway->sessions[$this->gateway->lastSessionId()]['expired'] = true;

        $this->verify($guest, $booking)->assertStatus(409)->assertJsonPath('code', 'session_expired');
    }

    public function test_when_stripe_cannot_be_reached_the_booking_stays_pending(): void
    {
        [$guest, $booking] = $this->paidOnStripe();
        $this->gateway->failRetrieve = true;

        $this->verify($guest, $booking)->assertStatus(502)->assertJsonPath('code', 'provider_error');

        $this->assertSame('pending', $booking->fresh()->status);
        $this->assertSame(0, Payment::count());
    }

    // ------------------------------------------------------ paying too late

    public function test_a_guest_who_pays_late_still_gets_the_room_if_it_is_still_free(): void
    {
        [$guest, $booking] = $this->paidOnStripe();
        $this->travel(20)->minutes(); // the 15 minutes ran out

        $this->verify($guest, $booking)->assertOk()->assertJsonPath('data.status', 'confirmed');

        $this->assertSame(1, Payment::where('status', 'paid')->count());
        $this->assertSame([], $this->gateway->refunds);
    }

    public function test_a_guest_who_pays_late_is_refunded_when_the_room_was_taken(): void
    {
        [$guest, $booking, $session] = $this->paidOnStripe();
        $this->travel(20)->minutes();

        // Someone else took the same room for the same nights.
        $other = $this->makeBooking($this->makeUser('customer'), ['status' => 'confirmed', 'hold' => null]);

        $this->verify($guest, $booking)
            ->assertStatus(409)
            ->assertJsonPath('code', 'room_gone_refunded')
            ->assertJsonPath('data.status', 'cancelled');

        $this->assertSame(['pi_test_' . $session], $this->gateway->refunds);
        $this->assertSame(1, Payment::where('status', 'refunded')->count());
        $this->assertSame(0, Payment::where('status', 'paid')->count());
        $this->assertSame('cancelled', $booking->fresh()->status);
        $this->assertSame('confirmed', $other->fresh()->status); // the other guest is untouched
    }

    public function test_a_guest_who_pays_late_is_refunded_when_the_room_is_in_maintenance(): void
    {
        [$guest, $booking] = $this->paidOnStripe();
        $this->travel(20)->minutes();
        Room::whereKey($booking->room_id)->update(['status' => Room::STATUS_MAINTENANCE]);

        $this->verify($guest, $booking)->assertStatus(409)->assertJsonPath('code', 'room_gone_refunded');

        $this->assertCount(1, $this->gateway->refunds);
    }

    public function test_a_payment_for_a_booking_cancelled_in_the_meantime_is_refunded(): void
    {
        [$guest, $booking] = $this->paidOnStripe();
        // Something else cancelled it (for example a night job) and left the payment page open.
        $booking->forceFill(['status' => 'cancelled'])->save();

        $this->verify($guest, $booking)->assertStatus(409)->assertJsonPath('code', 'booking_cancelled_refunded');

        $this->assertCount(1, $this->gateway->refunds);
        $this->assertSame(1, Payment::where('status', 'refunded')->count());
    }

    public function test_when_a_needed_refund_fails_the_guest_is_told_to_call_the_hotel(): void
    {
        [$guest, $booking] = $this->paidOnStripe();
        $this->travel(20)->minutes();
        $this->makeBooking($this->makeUser('customer'), ['status' => 'confirmed', 'hold' => null]);
        $this->gateway->failRefund = true;

        $response = $this->verify($guest, $booking)->assertStatus(502)->assertJsonPath('code', 'refund_failed');

        $this->assertStringContainsString($booking->code, $response->json('message'));
        $this->assertSame(0, Payment::where('status', 'paid')->count());
    }

    // ----------------------------------------------------------- demo mode

    public function test_demo_mode_opens_no_payment_page_even_with_a_stripe_key(): void
    {
        $this->demoMode();
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);

        $this->startOnline($guest, $booking)
            ->assertOk()
            ->assertJsonPath('mode', 'demo')
            ->assertJsonPath('checkout_url', null)
            ->assertJsonPath('data.amount_due', 25.5);

        $this->assertSame([], $this->gateway->created);
        $this->assertNull($booking->fresh()->checkout_session_id);
    }

    public function test_demo_mode_works_without_a_stripe_key(): void
    {
        $this->gateway->configured = false;
        $this->demoMode();
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);

        $this->startOnline($guest, $booking)->assertOk()->assertJsonPath('mode', 'demo');
    }

    public function test_with_demo_mode_off_and_a_key_it_is_a_real_payment_page(): void
    {
        $this->demoMode(false);
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);

        $this->startOnline($guest, $booking)->assertOk()->assertJsonPath('mode', 'online');
    }

    public function test_a_demo_payment_confirms_the_booking_with_the_discounted_amount(): void
    {
        $this->demoMode();
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);
        $this->startOnline($guest, $booking)->assertOk();

        $this->demoPay($guest, $booking)
            ->assertOk()
            ->assertJsonPath('data.status', 'confirmed')
            ->assertJsonPath('data.paid', true)
            ->assertJsonPath('data.payment_method', 'online');

        $payment = Payment::firstOrFail();
        $this->assertEquals(25.5, $payment->amount);
        $this->assertSame('online', $payment->method);
        $this->assertNull($payment->received_by);
        $this->assertStringStartsWith('demo-', $payment->reference);
        $this->assertNull($booking->fresh()->hold_expires_at);
    }

    public function test_pressing_the_demo_button_twice_does_not_pay_twice(): void
    {
        $this->demoMode();
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);
        $this->startOnline($guest, $booking)->assertOk();

        $this->demoPay($guest, $booking)->assertOk();
        $this->demoPay($guest, $booking)->assertOk();

        $this->assertSame(1, Payment::count());
    }

    public function test_the_demo_button_does_nothing_when_demo_mode_is_off(): void
    {
        $this->demoMode();
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);
        $this->startOnline($guest, $booking)->assertOk();

        $this->demoMode(false); // the admin switches it off

        $this->demoPay($guest, $booking)->assertStatus(403)->assertJsonPath('code', 'demo_mode_off');

        $this->assertSame(0, Payment::count());
        $this->assertSame('pending', $booking->fresh()->status);
    }

    public function test_a_guest_cannot_use_the_demo_button_in_normal_mode_to_skip_paying(): void
    {
        // Demo mode never was on: the endpoint must refuse, or anyone could book for free.
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);
        $this->startOnline($guest, $booking)->assertOk();

        $this->demoPay($guest, $booking)->assertStatus(403)->assertJsonPath('code', 'demo_mode_off');

        $this->assertSame(0, Payment::count());
    }

    public function test_the_demo_button_needs_online_payment_to_be_chosen_first(): void
    {
        $this->demoMode();
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);

        $this->demoPay($guest, $booking)->assertStatus(409)->assertJsonPath('code', 'no_payment_started');
        $this->assertSame(0, Payment::count());
    }

    public function test_the_demo_button_is_refused_after_the_time_ran_out_or_for_other_guests(): void
    {
        $this->demoMode();
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);
        $this->startOnline($guest, $booking)->assertOk();

        $this->demoPay($this->makeUser('customer'), $booking)->assertNotFound();

        $this->app['auth']->forgetGuards(); // nobody is logged in any more
        $this->postJson("/api/bookings/{$booking->id}/demo-pay")->assertUnauthorized();

        $this->travel(20)->minutes();
        $this->demoPay($guest, $booking)->assertStatus(409)->assertJsonPath('code', 'hold_expired');

        $this->assertSame(0, Payment::count());
    }

    public function test_the_demo_button_is_refused_for_a_cancelled_booking(): void
    {
        $this->demoMode();
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);
        $this->startOnline($guest, $booking)->assertOk();
        $booking->forceFill(['status' => 'cancelled'])->save();

        $this->demoPay($guest, $booking)->assertStatus(422)->assertJsonPath('code', 'not_pending');
    }

    // -------------------------------------------- changing your mind

    public function test_choosing_the_hotel_after_starting_online_drops_the_discount_and_closes_the_page(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);
        $this->startOnline($guest, $booking)->assertOk();
        $session = $this->gateway->lastSessionId();

        Sanctum::actingAs($guest);
        $this->postJson("/api/bookings/{$booking->id}/pay-at-hotel")
            ->assertOk()
            ->assertJsonPath('data.payment_choice', 'hotel')
            ->assertJsonPath('data.discount_percent', 0)
            ->assertJsonPath('data.amount_due', 30);

        $fresh = $booking->fresh();
        $this->assertNull($fresh->checkout_session_id);
        $this->assertNull($fresh->hold_expires_at);
        $this->assertSame([$session], $this->gateway->expired);
    }

    public function test_releasing_the_room_closes_the_payment_page(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);
        $this->startOnline($guest, $booking)->assertOk();
        $session = $this->gateway->lastSessionId();

        Sanctum::actingAs($guest);
        $this->postJson("/api/bookings/{$booking->id}/release")->assertOk();

        $this->assertSame([$session], $this->gateway->expired);
        $this->assertNull($booking->fresh()->checkout_session_id);
        $this->assertSame('cancelled', $booking->fresh()->status);
    }

    public function test_if_the_guest_paid_at_the_very_moment_they_cancelled_the_money_goes_back(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);
        $this->startOnline($guest, $booking)->assertOk();
        $session = $this->gateway->lastSessionId();

        // The page cannot be closed because it was just paid.
        $this->gateway->pay($session);
        $this->gateway->failExpire = true;

        Sanctum::actingAs($guest);
        $this->postJson("/api/bookings/{$booking->id}/release")->assertOk();

        $this->assertSame(['pi_test_' . $session], $this->gateway->refunds);
        $this->assertSame(1, Payment::where('status', 'refunded')->count());
        $this->assertEquals(25.5, Payment::firstOrFail()->amount);
        $this->assertSame('cancelled', $booking->fresh()->status);
    }

    public function test_staff_taking_payment_at_the_desk_closes_the_page_and_charges_the_full_price(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);
        $this->startOnline($guest, $booking)->assertOk();
        $session = $this->gateway->lastSessionId();

        $staff = $this->makeUser('staff');
        Sanctum::actingAs($staff);
        $this->postJson("/api/staff/bookings/{$booking->id}/payments", ['method' => 'cash'])
            ->assertCreated()
            ->assertJsonPath('data.payments.0.amount', 30)
            ->assertJsonPath('data.discount_percent', 0);

        $this->assertSame([$session], $this->gateway->expired);
        $fresh = $booking->fresh();
        $this->assertNull($fresh->checkout_session_id);
        $this->assertSame(0, $fresh->discount_percent);
    }

    // -------------------------------------------------------- what is shown

    public function test_staff_see_an_online_payment_without_a_receiving_staff_member(): void
    {
        [$guest, $booking] = $this->paidOnStripe();
        $this->verify($guest, $booking)->assertOk();

        Sanctum::actingAs($this->makeUser('staff'));
        $payment = $this->getJson("/api/staff/bookings/{$booking->id}")->assertOk()->json('data.payments.0');

        $this->assertSame('online', $payment['method']);
        $this->assertSame(25.5, $payment['amount']);
        $this->assertNull($payment['received_by']);
    }

    public function test_the_payment_response_never_contains_a_secret_key(): void
    {
        config(['services.stripe.secret' => 'sk_test_do_not_leak_me']);
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);

        $body = $this->startOnline($guest, $booking)->assertOk()->getContent();

        $this->assertStringNotContainsString('sk_test_', $body);
        $this->assertStringNotContainsString('do_not_leak_me', $body);
    }

    // ----------------------------------------------------- the return pages

    public function test_the_return_pages_show_a_message_without_a_login(): void
    {
        $this->get('/payment/success?booking=1')
            ->assertOk()
            ->assertSee('Payment received')
            ->assertSee('Angkor Stay app');

        $this->get('/payment/cancelled?booking=1')
            ->assertOk()
            ->assertSee('Payment cancelled')
            ->assertSee('Nothing was charged');
    }

    public function test_opening_the_success_page_by_hand_confirms_nothing(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);
        $this->startOnline($guest, $booking)->assertOk();

        $this->get('/payment/success?booking=' . $booking->id)->assertOk();

        $this->assertSame('pending', $booking->fresh()->status);
        $this->assertSame(0, Payment::count());
    }
}
