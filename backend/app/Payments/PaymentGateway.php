<?php

namespace App\Payments;

use App\Models\Booking;

/**
 * The company that takes online payments (PayWay in Cambodia, or Stripe). The rest
 * of the app only talks to this interface, so another company, or a fake one in
 * tests, can be plugged in without changing the booking rules.
 */
interface PaymentGateway
{
    /** A short name for logs and tests: "payway", "stripe". */
    public function name(): string;

    /** Is the gateway set up (sandbox or test keys are in .env)? */
    public function isConfigured(): bool;

    /** A sentence for the guest on the "finish paying" screen, such as the test card to use. */
    public function checkoutHint(): ?string;

    /**
     * Opens a payment page for the booking.
     *
     * @return array{id: string, url: string}
     *
     * @throws GatewayException
     */
    public function createCheckout(Booking $booking, int $amountCents, string $successUrl, string $cancelUrl): array;

    /**
     * Asks the gateway what really happened on a payment page.
     *
     * @return array{paid: bool, expired: bool, amount_cents: int, currency: string, booking_id: ?int, payment_reference: ?string}
     *
     * @throws GatewayException
     */
    public function retrieveCheckout(string $sessionId): array;

    /**
     * Gives the money back. Returns the refund's id.
     *
     * @throws GatewayException
     */
    public function refund(string $paymentReference): string;

    /**
     * Closes an unused payment page, so nobody can pay on it later.
     *
     * @throws GatewayException
     */
    public function expireCheckout(string $sessionId): void;
}
