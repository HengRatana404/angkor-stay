<?php

namespace App\Services;

use App\Models\Setting;

/**
 * Knows this PC's Wi-Fi (LAN) address and keeps the last one in the `settings` table.
 * The phone asks for it (through the tunnel) when its saved address stops working,
 * for example after the router gave this PC a new IP.
 */
class LanAddress
{
    public const KEY = 'server_lan_ip';

    /** The address this PC uses on the local network, or null when it has none. */
    public function detect(): ?string
    {
        // A UDP "connect" sends nothing. It only makes the system pick the network card
        // it would use to reach the internet, and that card's address is the Wi-Fi IP.
        try {
            $socket = @stream_socket_client('udp://192.0.2.1:9', $errno, $error, 1);
            if ($socket) {
                $name = stream_socket_get_name($socket, false);
                fclose($socket);
                $ip = $name ? explode(':', $name)[0] : null;
                if ($this->isUsable($ip)) {
                    return $ip;
                }
            }
        } catch (\Throwable) {
            // fall through to the host name
        }

        $ip = gethostbyname(gethostname());

        return $this->isUsable($ip) ? $ip : null;
    }

    public function saved(): ?string
    {
        $value = Setting::query()->where('key', self::KEY)->value('value');

        return $value === null ? null : json_decode($value, true);
    }

    /** Checks the real address now and saves it when it is different. Returns the real address. */
    public function refresh(): ?string
    {
        $ip = $this->detect();

        if ($ip !== null && $ip !== $this->saved()) {
            Setting::updateOrCreate(['key' => self::KEY], ['value' => json_encode($ip)]);
        }

        return $ip ?? $this->saved();
    }

    private function isUsable(?string $ip): bool
    {
        return $ip !== null
            && filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)
            && ! str_starts_with($ip, '127.')
            && ! str_starts_with($ip, '169.254.')
            && $ip !== '0.0.0.0';
    }
}
