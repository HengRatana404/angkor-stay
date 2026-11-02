<?php

namespace Tests\Feature;

use App\Models\Booking;
use App\Models\Payment;
use App\Models\Room;
use App\Payments\GatewayException;
use App\Payments\PaymentGateway;
use App\Payments\PaywayGateway;
use App\Payments\StripeGateway;
use Database\Seeders\RoomSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\MakesBookings;
use Tests\Concerns\MakesUsers;
use Tests\TestCase;

/** The real PaywayGateway with PayWay's answers faked: does it ask PayWay the right way? */
class PaywayGatewayTest extends TestCase
{
    use MakesBookings;
    use MakesUsers;
    use RefreshDatabase;

    private const KEY = 'TESTKEY0123456789ABCDEF';
    private const MERCHANT = 'ec000001';
    private const BASE = 'https://checkout-sandbox.payway.com.kh';
    private const CHECK_URL = self::BASE . '/api/payment-gateway/v1/payments/check-transaction-2';
    private const CLOSE_URL = self::BASE . '/api/payment-gateway/v1/payments/close-transaction';
    private const REFUND_URL = self::BASE . '/api/merchant-portal/merchant-access/online-transaction/refund';

    private ?string $pemPath = null;
    private $privateKey = null;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RoomSeeder::class);

        config([
            'services.payway.merchant_id' => self::MERCHANT,
            'services.payway.api_key' => self::KEY,
            'services.payway.base_url' => self::BASE,
            'services.payway.rsa_public_key_path' => null,
        ]);
    }

    protected function tearDown(): void
    {
        if ($this->pemPath && is_file($this->pemPath)) {
            @unlink($this->pemPath);
        }
        parent::tearDown();
    }

    private function gateway(?string $merchant = self::MERCHANT, ?string $key = self::KEY, string $base = self::BASE): PaywayGateway
    {
        return new PaywayGateway($merchant, $key, $base, $this->pemPath);
    }

    private function sign(string $glued): string
    {
        return base64_encode(hash_hmac('sha512', $glued, self::KEY, true));
    }

    private function booking(string $guestName = 'Sok Dara'): Booking
    {
        $guest = $this->makeUser('customer', ['name' => $guestName]);

        return $this->makeBooking($guest, ['room' => Room::where('room_number', '101')->first()]);
    }

    private function approved(float $amount = 12.75): array
    {
        return [
            'data' => ['payment_status_code' => 0, 'payment_status' => 'APPROVED', 'total_amount' => $amount, 'original_amount' => $amount],
            'status' => ['code' => '00', 'message' => 'Success!'],
        ];
    }

    /** Makes a pair of RSA keys like PayWay's (1024 bit) and saves the public one in a file. */
    private function makeRsaKeys(): void
    {
        // Windows PHP needs to be told where its OpenSSL settings file is.
        $settings = array_filter([
            getenv('OPENSSL_CONF') ?: null,
            dirname(PHP_BINARY) . '/extras/ssl/openssl.cnf',
            'C:/Program Files/Git/usr/ssl/openssl.cnf',
        ], fn ($path) => $path && is_file($path));

        $options = ['private_key_bits' => 1024, 'private_key_type' => OPENSSL_KEYTYPE_RSA];
        $this->privateKey = openssl_pkey_new($options);
        foreach ($settings as $path) {
            if ($this->privateKey !== false) {
                break;
            }
            $this->privateKey = openssl_pkey_new($options + ['config' => $path]);
        }

        if ($this->privateKey === false) {
            $this->markTestSkipped('This PHP cannot make RSA keys (no OpenSSL settings file found).');
        }

        $public = openssl_pkey_get_details($this->privateKey)['key'];
        $this->pemPath = tempnam(sys_get_temp_dir(), 'payway_rsa_');
        file_put_contents($this->pemPath, $public);
    }

    // ------------------------------------------------------------ set up or not

    public function test_it_counts_as_set_up_only_for_a_sandbox_address_with_both_values(): void
    {
        $this->assertTrue($this->gateway()->isConfigured());

        $this->assertFalse($this->gateway(null)->isConfigured());
        $this->assertFalse($this->gateway('')->isConfigured());
        $this->assertFalse($this->gateway(self::MERCHANT, null)->isConfigured());
        $this->assertFalse($this->gateway(self::MERCHANT, '')->isConfigured());
        // A live address is refused, so real money can never move by accident.
        $this->assertFalse($this->gateway(self::MERCHANT, self::KEY, 'https://checkout.payway.com.kh')->isConfigured());
        $this->assertFalse($this->gateway(self::MERCHANT, self::KEY, 'https://example.com')->isConfigured());
    }

    public function test_it_never_calls_payway_when_it_is_not_set_up(): void
    {
        Http::fake();

        foreach ([$this->gateway(null), $this->gateway(self::MERCHANT, self::KEY, 'https://checkout.payway.com.kh')] as $gateway) {
            foreach ([
                fn () => $gateway->retrieveCheckout('AS1-ABCDEFGH'),
                fn () => $gateway->expireCheckout('AS1-ABCDEFGH'),
                fn () => $gateway->refund('AS1-ABCDEFGH'),
                fn () => $gateway->createCheckout($this->booking(), 1275, 'http://x/ok', 'http://x/no'),
            ] as $call) {
                try {
                    $call();
                    $this->fail('A call to a gateway that is not set up must not happen.');
                } catch (GatewayException $e) {
                    $this->assertStringNotContainsString(self::KEY, $e->getMessage());
                }
            }
        }

        Http::assertNothingSent();
    }

    public function test_the_app_uses_payway_when_it_is_set_up_and_stripe_otherwise(): void
    {
        $this->assertInstanceOf(PaywayGateway::class, app(PaymentGateway::class));

        config(['services.payway.merchant_id' => null]);
        $this->assertInstanceOf(StripeGateway::class, app(PaymentGateway::class));
    }

    public function test_it_names_itself_and_tells_the_guest_which_test_card_to_use(): void
    {
        $gateway = $this->gateway();

        $this->assertSame('payway', $gateway->name());
        $this->assertStringContainsString('5156 8399 3770 6777', $gateway->checkoutHint());
        $this->assertStringContainsString('01/30', $gateway->checkoutHint());
        $this->assertStringContainsString('993', $gateway->checkoutHint());
    }

    // ---------------------------------------------------------- opening a page

    public function test_opening_a_page_gives_a_short_transaction_id_and_a_page_on_our_server(): void
    {
        Http::fake();
        $booking = $this->booking();

        $page = $this->gateway()->createCheckout($booking, 1275, 'http://hotel.test:8000/payment/success?booking=1', 'http://hotel.test:8000/payment/cancelled?booking=1');

        $this->assertMatchesRegularExpression('/^AS' . $booking->id . '-[A-Z0-9]+$/', $page['id']);
        $this->assertLessThanOrEqual(20, strlen($page['id'])); // PayWay allows 20 characters
        $this->assertSame('http://hotel.test:8000/payment/payway/' . $page['id'], $page['url']);

        // Making the page asks PayWay nothing. The guest's browser does that later.
        Http::assertNothingSent();
    }

    public function test_every_page_gets_its_own_transaction_id(): void
    {
        $booking = $this->booking();
        $ids = [];
        for ($i = 0; $i < 20; $i++) {
            $ids[] = $this->gateway()->createCheckout($booking, 1275, 'http://x/ok', 'http://x/no')['id'];
        }

        $this->assertCount(20, array_unique($ids));
    }

    public function test_a_long_booking_number_still_fits_in_20_characters(): void
    {
        $booking = $this->booking();
        $booking->id = 987654;

        $id = $this->gateway()->createCheckout($booking, 1275, 'http://x/ok', 'http://x/no')['id'];

        $this->assertLessThanOrEqual(20, strlen($id));
        $this->assertStringStartsWith('AS987654-', $id);
    }

    public function test_the_page_form_is_signed_the_way_payway_wants(): void
    {
        $booking = $this->booking('Sok Dara');
        $gateway = $this->gateway();
        $page = $gateway->createCheckout($booking, 1275, 'http://hotel.test/payment/success?booking=1', 'http://hotel.test/payment/cancelled?booking=1');

        $form = $gateway->pageFor($page['id']);
        $f = $form['fields'];

        $this->assertSame(self::BASE . '/api/payment-gateway/v1/payments/purchase', $form['action']);

        $this->assertSame(self::MERCHANT, $f['merchant_id']);
        $this->assertSame($page['id'], $f['tran_id']);
        $this->assertSame('12.75', $f['amount']);
        $this->assertSame('purchase', $f['type']);
        $this->assertSame('USD', $f['currency']);
        $this->assertSame('30', $f['lifetime']);
        $this->assertSame('http://hotel.test/payment/success?booking=1', $f['continue_success_url']);
        $this->assertSame('http://hotel.test/payment/cancelled?booking=1', $f['cancel_url']);
        $this->assertSame('Sok', $f['firstname']);
        $this->assertSame('Dara', $f['lastname']);
        $this->assertSame($booking->user->email, $f['email']);
        $this->assertMatchesRegularExpression('/^\d{14}$/', $f['req_time']);
        $this->assertEqualsWithDelta(time(), \DateTime::createFromFormat('YmdHis', $f['req_time'], new \DateTimeZone('UTC'))->getTimestamp(), 60);

        $items = json_decode(base64_decode($f['items']), true);
        $this->assertSame(1, $items[0]['quantity']);
        $this->assertEquals(12.75, $items[0]['price']);
        $this->assertStringContainsString($booking->code, $items[0]['name']);

        // The hash: the posted values glued together in PayWay's order (empty for the ones we do not send).
        $order = ['req_time', 'merchant_id', 'tran_id', 'amount', 'items', 'shipping', 'firstname', 'lastname', 'email',
            'phone', 'type', 'payment_option', 'return_url', 'cancel_url', 'continue_success_url', 'return_deeplink',
            'currency', 'custom_fields', 'return_params', 'payout', 'lifetime', 'additional_params',
            'google_pay_token', 'skip_success_page'];
        $glued = '';
        foreach ($order as $name) {
            $glued .= $f[$name] ?? '';
        }
        $this->assertSame($this->sign($glued), $f['hash']);

        // These two are posted but are NOT part of the hash: they ask for the normal
        // payment page instead of the QR service.
        $this->assertSame('0', $f['payment_gate']);
        $this->assertSame('hosted_view', $f['view_type']);

        // Only fields that were really used are posted, and the secret key is never one of them.
        $this->assertArrayNotHasKey('phone', $f);
        $this->assertStringNotContainsString(self::KEY, json_encode($f));
    }

    public function test_the_form_is_signed_fresh_each_time_it_is_opened(): void
    {
        $gateway = $this->gateway();
        $page = $gateway->createCheckout($this->booking(), 1275, 'http://x/ok', 'http://x/no');

        $this->travel(10)->minutes();
        $later = $gateway->pageFor($page['id']);

        $this->assertEqualsWithDelta(time(), \DateTime::createFromFormat('YmdHis', $later['fields']['req_time'], new \DateTimeZone('UTC'))->getTimestamp(), 60);
    }

    public function test_names_are_cleaned_because_payway_refuses_numbers_and_symbols(): void
    {
        $gateway = $this->gateway();

        $f = $gateway->pageFor($gateway->createCheckout($this->booking('Jean-Luc 99 Picard'), 1275, 'http://x/ok', 'http://x/no')['id'])['fields'];
        $this->assertSame('JeanLuc', $f['firstname']);
        $this->assertSame('Picard', $f['lastname']);

        $f = $gateway->pageFor($gateway->createCheckout($this->booking('Madonna'), 1275, 'http://x/ok', 'http://x/no')['id'])['fields'];
        $this->assertSame('Madonna', $f['firstname']);
        $this->assertArrayNotHasKey('lastname', $f);

        $f = $gateway->pageFor($gateway->createCheckout($this->booking('12345 !!'), 1275, 'http://x/ok', 'http://x/no')['id'])['fields'];
        $this->assertArrayNotHasKey('firstname', $f);
        $this->assertArrayNotHasKey('lastname', $f);
        $this->assertArrayHasKey('hash', $f); // still a valid, signed form
    }

    public function test_an_unknown_page_has_no_form(): void
    {
        $this->assertNull($this->gateway()->pageFor('AS1-NOTREAL1'));
    }

    // ----------------------------------------------------------------- checking

    public function test_checking_asks_payway_the_right_way(): void
    {
        Http::fake([self::CHECK_URL => Http::response($this->approved())]);

        $this->gateway()->retrieveCheckout('AS12-ABCDEFGH');

        Http::assertSent(function (Request $request) {
            $body = $request->data();

            return $request->method() === 'POST'
                && $request->url() === self::CHECK_URL
                && $request->hasHeader('Accept', 'application/json')
                && str_contains($request->header('Content-Type')[0] ?? '', 'application/json')
                && $body['merchant_id'] === self::MERCHANT
                && $body['tran_id'] === 'AS12-ABCDEFGH'
                && preg_match('/^\d{14}$/', $body['req_time']) === 1
                && $body['hash'] === $this->sign($body['req_time'] . self::MERCHANT . 'AS12-ABCDEFGH');
        });
    }

    public function test_an_approved_payment_is_read_as_paid_with_the_amount_in_cents(): void
    {
        Http::fake([self::CHECK_URL => Http::response($this->approved(12.75))]);

        $info = $this->gateway()->retrieveCheckout('AS12-ABCDEFGH');

        $this->assertSame([
            'paid' => true,
            'expired' => false,
            'amount_cents' => 1275,
            'currency' => 'usd',
            'booking_id' => 12,
            'payment_reference' => 'AS12-ABCDEFGH',
        ], $info);
    }

    public function test_amounts_are_turned_into_cents_without_float_mistakes(): void
    {
        $cases = [[8.10, 810], [0.1, 10], [12.75, 1275], [4.35, 435], [19.99, 1999], [1.15, 115]];

        // One fake that gives these answers one after the other.
        $answers = Http::sequence();
        foreach ($cases as [$amount]) {
            $answers->push($this->approved($amount));
        }
        Http::fake([self::CHECK_URL => $answers]);

        foreach ($cases as [$amount, $cents]) {
            $this->assertSame($cents, $this->gateway()->retrieveCheckout('AS1-ABCDEFGH')['amount_cents'], (string) $amount);
        }
    }

    public function test_every_payment_status_is_read_correctly(): void
    {
        $cases = [
            // status        paid   expired
            'APPROVED' => [true, false],
            'PENDING' => [false, false],
            'DECLINED' => [false, false],   // the guest may try another card
            'CANCELLED' => [false, true],   // closed by us
            'REFUNDED' => [false, true],    // money already went back
            'PRE-AUTH' => [false, false],   // we never use pre-auth, so it is not a paid purchase
        ];

        // One fake that gives these answers one after the other.
        $answers = Http::sequence();
        foreach (array_keys($cases) as $status) {
            $answers->push([
                'data' => ['payment_status' => $status, 'total_amount' => 12.75],
                'status' => ['code' => '00', 'message' => 'Success!'],
            ]);
        }
        Http::fake([self::CHECK_URL => $answers]);

        foreach ($cases as $status => [$paid, $expired]) {
            $info = $this->gateway()->retrieveCheckout('AS1-ABCDEFGH');

            $this->assertSame($paid, $info['paid'], "paid for {$status}");
            $this->assertSame($expired, $info['expired'], "expired for {$status}");
        }
    }

    public function test_a_transaction_payway_has_not_seen_yet_is_just_not_paid(): void
    {
        Http::fake([self::CHECK_URL => Http::response(['status' => ['code' => 6, 'message' => 'tran_id not found', 'tran_id' => 'AS1-ABCDEFGH']])]);

        $info = $this->gateway()->retrieveCheckout('AS1-ABCDEFGH');

        $this->assertFalse($info['paid']);
        $this->assertFalse($info['expired']);
        $this->assertSame(0, $info['amount_cents']);
        $this->assertSame(1, $info['booking_id']);
    }

    public function test_the_booking_number_comes_from_the_transaction_id(): void
    {
        Http::fake([self::CHECK_URL => Http::response($this->approved())]);

        $this->assertSame(345, $this->gateway()->retrieveCheckout('AS345-XYZXYZXY')['booking_id']);
        $this->assertNull($this->gateway()->retrieveCheckout('SOMETHING-ELSE')['booking_id']);
    }

    public function test_a_wrong_hash_or_other_payway_error_becomes_an_exception_without_the_key(): void
    {
        Http::fake([self::CHECK_URL => Http::response(['status' => ['code' => 5, 'message' => 'Invalid hash']], 403)]);

        try {
            $this->gateway()->retrieveCheckout('AS1-ABCDEFGH');
            $this->fail('Expected an exception.');
        } catch (GatewayException $e) {
            $this->assertStringContainsString('Invalid hash', $e->getMessage());
            $this->assertStringContainsString('code 5', $e->getMessage());
            $this->assertStringNotContainsString(self::KEY, $e->getMessage());
        }
    }

    public function test_an_answer_that_is_not_what_we_expect_is_an_error(): void
    {
        Http::fake([self::CHECK_URL => Http::response('<html>Bad gateway</html>', 502)]);

        $this->expectException(GatewayException::class);
        $this->gateway()->retrieveCheckout('AS1-ABCDEFGH');
    }

    public function test_a_network_failure_becomes_an_exception(): void
    {
        Http::fake(fn () => throw new ConnectionException('timeout'));

        $this->expectException(GatewayException::class);
        $this->gateway()->retrieveCheckout('AS1-ABCDEFGH');
    }

    // ------------------------------------------------------------------ closing

    public function test_closing_asks_payway_the_right_way_and_shuts_our_page(): void
    {
        Http::fake([self::CLOSE_URL => Http::response(['status' => ['code' => '00', 'message' => 'Success!']])]);
        $gateway = $this->gateway();
        $page = $gateway->createCheckout($this->booking(), 1275, 'http://x/ok', 'http://x/no');
        $this->assertNotNull($gateway->pageFor($page['id']));

        $gateway->expireCheckout($page['id']);

        Http::assertSent(function (Request $request) use ($page) {
            $body = $request->data();

            return $request->url() === self::CLOSE_URL
                && $body['merchant_id'] === self::MERCHANT
                && $body['tran_id'] === $page['id']
                && $body['hash'] === $this->sign($body['req_time'] . self::MERCHANT . $page['id']);
        });
        $this->assertNull($gateway->pageFor($page['id'])); // nobody can open it any more
    }

    public function test_closing_something_payway_never_saw_is_fine(): void
    {
        foreach (['5', '6'] as $code) {
            Http::fake([self::CLOSE_URL => Http::response(['status' => ['code' => $code, 'message' => 'not found']])]);

            $this->gateway()->expireCheckout('AS1-NEVERSEEN');
        }

        $this->assertTrue(true); // no exception
    }

    public function test_a_close_payway_refuses_is_an_error_but_our_page_is_shut_anyway(): void
    {
        Http::fake([self::CLOSE_URL => Http::response(['status' => ['code' => '1', 'message' => 'Wrong hash']])]);
        $gateway = $this->gateway();
        $page = $gateway->createCheckout($this->booking(), 1275, 'http://x/ok', 'http://x/no');

        try {
            $gateway->expireCheckout($page['id']);
            $this->fail('Expected an exception.');
        } catch (GatewayException $e) {
            $this->assertStringContainsString('Wrong hash', $e->getMessage());
        }

        $this->assertNull($gateway->pageFor($page['id']));
    }

    // ------------------------------------------------------------------- refund

    public function test_a_refund_is_encrypted_and_signed_the_way_payway_wants(): void
    {
        $this->makeRsaKeys();
        Http::fake([
            self::CHECK_URL => Http::response($this->approved(12.75)),
            self::REFUND_URL => Http::response(['grand_total' => 12.75, 'total_refunded' => 12.75, 'currency' => 'USD', 'transaction_status' => 'REFUNDED', 'status' => ['code' => '00', 'message' => 'Success!']]),
        ]);

        $id = $this->gateway()->refund('AS12-ABCDEFGH');

        $this->assertNotSame('', $id);

        Http::assertSent(function (Request $request) {
            if ($request->url() !== self::REFUND_URL) {
                return false;
            }
            $body = $request->data();

            // The hash covers the time, the merchant and the encrypted part.
            $hashOk = $body['hash'] === $this->sign($body['request_time'] . self::MERCHANT . $body['merchant_auth']);

            // The encrypted part opens with PayWay's private key and holds the refund details.
            $plain = '';
            foreach (str_split(base64_decode($body['merchant_auth']), 128) as $piece) {
                openssl_private_decrypt($piece, $part, $this->privateKey);
                $plain .= $part;
            }
            $details = json_decode($plain, true);

            return $hashOk
                && $body['merchant_id'] === self::MERCHANT
                && preg_match('/^\d{14}$/', $body['request_time']) === 1
                && $details['mc_id'] === self::MERCHANT
                && $details['tran_id'] === 'AS12-ABCDEFGH'
                && (float) $details['refund_amount'] === 12.75;
        });
    }

    public function test_a_refund_with_a_long_request_is_encrypted_in_pieces(): void
    {
        $this->makeRsaKeys();
        $longMerchant = str_repeat('m', 70); // makes the request longer than one 117-byte piece
        Http::fake([
            self::CHECK_URL => Http::response($this->approved(30.0)),
            self::REFUND_URL => Http::response(['status' => ['code' => '00', 'message' => 'Success!']]),
        ]);
        $gateway = new PaywayGateway($longMerchant, self::KEY, self::BASE, $this->pemPath);

        $gateway->refund('AS1-ABCDEFGH');

        Http::assertSent(function (Request $request) use ($longMerchant) {
            if ($request->url() !== self::REFUND_URL) {
                return false;
            }
            $encrypted = base64_decode($request->data()['merchant_auth']);
            $plain = '';
            foreach (str_split($encrypted, 128) as $piece) {
                openssl_private_decrypt($piece, $part, $this->privateKey);
                $plain .= $part;
            }

            return strlen($encrypted) > 128 // more than one piece
                && json_decode($plain, true)['mc_id'] === $longMerchant;
        });
    }

    public function test_nothing_is_refunded_when_the_payment_was_not_approved(): void
    {
        $this->makeRsaKeys();
        Http::fake([self::CHECK_URL => Http::response(['data' => ['payment_status' => 'PENDING', 'total_amount' => 12.75], 'status' => ['code' => '00']])]);

        try {
            $this->gateway()->refund('AS12-ABCDEFGH');
            $this->fail('Expected an exception.');
        } catch (GatewayException $e) {
            $this->assertStringContainsString('nothing to refund', $e->getMessage());
        }

        Http::assertSentCount(1); // only the check, never a refund
    }

    public function test_refunds_say_clearly_when_the_rsa_key_file_is_missing(): void
    {
        Http::fake([self::CHECK_URL => Http::response($this->approved())]);

        try {
            $this->gateway()->refund('AS12-ABCDEFGH');
            $this->fail('Expected an exception.');
        } catch (GatewayException $e) {
            $this->assertStringContainsString('PAYWAY_RSA_PUBLIC_KEY_PATH', $e->getMessage());
        }

        Http::assertSentCount(1); // only the check
    }

    public function test_refunds_say_clearly_when_the_rsa_key_file_is_damaged(): void
    {
        $this->pemPath = tempnam(sys_get_temp_dir(), 'payway_rsa_');
        file_put_contents($this->pemPath, "-----BEGIN PUBLIC KEY-----\nthis was copied wrong\n-----END PUBLIC KEY-----");
        Http::fake([self::CHECK_URL => Http::response($this->approved())]);

        $this->expectException(GatewayException::class);
        $this->expectExceptionMessage('cannot be read');
        $this->gateway()->refund('AS12-ABCDEFGH');
    }

    public function test_a_refund_payway_refuses_is_an_error_with_its_message(): void
    {
        $this->makeRsaKeys();
        Http::fake([
            self::CHECK_URL => Http::response($this->approved()),
            self::REFUND_URL => Http::response(['status' => ['code' => 'PTL181', 'message' => 'The available balance is not enough to refund the customer']]),
        ]);

        try {
            $this->gateway()->refund('AS12-ABCDEFGH');
            $this->fail('Expected an exception.');
        } catch (GatewayException $e) {
            $this->assertStringContainsString('available balance', $e->getMessage());
            $this->assertStringContainsString('PTL181', $e->getMessage());
        }
    }

    // ------------------------------------------------------------ the web page

    public function test_the_page_sends_the_guest_to_payway_with_the_signed_form(): void
    {
        $booking = $this->booking();
        $page = app(PaywayGateway::class)->createCheckout($booking, 1275, 'http://localhost/payment/success?booking=1', 'http://localhost/payment/cancelled?booking=1');

        $response = $this->get('/payment/payway/' . $page['id'])->assertOk();

        $response->assertSee('action="' . self::BASE . '/api/payment-gateway/v1/payments/purchase"', false);
        $response->assertSee('name="merchant_id" value="' . self::MERCHANT . '"', false);
        $response->assertSee('name="tran_id" value="' . $page['id'] . '"', false);
        $response->assertSee('name="amount" value="12.75"', false);
        $response->assertSee('name="hash"', false);
        $response->assertSee('name="payment_gate" value="0"', false);
        $response->assertSee("getElementById('payway').submit()", false);
        $this->assertStringNotContainsString(self::KEY, $response->getContent());
    }

    public function test_a_closed_unknown_or_oddly_named_page_is_not_shown(): void
    {
        Http::fake([self::CLOSE_URL => Http::response(['status' => ['code' => '00']])]);
        $gateway = app(PaywayGateway::class);
        $page = $gateway->createCheckout($this->booking(), 1275, 'http://localhost/ok', 'http://localhost/no');
        $gateway->expireCheckout($page['id']);

        $this->get('/payment/payway/' . $page['id'])->assertStatus(410)->assertSee('closed');
        $this->get('/payment/payway/AS1-NOTREAL1')->assertStatus(410);
        $this->get('/payment/payway/a')->assertNotFound();               // too short
        $this->get('/payment/payway/' . str_repeat('A', 30))->assertNotFound(); // too long
    }

    // ------------------------------------------- the whole flow with PayWay

    private function startOnline($guest, Booking $booking)
    {
        Sanctum::actingAs($guest);

        return $this->postJson("/api/bookings/{$booking->id}/pay-online");
    }

    public function test_paying_online_with_payway_end_to_end(): void
    {
        $guest = $this->makeUser('customer', ['name' => 'Sok Dara']);
        $booking = $this->makeBooking($guest); // $30, 15% off = $25.50

        $started = $this->startOnline($guest, $booking)
            ->assertOk()
            ->assertJsonPath('mode', 'online')
            ->assertJsonPath('data.amount_due', 25.5);

        $tran = $booking->fresh()->checkout_session_id;
        $this->assertMatchesRegularExpression('/^AS' . $booking->id . '-/', $tran);
        $this->assertSame(rtrim(config('app.url'), '/') . '/payment/payway/' . $tran, $started->json('checkout_url'));
        $this->assertStringContainsString('5156 8399 3770 6777', $started->json('checkout_hint'));

        // PayWay's answers, one after the other: first it does not know the transaction,
        // then (after the guest paid on PayWay's page) it says approved.
        Http::fake([self::CHECK_URL => Http::sequence()
            ->push(['status' => ['code' => 6, 'message' => 'tran_id not found']])
            ->push($this->approved(25.50))]);

        // The guest has not paid yet.
        Sanctum::actingAs($guest);
        $this->postJson("/api/bookings/{$booking->id}/verify-payment")->assertStatus(409)->assertJsonPath('code', 'payment_not_completed');

        // The guest paid.
        $this->postJson("/api/bookings/{$booking->id}/verify-payment")
            ->assertOk()
            ->assertJsonPath('data.status', 'confirmed')
            ->assertJsonPath('data.paid', true);

        $payment = Payment::firstOrFail();
        $this->assertEquals(25.5, $payment->amount);
        $this->assertSame('online', $payment->method);
        $this->assertSame($tran, $payment->reference); // refunds use this
        $this->assertNull($payment->received_by);
    }

    public function test_a_payway_payment_for_the_wrong_amount_is_not_accepted(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);
        $this->startOnline($guest, $booking)->assertOk();

        Http::fake([self::CHECK_URL => Http::response($this->approved(1.00))]);
        Sanctum::actingAs($guest);

        $this->postJson("/api/bookings/{$booking->id}/verify-payment")->assertStatus(422)->assertJsonPath('code', 'payment_mismatch');
        $this->assertSame(0, Payment::count());
        $this->assertSame('pending', $booking->fresh()->status);
    }

    public function test_a_payway_page_started_for_another_booking_is_not_accepted(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);
        $this->startOnline($guest, $booking)->assertOk();
        // Point the booking at a transaction that belongs to booking 999.
        $booking->forceFill(['checkout_session_id' => 'AS999-ABCDEFGH'])->save();

        Http::fake([self::CHECK_URL => Http::response($this->approved(25.50))]);
        Sanctum::actingAs($guest);

        $this->postJson("/api/bookings/{$booking->id}/verify-payment")->assertStatus(422)->assertJsonPath('code', 'payment_mismatch');
        $this->assertSame(0, Payment::count());
    }

    public function test_cancelling_closes_the_payway_page_for_good(): void
    {
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);
        $this->startOnline($guest, $booking)->assertOk();
        $tran = $booking->fresh()->checkout_session_id;

        Http::fake([self::CLOSE_URL => Http::response(['status' => ['code' => '00', 'message' => 'Success!']])]);
        Sanctum::actingAs($guest);
        $this->postJson("/api/bookings/{$booking->id}/release")->assertOk();

        Http::assertSent(fn (Request $r) => $r->url() === self::CLOSE_URL && $r->data()['tran_id'] === $tran);
        $this->get('/payment/payway/' . $tran)->assertStatus(410); // the page cannot be opened again
        $this->assertNull($booking->fresh()->checkout_session_id);
    }

    public function test_a_guest_who_pays_late_after_the_room_was_taken_is_refunded_through_payway(): void
    {
        $this->makeRsaKeys();
        config(['services.payway.rsa_public_key_path' => $this->pemPath]);

        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);
        $this->startOnline($guest, $booking)->assertOk();
        $tran = $booking->fresh()->checkout_session_id;

        $this->travel(20)->minutes();
        $this->makeBooking($this->makeUser('customer'), ['status' => 'confirmed', 'hold' => null]); // the room is taken

        Http::fake([
            self::CHECK_URL => Http::response($this->approved(25.50)),
            self::REFUND_URL => Http::response(['status' => ['code' => '00', 'message' => 'Success!']]),
        ]);
        Sanctum::actingAs($guest);

        $this->postJson("/api/bookings/{$booking->id}/verify-payment")
            ->assertStatus(409)
            ->assertJsonPath('code', 'room_gone_refunded');

        Http::assertSent(fn (Request $r) => $r->url() === self::REFUND_URL);
        $this->assertSame(1, Payment::where('status', 'refunded')->where('reference', $tran)->count());
        $this->assertSame(0, Payment::where('status', 'paid')->count());
        $this->assertSame('cancelled', $booking->fresh()->status);
    }

    public function test_when_payway_cannot_refund_the_guest_is_told_to_call_the_hotel(): void
    {
        // No RSA key file saved: automatic refunds are not set up.
        $guest = $this->makeUser('customer');
        $booking = $this->makeBooking($guest);
        $this->startOnline($guest, $booking)->assertOk();

        $this->travel(20)->minutes();
        $this->makeBooking($this->makeUser('customer'), ['status' => 'confirmed', 'hold' => null]);

        Http::fake([self::CHECK_URL => Http::response($this->approved(25.50))]);
        Sanctum::actingAs($guest);

        $response = $this->postJson("/api/bookings/{$booking->id}/verify-payment")->assertStatus(502)->assertJsonPath('code', 'refund_failed');

        $this->assertStringContainsString($booking->code, $response->json('message'));
    }

    public function test_the_state_is_clean_between_tests(): void
    {
        // A page cached by one test must not be visible to another.
        $this->assertNull(Cache::get('payway:page:AS1-ABCDEFGH'));
    }
}
