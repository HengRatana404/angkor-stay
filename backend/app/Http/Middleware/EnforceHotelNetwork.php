<?php

namespace App\Http\Middleware;

use App\Services\SettingsService;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Staff and admin can only use the app from the hotel network, even with a
 * valid login token. So a token that leaves the hotel stops working.
 * Customers are not affected. Use it after `auth:sanctum`.
 */
class EnforceHotelNetwork
{
    public function __construct(private SettingsService $settings)
    {
    }

    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        // $request->ip() is the address of the connection itself. Headers such
        // as X-Forwarded-For are ignored, so they cannot be used to cheat.
        if ($user && ! $this->settings->mayConnectFrom($user, $request->ip())) {
            return response()->json([
                'message' => 'Staff and admin can only use the app on the hotel network.',
                'code' => 'outside_hotel_network',
            ], 403);
        }

        return $next($request);
    }
}
