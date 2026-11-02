<?php

namespace Tests\Support;

use App\Models\Booking;
use App\Payments\GatewayException;
use App\Payments\PaymentGateway;

/**
 * A pretend Stripe for the tests. It remembers every payment page it opened,
 * lets a test "pay" on a page, and can be told to fail.
 */
class FakeGateway implements PaymentGateway
{
    public bool $configured = true;

    public bool $failCreate = false;
    public bool $failRetrieve = false;
    public bool $failRefund = false;
    public bool $failExpire = false;

    /** @var array<string, array> */
    public array $sessions = [];

    /** @var list<array> */
    public array $created = [];

    /** @var list<string> */
    public array $expired = [];

    /** @var list<string> */
    public array $refunds = [];

    private int $counter = 0;

    public ?string $hint = 'Use the test card 4242 4242 4242 4242.';

    public function name(): string
    {
        return 'fake';
    }

    public function checkoutHint(): ?string
    {
        return $this->hint;
    }

    public function isConfigured(): bool
    {
        return $this->configured;
    }

    public function createCheckout(Booking $booking, int $amountCents, string $successUrl, string $cancelUrl): array
    {
        if ($this->failCreate) {
            throw new GatewayException('Stripe is down.');
        }

        $id = 'cs_test_' . (++$this->counter);

        $this->sessions[$id] = [
            'paid' => false,
            'expired' => false,
            'amount_cents' => $amountCents,
            'currency' => 'usd',
            'booking_id' => $booking->id,
            'payment_reference' => null,
        ];
        $this->created[] = [
            'id' => $id,
            'booking_id' => $booking->id,
            'amount_cents' => $amountCents,
            'success_url' => $successUrl,
            'cancel_url' => $cancelUrl,
        ];

        return ['id' => $id, 'url' => "https://checkout.stripe.test/pay/{$id}"];
    }

    /** The guest pays on the page. Options can change what Stripe will report. */
    public function pay(string $sessionId, array $override = []): void
    {
        $this->sessions[$sessionId] = array_merge(
            $this->sessions[$sessionId],
            ['paid' => true, 'payment_reference' => 'pi_test_' . $sessionId],
            $override,
        );
    }

    public function lastSessionId(): string
    {
        return array_key_last($this->sessions);
    }

    public function retrieveCheckout(string $sessionId): array
    {
        if ($this->failRetrieve) {
            throw new GatewayException('Stripe is down.');
        }
        if (! isset($this->sessions[$sessionId])) {
            throw new GatewayException('No such session.');
        }

        return $this->sessions[$sessionId];
    }

    public function refund(string $paymentReference): string
    {
        if ($this->failRefund) {
            throw new GatewayException('Refund refused.');
        }

        $this->refunds[] = $paymentReference;

        return 're_test_' . count($this->refunds);
    }

    public function expireCheckout(string $sessionId): void
    {
        if ($this->failExpire) {
            throw new GatewayException('Cannot expire this session.');
        }

        $this->expired[] = $sessionId;

        if (isset($this->sessions[$sessionId]) && ! $this->sessions[$sessionId]['paid']) {
            $this->sessions[$sessionId]['expired'] = true;
        }
    }
}
