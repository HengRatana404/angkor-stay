<?php

namespace App\Payments;

use App\Models\Booking;
use Illuminate\Http\Client\ConnectionException;

/**
 * Stripe Checkout in test mode. The guest pays on Stripe's own page, so card
 * numbers never touch this app or the phone.
 */
class StripeGateway implements PaymentGateway
{
    private const API = 'https://api.stripe.com/v1';

    /** Stripe does not allow a payment page that lives less than 30 minutes. */
    private const PAGE_MINUTES = 31;

    public function __construct(private ?string $secret)
    {
    }

    public function name(): string
    {
        return 'stripe';
    }

    public function checkoutHint(): ?string
    {
        return 'Testing? Use the card 4242 4242 4242 4242, any future date and any 3 numbers.';
    }

    public function isConfigured(): bool
    {
        // Only test keys are accepted, so real money can never move by accident.
        // Real Stripe test keys are about 100 characters, so a short one is a typo or a placeholder.
        return is_string($this->secret) && str_starts_with($this->secret, 'sk_test_') && strlen($this->secret) >= 20;
    }

    public function createCheckout(Booking $booking, int $amountCents, string $successUrl, string $cancelUrl): array
    {
        $booking->loadMissing('room.roomType');

        $data = $this->request('post', '/checkout/sessions', [
            'mode' => 'payment',
            'success_url' => $successUrl,
            'cancel_url' => $cancelUrl,
            'client_reference_id' => $booking->code,
            'metadata' => ['booking_id' => $booking->id],
            'expires_at' => now()->addMinutes(self::PAGE_MINUTES)->timestamp,
            'line_items' => [[
                'quantity' => 1,
                'price_data' => [
                    'currency' => 'usd',
                    'unit_amount' => $amountCents,
                    'product_data' => [
                        'name' => "Angkor Stay, {$booking->room?->roomType?->name} room ({$booking->code})",
                        'description' => $booking->check_in_date->format('D j M') . ' to ' . $booking->check_out_date->format('D j M Y')
                            . ', ' . $booking->nights . ' ' . ($booking->nights === 1 ? 'night' : 'nights'),
                    ],
                ],
            ]],
        ]);

        if (empty($data['id']) || empty($data['url'])) {
            throw new GatewayException('Stripe did not return a payment page.');
        }

        return ['id' => $data['id'], 'url' => $data['url']];
    }

    public function retrieveCheckout(string $sessionId): array
    {
        $data = $this->request('get', '/checkout/sessions/' . rawurlencode($sessionId));

        $bookingId = $data['metadata']['booking_id'] ?? null;

        return [
            'paid' => ($data['payment_status'] ?? null) === 'paid',
            'expired' => ($data['status'] ?? null) === 'expired',
            'amount_cents' => (int) ($data['amount_total'] ?? 0),
            'currency' => strtolower((string) ($data['currency'] ?? '')),
            'booking_id' => is_numeric($bookingId) ? (int) $bookingId : null,
            'payment_reference' => is_string($data['payment_intent'] ?? null) ? $data['payment_intent'] : null,
        ];
    }

    public function refund(string $paymentReference): string
    {
        $data = $this->request('post', '/refunds', ['payment_intent' => $paymentReference]);

        if (empty($data['id'])) {
            throw new GatewayException('Stripe did not confirm the refund.');
        }

        return $data['id'];
    }

    public function expireCheckout(string $sessionId): void
    {
        $this->request('post', '/checkout/sessions/' . rawurlencode($sessionId) . '/expire');
    }

    /**
     * @return array<string, mixed>
     *
     * @throws GatewayException
     */
    private function request(string $method, string $path, array $params = []): array
    {
        if (! $this->isConfigured()) {
            throw new GatewayException('Stripe is not set up. Put a test key in STRIPE_SECRET.');
        }

        try {
            $client = HttpClient::make()->withBasicAuth($this->secret, '')->acceptJson();

            $response = $method === 'get'
                ? $client->get(self::API . $path)
                : $client->asForm()->post(self::API . $path, $params);
        } catch (ConnectionException $e) {
            throw new GatewayException('Could not reach Stripe. Try again in a moment.', 0, $e);
        }

        if ($response->failed()) {
            // The key itself is never put in a message.
            throw new GatewayException($response->json('error.message') ?: 'Stripe refused the request.');
        }

        return $response->json() ?? [];
    }
}
