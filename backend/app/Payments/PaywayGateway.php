<?php

namespace App\Payments;

use App\Models\Booking;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Str;

/**
 * ABA PayWay (Cambodia), SANDBOX only. The guest pays on PayWay's own page, so card
 * numbers never touch this app or the phone.
 *
 * How it works:
 *  - PayWay's payment page is opened by a browser form POST that carries a signed hash.
 *    So createCheckout() gives back the address of a small page on THIS server
 *    (/payment/payway/{tran_id}) that signs the form and sends the browser on to PayWay.
 *  - The server later asks PayWay "check transaction" to learn if it was paid.
 *  - "Close transaction" shuts an unused page, and PayWay then refuses any later payment.
 *  - Refunds are encrypted with the RSA PUBLIC key that PayWay emailed.
 *
 * Every request is signed: base64(HMAC-SHA512(fields glued together, api_key)). ABA's docs
 * call the api_key the "public key", but it is a secret and must never leave the server.
 */
class PaywayGateway implements PaymentGateway
{
    private const PURCHASE = '/api/payment-gateway/v1/payments/purchase';
    private const CHECK = '/api/payment-gateway/v1/payments/check-transaction-2';
    private const CLOSE = '/api/payment-gateway/v1/payments/close-transaction';
    private const REFUND = '/api/merchant-portal/merchant-access/online-transaction/refund';

    /** How long a payment page can be used after the guest first opens it. */
    private const PAGE_LIFETIME_MINUTES = 30;

    /** The order PayWay wants the purchase fields glued together for the hash. Fields we do not send are empty. */
    private const PURCHASE_HASH_ORDER = [
        'req_time', 'merchant_id', 'tran_id', 'amount', 'items', 'shipping', 'firstname', 'lastname', 'email',
        'phone', 'type', 'payment_option', 'return_url', 'cancel_url', 'continue_success_url', 'return_deeplink',
        'currency', 'custom_fields', 'return_params', 'payout', 'lifetime', 'additional_params',
        'google_pay_token', 'skip_success_page',
    ];

    public function __construct(
        private ?string $merchantId,
        private ?string $apiKey,
        private string $baseUrl,
        private ?string $rsaPublicKeyPath = null,
    ) {
    }

    public function name(): string
    {
        return 'payway';
    }

    public function checkoutHint(): ?string
    {
        return 'Sandbox test card: 5156 8399 3770 6777, expiry 01/30, CVV 993. No real money moves.';
    }

    public function isConfigured(): bool
    {
        $host = strtolower((string) parse_url($this->baseUrl, PHP_URL_HOST));

        // Sandbox only, so real money can never move by accident.
        return filled($this->merchantId) && filled($this->apiKey) && str_contains($host, 'sandbox');
    }

    // ----------------------------------------------------------------- opening a page

    public function createCheckout(Booking $booking, int $amountCents, string $successUrl, string $cancelUrl): array
    {
        $this->ensureConfigured();
        $booking->loadMissing('user');

        $tran = $this->newTranId($booking);
        $amount = number_format($amountCents / 100, 2, '.', '');
        [$first, $last] = $this->nameParts($booking->user?->name);
        $email = (string) $booking->user?->email;

        $params = array_filter([
            'tran_id' => $tran,
            'amount' => $amount,
            'items' => base64_encode(json_encode([[
                'name' => "Angkor Stay room {$booking->code}",
                'quantity' => 1,
                'price' => (float) $amount,
            ]])),
            'firstname' => $first,
            'lastname' => $last,
            'email' => strlen($email) <= 50 ? $email : '',
            'type' => 'purchase',
            'cancel_url' => $cancelUrl,
            'continue_success_url' => $successUrl,
            'currency' => 'USD',
            'lifetime' => (string) self::PAGE_LIFETIME_MINUTES,
        ], fn ($value) => $value !== '' && $value !== null);

        // The form is signed when the guest opens the page (fresh time), not now.
        Cache::put($this->pageKey($tran), $params, now()->addMinutes(self::PAGE_LIFETIME_MINUTES + 5));

        $origin = parse_url($successUrl);
        $site = ($origin['scheme'] ?? 'http') . '://' . ($origin['host'] ?? 'localhost') . (isset($origin['port']) ? ':' . $origin['port'] : '');

        return ['id' => $tran, 'url' => $site . '/payment/payway/' . $tran];
    }

