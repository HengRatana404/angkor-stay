<?php

namespace Tests\Feature;

use App\Models\Booking;
use App\Models\Room;
use App\Payments\GatewayException;
use App\Payments\StripeGateway;
use Database\Seeders\RoomSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Tests\Concerns\MakesBookings;
use Tests\Concerns\MakesUsers;
use Tests\TestCase;

/** The real StripeGateway, with Stripe's answers faked: does it ask Stripe the right way? */
class StripeGatewayTest extends TestCase
{
    use MakesBookings;
    use MakesUsers;
    use RefreshDatabase;

    private const KEY = 'sk_test_abcdefghijklmnop';

    private function gateway(?string $key = self::KEY): StripeGateway
    {
        return new StripeGateway($key);
    }

    private function booking(): Booking
    {
        $this->seed(RoomSeeder::class);

        return $this->makeBooking($this->makeUser('customer'), ['room' => Room::where('room_number', '101')->first()]);
    }

    public function test_only_test_keys_count_as_set_up(): void
    {
        $this->assertTrue($this->gateway(self::KEY)->isConfigured());

        foreach ([null, '', 'sk_live_abcdefghijklmnop', 'pk_test_abcdefghijklmnop', 'sk_test_', 'sk_test_short', 'nonsense'] as $bad) {
            $this->assertFalse($this->gateway($bad)->isConfigured(), var_export($bad, true));
        }
    }

    public function test_it_never_calls_stripe_without_a_test_key(): void
    {
        Http::fake();

        foreach ([null, 'sk_live_abcdefghijklmnop'] as $key) {
            try {
                $this->gateway($key)->retrieveCheckout('cs_test_1');
                $this->fail('A call without a test key must not happen.');
            } catch (GatewayException $e) {
                $this->assertStringNotContainsString('sk_live', $e->getMessage());
            }
        }

        Http::assertNothingSent();
    }

    public function test_it_asks_stripe_for_a_payment_page_the_right_way(): void
    {
        Http::fake(['api.stripe.com/*' => Http::response(['id' => 'cs_test_abc', 'url' => 'https://checkout.stripe.com/c/pay/cs_test_abc'])]);
        $booking = $this->booking();

        $page = $this->gateway()->createCheckout($booking, 2550, 'http://hotel.test/payment/success?booking=1', 'http://hotel.test/payment/cancelled?booking=1');

        $this->assertSame(['id' => 'cs_test_abc', 'url' => 'https://checkout.stripe.com/c/pay/cs_test_abc'], $page);

        Http::assertSent(function (Request $request) use ($booking) {
            $data = $request->data();

            return $request->method() === 'POST'
                && $request->url() === 'https://api.stripe.com/v1/checkout/sessions'
                && $request->hasHeader('Authorization', 'Basic ' . base64_encode(self::KEY . ':'))
                && $data['mode'] === 'payment'
                && $data['success_url'] === 'http://hotel.test/payment/success?booking=1'
                && $data['cancel_url'] === 'http://hotel.test/payment/cancelled?booking=1'
                && $data['client_reference_id'] === $booking->code
                && (string) $data['metadata']['booking_id'] === (string) $booking->id
                && $data['line_items'][0]['quantity'] == 1
                && $data['line_items'][0]['price_data']['currency'] === 'usd'
                && $data['line_items'][0]['price_data']['unit_amount'] == 2550
                && str_contains($data['line_items'][0]['price_data']['product_data']['name'], 'Single room')
                && str_contains($data['line_items'][0]['price_data']['product_data']['name'], $booking->code)
                && (int) $data['expires_at'] >= now()->addMinutes(30)->timestamp; // Stripe's minimum is 30 minutes
        });
    }

