<?php

namespace App\Services;

use App\Models\Setting;
use App\Models\User;
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

        return $this->isInAllowedNetwork($ip);
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
