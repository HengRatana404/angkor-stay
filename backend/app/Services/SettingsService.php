<?php

namespace App\Services;

use App\Models\Setting;
use App\Models\User;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Symfony\Component\HttpFoundation\IpUtils;

class SettingsService
{
    /** All settings: the admin's saved values on top of the defaults. */
    public function all(): array
    {
        $defaults = config('hotel.defaults');

        $saved = Setting::query()
            ->whereIn('key', array_keys($defaults))
            ->pluck('value', 'key')
            ->map(fn (string $json) => json_decode($json, true))
            ->all();

        return array_merge($defaults, $saved);
    }

    public function get(string $key): mixed
    {
        return $this->all()[$key] ?? null;
    }

    /**
     * Saves only the known settings. Unknown keys are ignored.
     * Each value is saved with the same type as its default, so "25" from a
     * form becomes the number 25 and "1" becomes true.
     */
    public function update(array $values): void
    {
        foreach (config('hotel.defaults') as $key => $default) {
            if (array_key_exists($key, $values)) {
                Setting::updateOrCreate(
                    ['key' => $key],
                    ['value' => json_encode($this->sameTypeAs($default, $values[$key]))],
                );
            }
        }
    }

    private function sameTypeAs(mixed $default, mixed $value): mixed
    {
        return match (true) {
            is_int($default) => (int) $value,
            is_bool($default) => filter_var($value, FILTER_VALIDATE_BOOLEAN),
            is_string($default) => (string) $value,
            default => $value,
        };
    }

    public function isNetworkRestricted(): bool
    {
        return (bool) $this->get('staff_login_restricted');
    }

    /** @return string[] */
    public function allowedNetworks(): array
    {
        return array_values((array) $this->get('allowed_networks'));
    }

    /** Is this address inside one of the allowed networks? */
    public function isInAllowedNetwork(string $ip, ?array $networks = null): bool
    {
        return IpUtils::checkIp($ip, $networks ?? $this->allowedNetworks());
    }

    /**
     * The address the visitor really connects from.
     *
     * Only the web server's own socket is believed, plus the forwarding header of a tunnel
     * program running on this same PC (ngrok, cloudflared): bootstrap/app.php trusts proxies
     * at 127.0.0.1 only. Headers sent by a client (CF-Connecting-IP, X-Forwarded-For) are never
     * trusted by themselves, so nobody can claim to be on the hotel network.
     */
    public function effectiveIp(\Illuminate\Http\Request $request): string
    {
        return $request->ip();
    }

    /**
     * May this user use the app from this address?
     * Customers can connect from anywhere. Staff and admin only from
     * the hotel network, unless the admin switched that rule off.
     */
    public function mayConnectFrom(User $user, string $ip): bool
    {
        if (! in_array($user->role, ['staff', 'admin'], true)) {
            return true;
        }

        if (! $this->isNetworkRestricted()) {
            return true;
        }

        return $this->isInAllowedNetwork($ip) || $this->isOnServersPublicAddress($ip);
    }

    /**
     * Wi-Fi that stops phones from reaching the PC directly (client isolation) forces the app
     * to use the tunnel. Phone and PC are still on the same Wi-Fi, so the internet sees both
     * with the same public address. When HOTEL_TRUST_SAME_PUBLIC_IP is on, a visitor who comes
     * from this PC's own public address counts as "on the hotel network".
     * The visitor address is only believed when it comes from the tunnel program on this PC
     * (see bootstrap/app.php), so nobody can claim it with a header.
     */
    public function isOnServersPublicAddress(string $ip): bool
    {
        $networks = [];
        foreach ($this->serverPublicAddresses() as $own) {
            $networks[] = str_contains($own, ':') ? $own.'/64' : $own.'/32';
        }

        return $networks !== [] && IpUtils::checkIp($ip, $networks);
    }

    /** @return string[] This PC's public address(es) as the internet sees them. Empty when off or unknown. */
    public function serverPublicAddresses(): array
    {
        if (! config('hotel.trust_same_public_ip')) {
            return [];
        }

        $cached = Cache::get('hotel.server_public_ips');
        if (is_array($cached)) {
            return $cached;
        }

        $found = [];
        foreach (['https://api.ipify.org', 'https://api6.ipify.org'] as $url) {
            $address = $this->lookUpAddress($url);
            if ($address !== null && filter_var($address, FILTER_VALIDATE_IP)) {
                $found[] = $address;
            }
        }
        $found = array_values(array_unique($found));

        // Keep a good answer for 5 minutes. An empty answer is not kept, so the next request retries.
        if ($found !== []) {
            Cache::put('hotel.server_public_ips', $found, 300);
        }

        return $found;
    }

    /** Asks a "what is my IP" site for this PC's public address. Null when it cannot be learned. */
    private function lookUpAddress(string $url): ?string
    {
        try {
            return trim(Http::timeout(3)->get($url)->body());
        } catch (\Throwable) {
            // On Windows PHP often has no certificate bundle for cURL (error 60).
            // PHP's own HTTPS stream still works there, so try that once.
            $body = @file_get_contents($url, false, stream_context_create(['http' => ['timeout' => 3]]));

            return $body === false ? null : trim($body);
        }
    }

    /**
     * "192.168.1.0/24" stays as it is, "10.0.0.5" becomes "10.0.0.5/32".
     * Returns null when the text is not a network.
     */
    public static function normalizeNetwork(string $entry): ?string
    {
        $entry = trim($entry);
        if ($entry === '') {
            return null;
        }

        [$ip, $mask] = array_pad(explode('/', $entry, 2), 2, null);

        if (! filter_var($ip, FILTER_VALIDATE_IP)) {
            return null;
        }

        $max = str_contains($ip, ':') ? 128 : 32;
        $mask ??= (string) $max;

        if (! ctype_digit($mask) || (int) $mask > $max) {
            return null;
        }

        return $ip . '/' . (int) $mask;
    }
}