    /**
     * The signed form for our "go to PayWay" page, or null when the page is closed or too old.
     *
     * @return array{action: string, fields: array<string, string>}|null
     */
    public function pageFor(string $tran): ?array
    {
        $params = Cache::get($this->pageKey($tran));

        if (! is_array($params) || Cache::has($this->closedKey($tran)) || ! $this->isConfigured()) {
            return null;
        }

        $fields = array_merge(['req_time' => gmdate('YmdHis'), 'merchant_id' => $this->merchantId], $params);

        $glued = '';
        foreach (self::PURCHASE_HASH_ORDER as $name) {
            $glued .= $fields[$name] ?? '';
        }
        $fields['hash'] = $this->sign($glued);

        // These two are not part of the signed hash (see ABA's docs). Without payment_gate=0 a
        // merchant that also has the QR service answers with raw QR data instead of the payment page.
        $fields['payment_gate'] = '0';
        $fields['view_type'] = 'hosted_view';

        return ['action' => rtrim($this->baseUrl, '/') . self::PURCHASE, 'fields' => $fields];
    }

    // --------------------------------------------------------------------- checking

    public function retrieveCheckout(string $sessionId): array
    {
        $data = $this->call(self::CHECK, $this->signedRequest($sessionId));
        $code = (string) ($data['status']['code'] ?? '');

        $answer = [
            'paid' => false,
            'expired' => false,
            'amount_cents' => 0,
            'currency' => 'usd', // we only ever ask for USD
            'booking_id' => $this->bookingIdFrom($sessionId),
            'payment_reference' => $sessionId, // PayWay refunds by the transaction id
        ];

        // "tran_id not found": the guest has not opened or paid the page yet.
        if ($code === '6') {
            return $answer;
        }
        if ($code !== '00') {
            throw new GatewayException('PayWay: ' . ($data['status']['message'] ?? 'could not check the payment') . " (code {$code})");
        }

        $status = (string) ($data['data']['payment_status'] ?? '');

        $answer['paid'] = $status === 'APPROVED';
        // A closed or fully refunded transaction can never be paid any more.
        $answer['expired'] = in_array($status, ['CANCELLED', 'REFUNDED'], true);
        $answer['amount_cents'] = (int) round(((float) ($data['data']['total_amount'] ?? 0)) * 100);

        return $answer;
    }

    // ----------------------------------------------------------------------- closing

    public function expireCheckout(string $sessionId): void
    {
        $this->ensureConfigured();

        // Our own page stops working at once, even before PayWay answers.
        Cache::put($this->closedKey($sessionId), true, now()->addDay());
        Cache::forget($this->pageKey($sessionId));

        $data = $this->call(self::CLOSE, $this->signedRequest($sessionId));
        $code = (string) ($data['status']['code'] ?? '');

        // "00" = closed. "5" or "6" = PayWay never saw it, so there is nothing to close.
        if (! in_array($code, ['00', '5', '6'], true)) {
            throw new GatewayException('PayWay: ' . ($data['status']['message'] ?? 'could not close the payment') . " (code {$code})");
        }
    }

    // ----------------------------------------------------------------------- refund

    public function refund(string $paymentReference): string
    {
        $this->ensureConfigured();

        $info = $this->retrieveCheckout($paymentReference);
        if (! $info['paid']) {
            throw new GatewayException('PayWay: this transaction is not paid, so there is nothing to refund.');
        }

        $amount = round($info['amount_cents'] / 100, 2);

        $auth = $this->encryptForRefund(json_encode([
            'mc_id' => $this->merchantId,
            'tran_id' => $paymentReference,
            'refund_amount' => $amount,
        ]));

        $time = gmdate('YmdHis');
        $data = $this->call(self::REFUND, [
            'request_time' => $time,
            'merchant_id' => $this->merchantId,
            'merchant_auth' => $auth,
            'hash' => $this->sign($time . $this->merchantId . $auth),
        ]);

        $code = (string) ($data['status']['code'] ?? '');
        if ($code !== '00') {
            throw new GatewayException('PayWay refund: ' . ($data['status']['message'] ?? 'refused') . " (code {$code})");
        }

        return 'payway-refund-' . $paymentReference;
    }

