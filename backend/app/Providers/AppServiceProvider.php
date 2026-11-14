<?php

namespace App\Providers;

use App\Services\LanAddress;
use Illuminate\Console\Events\CommandStarting;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        // When `php artisan serve` starts, remember this PC's Wi-Fi address in the database.
        Event::listen(CommandStarting::class, function (CommandStarting $event): void {
            if ($event->command !== 'serve') {
                return;
            }
            try {
                app(LanAddress::class)->refresh();
            } catch (\Throwable) {
                // The server must still start if the database is not ready.
            }
        });
    }
}
