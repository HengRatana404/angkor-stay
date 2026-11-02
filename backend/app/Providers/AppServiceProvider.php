<?php

namespace App\Providers;

use App\Payments\PaymentGateway;
use App\Payments\PaywayGateway;
use App\Payments\StripeGateway;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        // ABA PayWay (Cambodia), sandbox only.
        $this->app->bind(PaywayGateway::class, fn () => new PaywayGateway(
            config('services.payway.merchant_id'),
            config('services.payway.api_key'),
            (string) config('services.payway.base_url'),
            config('services.payway.rsa_public_key_path'),
        ));

        // Online payments use PayWay when its sandbox keys are in .env, otherwise Stripe
        // (which does not work in Cambodia, but is kept for other countries).
        // Tests plug in a fake gateway here instead.
        $this->app->bind(PaymentGateway::class, function ($app) {
            $payway = $app->make(PaywayGateway::class);

            return $payway->isConfigured()
                ? $payway
                : new StripeGateway(config('services.stripe.secret'));
        });
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        //
    }
}
