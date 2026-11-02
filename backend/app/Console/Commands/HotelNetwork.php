<?php

namespace App\Console\Commands;

use App\Services\SettingsService;
use Illuminate\Console\Command;

/**
 * Rescue tool for when the admin is locked out of the app
 * because the allowed network was set wrong.
 */
class HotelNetwork extends Command
{
    protected $signature = 'hotel:network
        {action=show : show, on, off, or networks such as 192.168.1.0/24,10.0.0.0/8}';

    protected $description = 'Show or change the network staff and admin must use';

    public function handle(SettingsService $settings): int
    {
        $action = trim((string) $this->argument('action'));

        switch (strtolower($action)) {
            case 'show':
                break;

            case 'off':
                $settings->update(['staff_login_restricted' => false]);
                $this->info('Staff and admin can now log in from any network.');
                break;

            case 'on':
                $settings->update(['staff_login_restricted' => true]);
                $this->info('Staff and admin must now use an allowed network.');
                break;

            default:
                $networks = [];
                foreach (explode(',', $action) as $entry) {
                    $normal = SettingsService::normalizeNetwork($entry);
                    if ($normal === null) {
                        $this->error("\"{$entry}\" is not a network. Example: 192.168.1.0/24");

                        return self::FAILURE;
                    }
                    $networks[] = $normal;
                }
                $settings->update([
                    'allowed_networks' => array_values(array_unique($networks)),
                    'staff_login_restricted' => true,
                ]);
                $this->info('Allowed networks saved.');
        }

        $this->line('Rule is ' . ($settings->isNetworkRestricted() ? 'ON' : 'OFF'));
        $this->line('Allowed networks: ' . implode(', ', $settings->allowedNetworks()));

        return self::SUCCESS;
    }
}
