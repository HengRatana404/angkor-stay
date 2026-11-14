<?php

namespace Tests\Feature;

use App\Models\Booking;
use App\Models\Payment;
use App\Models\PaymentIntent;
use App\Models\User;
use App\Payments\KhqrPayload;
use App\Services\SettingsService;
use Carbon\Carbon;
use Database\Seeders\RoomSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\MakesBookings;
use Tests\Concerns\MakesUsers;
use Tests\TestCase;

/**
 * Paying online: a card or a QR code. The payments are simulated, but every payment is written to
 * the database and checked there before a booking is confirmed.
 */
class OnlinePaymentTest extends TestCase
{
    use MakesBookings;
    use MakesUsers;
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RoomSeeder::class);
    }

    /** A card of any kind. Not a real number: nothing is ever charged. */
    private function card(array $over = []): array
    {
        return array_merge([
            'number' => '4242 4242 4242 4242',
            'holder' => 'Sokha Demo',
            'expiry' => '11/26',
            'cvv' => '987',
        ], $over);
    }

    private function at(int $y, int $m, int $d, int $h = 10, int $min = 0): void
    {
        $this->travelTo(Carbon::create($y, $m, $d, $h, $min, 0, config('app.timezone')));
    }

    private function payCard(User $guest, Booking $booking, array $card = [])
    {
        Sanctum::actingAs($guest);

        return $this->postJson("/api/bookings/{$booking->id}/pay-card", $this->card($card));
    }

    private function startQr(User $guest, Booking $booking)
    {
        Sanctum::actingAs($guest);

        return $this->postJson("/api/bookings/{$booking->id}/pay-qr");
    }

    private function verify(User $guest, Booking $booking)
    {
        Sanctum::actingAs($guest);

        return $this->postJson("/api/bookings/{$booking->id}/verify-payment");
    }

    // ------------------------------------------------------------- card: the money side

    public function test_a_card_payment_confirms_the_booking_and_is_saved_in_the_database(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest); // 2 nights x $15 = $30, 15% off = $25.50

        $this->payCard($guest, $booking)
            ->assertOk()
            ->assertJsonPath('data.status', 'confirmed')
            ->assertJsonPath('data.paid', true)
            ->assertJsonPath('data.payment_method', 'online')
            ->assertJsonPath('data.payment_detail', 'Visa ending 4242')
            ->assertJsonPath('data.amount_due', 25.5)
            ->assertJsonPath('data.hold_seconds_left', null)
            ->assertJsonPath('payment.channel', 'card');

        $intent = PaymentIntent::firstOrFail();
        $this->assertSame('paid', $intent->status);
        $this->assertSame($booking->id, $intent->booking_id);
        $this->assertSame('4242', $intent->card_last4);
        $this->assertSame('Visa', $intent->card_brand);
        $this->assertEquals(25.5, $intent->amount);

        $payment = Payment::firstOrFail();
        $this->assertSame('online', $payment->method);
        $this->assertSame('paid', $payment->status);
        $this->assertNull($payment->received_by);
        $this->assertSame($intent->reference, $payment->reference);
        $this->assertEquals(25.5, $payment->amount);

        $booking->refresh();
        $this->assertSame(15, $booking->discount_percent);
        $this->assertEquals(4.5, $booking->discount_amount);
    }

    public function test_the_full_card_number_and_the_cvv_are_never_saved_or_sent_back(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);

        $response = $this->payCard($guest, $booking, ['number' => '5500 0000 0000 0004', 'cvv' => '9876'])->assertOk();

        $this->assertFalse(Schema::hasColumn('payment_intents', 'cvv'));
        $this->assertFalse(Schema::hasColumn('payment_intents', 'card_number'));

        $saved = json_encode([DB::table('payment_intents')->get(), DB::table('payments')->get(), DB::table('bookings')->get()]);
        $this->assertStringNotContainsString('5500000000000004', $saved);
        $this->assertStringContainsString('0004', $saved); // only the last 4

        $body = $response->getContent();
        $this->assertStringNotContainsString('5500000000000004', $body);
        $this->assertStringNotContainsString('9876', $body);
        $this->assertStringNotContainsString('cvv', strtolower($body));
    }

    public function test_any_card_number_works_it_does_not_have_to_pass_a_bank_check(): void
    {
        foreach (['1234 5678 9012 3456', '0000000000000', '9999-9999-9999-9999'] as $i => $number) {
            $guest = $this->makeUser('customer');
            $booking = $this->makeBooking($guest, ['in' => 10 + $i * 5]);

            $this->payCard($guest, $booking, ['number' => $number])->assertOk()->assertJsonPath('data.status', 'confirmed');
        }
    }

    public function test_the_brand_comes_from_the_first_digits(): void
    {
        $cases = [['4111111111111111', 'Visa'], ['5500000000000004', 'Mastercard'], ['2221000000000009', 'Mastercard'],
            ['378282246310005', 'Amex'], ['6011111111111117', 'Card']];

        $day = 5;
        foreach ($cases as [$number, $brand]) {
            $guest = $this->makeUser('customer');
            $booking = $this->makeBooking($guest, ['in' => $day += 3]);

            $this->payCard($guest, $booking, ['number' => $number])
                ->assertOk()
                ->assertJsonPath('data.payment_detail', $brand . ' ending ' . substr($number, -4));
        }
    }

    // ------------------------------------------------------------- card: the expiry date

    public function test_a_card_that_expires_11_26_is_good_all_through_november_2026(): void
    {
        $guest = $this->makeUser('customer');

        $this->at(2026, 11, 3);
        $first = $this->makeBooking($guest);
        $this->payCard($guest, $first)->assertOk();

        // The very last minute of November.
        $this->at(2026, 11, 30, 23, 59);
        $second = $this->makeBooking($guest, ['in' => 20]);
        $this->payCard($guest, $second)->assertOk()->assertJsonPath('data.status', 'confirmed');
    }

    public function test_a_card_that_expires_11_26_is_expired_from_1_december_2026(): void
    {
        $guest = $this->makeUser('customer');

        $this->at(2026, 12, 1, 0, 0);
        $booking = $this->makeBooking($guest);

        $this->payCard($guest, $booking)
            ->assertStatus(422)
            ->assertJsonValidationErrors('expiry')
            ->assertJsonPath('errors.expiry.0', 'This card has expired.');

        $this->assertSame('pending', $booking->fresh()->status);
        $this->assertSame(0, PaymentIntent::count());
        $this->assertSame(0, Payment::count());
    }

    public function test_last_month_is_expired_and_a_far_future_date_is_fine(): void
    {
        $guest = $this->makeUser('customer');
        $this->at(2026, 11, 3);
        $booking = $this->makeBooking($guest);

        $this->payCard($guest, $booking, ['expiry' => '10/26'])->assertStatus(422)->assertJsonPath('errors.expiry.0', 'This card has expired.');
        $this->payCard($guest, $booking, ['expiry' => '12/20'])->assertStatus(422)->assertJsonValidationErrors('expiry');
        $this->payCard($guest, $booking, ['expiry' => '12/99'])->assertOk();
    }

    public function test_the_expiry_date_must_be_written_mm_slash_yy(): void
    {
        $guest = $this->makeUser('customer');
        $this->at(2026, 11, 3);
        $booking = $this->makeBooking($guest);

        foreach (['13/26', '00/26', '1/26', '11/2026', '1126', 'abcd', ''] as $bad) {
            $this->payCard($guest, $booking, ['expiry' => $bad])->assertStatus(422)->assertJsonValidationErrors('expiry');
        }
    }

    public function test_the_other_card_fields_are_checked_for_their_shape(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);

        $this->payCard($guest, $booking, ['number' => '1234'])->assertStatus(422)->assertJsonValidationErrors('number');
        $this->payCard($guest, $booking, ['number' => 'abcd efgh ijkl'])->assertStatus(422)->assertJsonValidationErrors('number');
        $this->payCard($guest, $booking, ['holder' => ''])->assertStatus(422)->assertJsonValidationErrors('holder');
        $this->payCard($guest, $booking, ['cvv' => '12'])->assertStatus(422)->assertJsonValidationErrors('cvv');
        $this->payCard($guest, $booking, ['cvv' => '12a'])->assertStatus(422)->assertJsonValidationErrors('cvv');

        Sanctum::actingAs($guest);
        $this->postJson("/api/bookings/{$booking->id}/pay-card", [])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['number', 'holder', 'expiry', 'cvv']);

        $this->assertSame(0, Payment::count());
    }

    // ------------------------------------------------------------- card: who and when

    public function test_a_card_cannot_pay_twice(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);

        $this->payCard($guest, $booking)->assertOk();
        $this->payCard($guest, $booking)->assertStatus(422)->assertJsonPath('code', 'not_pending');

        $this->assertSame(1, Payment::count());
        $this->assertSame(1, PaymentIntent::count());
    }

    public function test_a_hold_that_ran_out_cannot_be_paid(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest, ['hold' => now()->subMinute()]);

        $this->payCard($guest, $booking)->assertStatus(409)->assertJsonPath('code', 'hold_expired');
        $this->assertSame(0, Payment::count());
    }

    public function test_a_cancelled_booking_cannot_be_paid(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest, ['status' => Booking::STATUS_CANCELLED, 'hold' => null]);

        $this->payCard($guest, $booking)->assertStatus(422)->assertJsonPath('code', 'not_pending');
        $this->startQr($guest, $booking)->assertStatus(422);
    }

    public function test_nobody_can_pay_for_someone_elses_booking_or_without_logging_in(): void
    {
        $booking = $this->makeBooking($this->makeUser('customer'));

        $this->payCard($this->makeUser('customer'), $booking)->assertNotFound();
        $this->startQr($this->makeUser('customer'), $booking)->assertNotFound();
        $this->verify($this->makeUser('customer'), $booking)->assertNotFound();

        $this->app['auth']->forgetGuards();
        $this->postJson("/api/bookings/{$booking->id}/pay-card", $this->card())->assertUnauthorized();
        $this->assertSame(0, Payment::count());
    }

    public function test_a_room_kept_for_the_hotel_can_still_be_paid_by_card_and_stays_kept_until_then(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeKeptBooking($guest);

        $this->payCard($guest, $booking)->assertOk()->assertJsonPath('data.status', 'confirmed');
    }

    // ------------------------------------------------------------- QR

    public function test_starting_a_qr_payment_gives_a_real_format_code_and_saves_it_in_the_database(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest, ['hold' => now()->addMinutes(1)]);

        $response = $this->startQr($guest, $booking)
            ->assertOk()
            ->assertJsonPath('data.payment_choice', 'online')
            ->assertJsonPath('data.status', 'pending')
            ->assertJsonPath('qr.amount', 25.5)
            ->assertJsonPath('qr.currency', 'USD');

        $intent = PaymentIntent::firstOrFail();
        $this->assertSame('pending', $intent->status);
        $this->assertSame('khqr', $intent->channel);
        $this->assertEquals(25.5, $intent->amount);
        $this->assertSame($intent->reference, $response->json('qr.reference'));
        $this->assertSame($intent->qr_payload, $response->json('qr.payload'));

        // The 1-minute hold was stretched to the 15-minute payment window.
        $this->assertGreaterThan(14 * 60, $response->json('data.hold_seconds_left'));
        $this->assertLessThanOrEqual(15 * 60, $response->json('qr.seconds_left'));

        // Nothing is paid yet.
        $this->assertSame(0, Payment::count());
        $this->assertSame('pending', $booking->fresh()->status);
    }

    public function test_the_qr_text_follows_the_khqr_layout(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);

        $payload = $this->startQr($guest, $booking)->json('qr.payload');
        $tags = KhqrPayload::parse($payload);

        $this->assertStringStartsWith('00020101021', $payload);
        $this->assertTrue(KhqrPayload::isValid($payload), 'the CRC at the end must match');
        $this->assertSame('01', $tags['00']);
        $this->assertSame('12', $tags['01']);
        $this->assertSame('840', $tags['53']);           // US dollar
        $this->assertSame('25.50', $tags['54']);         // the discounted price
        $this->assertSame('KH', $tags['58']);
        $this->assertSame('Angkor Stay', $tags['59']);
        $this->assertSame('7011', $tags['52']);
        $this->assertSame(PaymentIntent::first()->reference, KhqrPayload::parse($tags['62'])['01']); // bill number
        $this->assertStringContainsString(KhqrPayload::DEMO_ACCOUNT, $tags['29']);                  // a demo account
    }

    public function test_a_changed_qr_text_fails_the_crc_check(): void
    {
        $payload = KhqrPayload::build('AS1-TEST1234', 25.5, now()->addMinutes(15));

        $this->assertTrue(KhqrPayload::isValid($payload));
        $this->assertFalse(KhqrPayload::isValid(str_replace('25.50', '2.50', $payload)));
        $this->assertFalse(KhqrPayload::isValid(substr($payload, 0, -1) . 'X'));
        $this->assertFalse(KhqrPayload::isValid('hello'));
    }

    public function test_pressing_i_have_paid_without_a_qr_payment_is_refused(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);

        $this->verify($guest, $booking)->assertStatus(409)->assertJsonPath('code', 'no_payment_started');
        $this->assertSame(0, Payment::count());
    }

    public function test_verifying_a_qr_payment_finds_it_in_the_database_and_confirms_the_booking(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);
        $reference = $this->startQr($guest, $booking)->json('qr.reference');

        $this->verify($guest, $booking)
            ->assertOk()
            ->assertJsonPath('data.status', 'confirmed')
            ->assertJsonPath('data.paid', true)
            ->assertJsonPath('data.payment_detail', 'KHQR');

        $this->assertSame('paid', PaymentIntent::where('reference', $reference)->value('status'));
        $payment = Payment::firstOrFail();
        $this->assertSame($reference, $payment->reference);
        $this->assertSame('online', $payment->method);
        $this->assertEquals(25.5, $payment->amount);
    }

    public function test_pressing_i_have_paid_twice_does_not_charge_twice(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);
        $this->startQr($guest, $booking);

        $this->verify($guest, $booking)->assertOk();
        $this->verify($guest, $booking)->assertOk()->assertJsonPath('data.status', 'confirmed');

        $this->assertSame(1, Payment::count());
    }

    public function test_starting_a_new_qr_closes_the_old_one(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);

        $old = $this->startQr($guest, $booking)->json('qr.reference');
        $new = $this->startQr($guest, $booking)->json('qr.reference');

        $this->assertNotSame($old, $new);
        $this->assertSame('cancelled', PaymentIntent::where('reference', $old)->value('status'));
        $this->assertSame('pending', PaymentIntent::where('reference', $new)->value('status'));

        $this->verify($guest, $booking)->assertOk();
        $this->assertSame($new, Payment::firstOrFail()->reference);
    }

    public function test_a_qr_payment_that_nobody_finished_in_time_is_refused_and_later_marked_expired(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeKeptBooking($guest); // no hold timer, so only the QR clock runs
        $this->startQr($guest, $booking);

        $this->travel(16)->minutes();

        $this->verify($guest, $booking)->assertStatus(409)->assertJsonPath('code', 'payment_expired');
        $this->assertSame(0, Payment::count());
        $this->assertSame('pending', $booking->fresh()->status);

        $this->artisan('hotel:clean-up')->assertSuccessful();
        $this->assertSame('expired', PaymentIntent::firstOrFail()->status);

        // After the tidy-up the message is the same.
        $this->verify($guest, $booking)->assertStatus(409)->assertJsonPath('code', 'payment_expired');
    }

    public function test_a_qr_started_on_a_running_hold_runs_out_with_the_hold(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);
        $this->startQr($guest, $booking);

        $this->travel(16)->minutes();

        $this->verify($guest, $booking)->assertStatus(409);
        $this->assertSame(0, Payment::count());
    }

    public function test_a_payment_whose_amount_was_changed_in_the_database_is_not_accepted(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);
        $this->startQr($guest, $booking);

        PaymentIntent::query()->update(['amount' => 1.00]); // someone tampers with the row

        $this->verify($guest, $booking)->assertStatus(422)->assertJsonPath('code', 'payment_mismatch');
        $this->assertSame(0, Payment::count());
        $this->assertSame('pending', $booking->fresh()->status);
    }

    public function test_a_payment_that_belongs_to_another_booking_is_not_accepted(): void
    {
        $guest = $this->makeUser('customer');
        $mine = $this->makeBooking($guest);
        $other = $this->makeBooking($guest, ['in' => 30]);
        $this->startQr($guest, $mine);

        PaymentIntent::query()->update(['booking_id' => $other->id]);

        $this->verify($guest, $mine)->assertStatus(409); // it is not even found for this booking
        $this->assertSame(0, Payment::count());
    }

    // ------------------------------------------------------------- choosing another way

    public function test_choosing_the_hotel_after_starting_a_qr_drops_the_discount_and_closes_the_payment(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);
        $this->startQr($guest, $booking);
        $this->assertSame(15, $booking->fresh()->discount_percent);

        Sanctum::actingAs($guest);
        $this->postJson("/api/bookings/{$booking->id}/pay-at-hotel")->assertOk()->assertJsonPath('data.amount_due', 30);

        $this->assertSame('cancelled', PaymentIntent::firstOrFail()->status);
        $this->assertSame(0, $booking->fresh()->discount_percent);

        $this->verify($guest, $booking)->assertStatus(409); // the old QR can never be paid now
        $this->assertSame(0, Payment::count());
    }

    public function test_releasing_the_room_closes_the_open_payment(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);
        $this->startQr($guest, $booking);

        Sanctum::actingAs($guest);
        $this->postJson("/api/bookings/{$booking->id}/release")->assertOk();

        $this->assertSame('cancelled', PaymentIntent::firstOrFail()->status);
        $this->verify($guest, $booking)->assertStatus(409);
    }

    public function test_staff_taking_payment_at_the_desk_closes_the_open_qr_and_charges_the_full_price(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeKeptBooking($guest);
        $this->startQr($guest, $booking);

        Sanctum::actingAs($this->makeUser('staff'));
        $this->postJson("/api/staff/bookings/{$booking->id}/payments", ['method' => 'cash'])
            ->assertStatus(201)
            ->assertJsonPath('data.status', 'confirmed');

        $this->assertSame('cancelled', PaymentIntent::firstOrFail()->status);
        $payment = Payment::firstOrFail();
        $this->assertSame('cash', $payment->method);
        $this->assertEquals(30, $payment->amount); // no online discount at the desk
    }

    public function test_staff_see_an_online_payment_without_a_receiving_staff_member(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);
        $this->payCard($guest, $booking)->assertOk();

        Sanctum::actingAs($this->makeUser('staff'));
        $this->getJson("/api/staff/bookings/{$booking->id}")
            ->assertOk()
            ->assertJsonPath('data.payments.0.method', 'online')
            ->assertJsonPath('data.payments.0.received_by', null)
            ->assertJsonPath('data.discount_percent', 15)
            ->assertJsonPath('data.amount_due', 25.5);
    }

    // ------------------------------------------------------------- refunds (simulated, in the database)

    public function test_cancelling_a_card_booking_marks_the_payment_and_the_intent_refunded(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);
        $this->payCard($guest, $booking)->assertOk();

        Sanctum::actingAs($guest);
        $this->postJson("/api/bookings/{$booking->id}/cancel")
            ->assertOk()
            ->assertJsonPath('data.status', 'cancelled')
            ->assertJsonPath('data.refunded_amount', 25.5);

        $this->assertSame('refunded', Payment::firstOrFail()->status);
        $this->assertSame('refunded', PaymentIntent::firstOrFail()->status);
    }

    // ------------------------------------------------------------- settings stay public

    public function test_the_discount_and_times_are_public_and_follow_the_admin(): void
    {
        $this->getJson('/api/settings/public')
            ->assertOk()
            ->assertExactJson(['data' => [
                'online_discount_percent' => 15,
                'check_in_time' => '14:00',
                'check_out_time' => '12:00',
            ]]);

        app(SettingsService::class)->update(['online_discount_percent' => 25, 'check_in_time' => '13:30']);

        $this->getJson('/api/settings/public')
            ->assertOk()
            ->assertJsonPath('data.online_discount_percent', 25)
            ->assertJsonPath('data.check_in_time', '13:30');
    }

    public function test_a_changed_discount_is_used_for_the_next_payment_only(): void
    {
        $guest = $this->makeUser('customer');
        $first = $this->makeBooking($guest);
        $this->payCard($guest, $first)->assertOk();

        app(SettingsService::class)->update(['online_discount_percent' => 50]);

        $second = $this->makeBooking($guest, ['in' => 20]);
        $this->payCard($guest, $second)->assertOk()->assertJsonPath('data.amount_due', 15);

        $this->assertEquals(25.5, $first->fresh()->amount_due); // the old booking keeps its discount
    }

    public function test_the_old_gateway_and_demo_routes_are_gone(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);
        Sanctum::actingAs($guest);

        $this->postJson("/api/bookings/{$booking->id}/pay-online")->assertNotFound();
        $this->postJson("/api/bookings/{$booking->id}/demo-pay")->assertNotFound();
        $this->get('/payment/success')->assertNotFound();
        $this->assertFalse(Schema::hasColumn('bookings', 'checkout_session_id'));
        $this->assertArrayNotHasKey('demo_payment_mode', app(SettingsService::class)->all());
    }
}