    /** PayWay wants the refund details encrypted with its RSA public key, 117 bytes at a time. */
    private function encryptForRefund(string $json): string
    {
        $path = $this->rsaPublicKeyPath;
        $pem = ($path && is_file($path)) ? trim((string) file_get_contents($path)) : '';

        if ($pem === '') {
            throw new GatewayException(
                'Refunds are not set up. Save the RSA public key from the PayWay email in a file '
                . 'and put its path in PAYWAY_RSA_PUBLIC_KEY_PATH.'
            );
        }

        $key = openssl_pkey_get_public($pem);
        if ($key === false) {
            throw new GatewayException('The PayWay RSA public key file cannot be read. Check that it was copied whole.');
        }

        $encrypted = '';
        foreach (str_split($json, 117) as $chunk) {
            if (! openssl_public_encrypt($chunk, $piece, $key)) {
                throw new GatewayException('Could not encrypt the refund request.');
            }
            $encrypted .= $piece;
        }

        return base64_encode($encrypted);
    }

    // ---------------------------------------------------------------------- helpers

    /** check-transaction and close-transaction are signed over req_time + merchant_id + tran_id. */
    private function signedRequest(string $tran): array
    {
        $time = gmdate('YmdHis');

        return [
            'req_time' => $time,
            'merchant_id' => $this->merchantId,
            'tran_id' => $tran,
            'hash' => $this->sign($time . $this->merchantId . $tran),
        ];
    }

    private function sign(string $glued): string
    {
        return base64_encode(hash_hmac('sha512', $glued, (string) $this->apiKey, true));
    }

    /**
     * @return array<string, mixed>
     *
     * @throws GatewayException
     */
    private function call(string $path, array $payload): array
    {
        $this->ensureConfigured();

        try {
            $response = HttpClient::make()->acceptJson()->asJson()->post(rtrim($this->baseUrl, '/') . $path, $payload);
        } catch (ConnectionException $e) {
            throw new GatewayException('Could not reach PayWay. Try again in a moment.', 0, $e);
        }

        $data = $response->json();

        // PayWay answers 200 with a status code inside. A wrong hash is an HTTP 403 with one too.
        if (! is_array($data) || ! isset($data['status'])) {
            throw new GatewayException('PayWay sent an answer we do not understand (HTTP ' . $response->status() . ').');
        }

        return $data;
    }

    private function ensureConfigured(): void
    {
        if (! $this->isConfigured()) {
            throw new GatewayException('PayWay is not set up. Put the sandbox Merchant ID and key in .env.');
        }
    }

    /** "AS12-K3F9QZ7M": at most 20 letters and numbers, and it carries the booking number. */
    private function newTranId(Booking $booking): string
    {
        $prefix = 'AS' . $booking->id . '-';

        return $prefix . Str::upper(Str::random(min(10, 20 - strlen($prefix))));
    }

    private function bookingIdFrom(string $tran): ?int
    {
        return preg_match('/^AS(\d+)-/', $tran, $m) ? (int) $m[1] : null;
    }

    /** PayWay refuses names with numbers or special characters, so keep letters only. @return array{string, string} */
    private function nameParts(?string $name): array
    {
        $clean = trim(preg_replace('/\s+/', ' ', preg_replace('/[^\p{L} ]+/u', '', (string) $name)));
        if ($clean === '') {
            return ['', ''];
        }

        $parts = explode(' ', $clean, 2);

        return [mb_substr($parts[0], 0, 100), mb_substr($parts[1] ?? '', 0, 100)];
    }

    private function pageKey(string $tran): string
    {
        return "payway:page:{$tran}";
    }

    private function closedKey(string $tran): string
    {
        return "payway:closed:{$tran}";
    }
}