    public function test_it_reads_a_paid_page(): void
    {
        Http::fake(['api.stripe.com/v1/checkout/sessions/cs_test_abc' => Http::response([
            'id' => 'cs_test_abc',
            'payment_status' => 'paid',
            'status' => 'complete',
            'amount_total' => 2550,
            'currency' => 'USD',
            'payment_intent' => 'pi_123',
            'metadata' => ['booking_id' => '42'],
        ])]);

        $info = $this->gateway()->retrieveCheckout('cs_test_abc');

        $this->assertSame([
            'paid' => true,
            'expired' => false,
            'amount_cents' => 2550,
            'currency' => 'usd',
            'booking_id' => 42,
            'payment_reference' => 'pi_123',
        ], $info);

        Http::assertSent(fn (Request $r) => $r->method() === 'GET'
            && $r->url() === 'https://api.stripe.com/v1/checkout/sessions/cs_test_abc'
            && $r->hasHeader('Authorization', 'Basic ' . base64_encode(self::KEY . ':')));
    }

    public function test_it_reads_unpaid_and_expired_pages(): void
    {
        Http::fake([
            'api.stripe.com/v1/checkout/sessions/cs_open' => Http::response(['payment_status' => 'unpaid', 'status' => 'open', 'amount_total' => 100, 'currency' => 'usd', 'payment_intent' => null, 'metadata' => []]),
            'api.stripe.com/v1/checkout/sessions/cs_old' => Http::response(['payment_status' => 'unpaid', 'status' => 'expired', 'amount_total' => 100, 'currency' => 'usd', 'metadata' => []]),
        ]);

        $open = $this->gateway()->retrieveCheckout('cs_open');
        $old = $this->gateway()->retrieveCheckout('cs_old');

        $this->assertFalse($open['paid']);
        $this->assertFalse($open['expired']);
        $this->assertNull($open['booking_id']);
        $this->assertNull($open['payment_reference']);
        $this->assertFalse($old['paid']);
        $this->assertTrue($old['expired']);
    }

    public function test_it_asks_for_a_refund_the_right_way(): void
    {
        Http::fake(['api.stripe.com/*' => Http::response(['id' => 're_123'])]);

        $this->assertSame('re_123', $this->gateway()->refund('pi_123'));

        Http::assertSent(fn (Request $r) => $r->method() === 'POST'
            && $r->url() === 'https://api.stripe.com/v1/refunds'
            && $r->data() === ['payment_intent' => 'pi_123']);
    }

    public function test_it_closes_a_page_the_right_way(): void
    {
        Http::fake(['api.stripe.com/*' => Http::response(['id' => 'cs_test_abc', 'status' => 'expired'])]);

        $this->gateway()->expireCheckout('cs_test_abc');

        Http::assertSent(fn (Request $r) => $r->method() === 'POST'
            && $r->url() === 'https://api.stripe.com/v1/checkout/sessions/cs_test_abc/expire');
    }

    public function test_a_refusal_from_stripe_becomes_an_exception_without_the_key(): void
    {
        Http::fake(['api.stripe.com/*' => Http::response(['error' => ['message' => 'Invalid API Key provided']], 401)]);

        try {
            $this->gateway()->retrieveCheckout('cs_test_abc');
            $this->fail('Expected an exception.');
        } catch (GatewayException $e) {
            $this->assertSame('Invalid API Key provided', $e->getMessage());
            $this->assertStringNotContainsString(self::KEY, $e->getMessage());
        }
    }

    public function test_a_page_answer_without_a_link_is_an_error(): void
    {
        Http::fake(['api.stripe.com/*' => Http::response(['id' => 'cs_test_abc'])]);

        $this->expectException(GatewayException::class);
        $this->gateway()->createCheckout($this->booking(), 2550, 'http://x/ok', 'http://x/no');
    }

    public function test_a_refund_answer_without_an_id_is_an_error(): void
    {
        Http::fake(['api.stripe.com/*' => Http::response([])]);

        $this->expectException(GatewayException::class);
        $this->gateway()->refund('pi_123');
    }

    public function test_a_network_failure_becomes_an_exception(): void
    {
        Http::fake(fn () => throw new ConnectionException('timeout'));

        $this->expectException(GatewayException::class);
        $this->gateway()->retrieveCheckout('cs_test_abc');
    }
}
