<?php

namespace App\Console\Commands;

use App\Services\BookingCleanupService;
use Illuminate\Console\Command;

/** Runs both automatic jobs now. The scheduler runs it every minute; you can also run it by hand for a demo. */
class HotelCleanup extends Command
{
    protected $signature = 'hotel:clean-up';

    protected $description = 'Cancel holds that ran out and mark guests who never came as no-show (with refunds)';

    public function handle(BookingCleanupService $cleanup): int
    {
        $r = $cleanup->run();

        $this->info("Holds tidied up: {$r['expired_holds']}");
        $this->info("No-shows marked: {$r['no_shows']} (refunded {$r['refunded']})");

        if ($r['failed'] > 0) {
            $this->error("Refunds that failed and will be tried again: {$r['failed']}");

            return self::FAILURE;
        }

        return self::SUCCESS;
    }
}
