<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\LanAddress;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Tells our own app where this server is on the Wi-Fi.
 * Only answers when the app sends the secret key (SERVER_INFO_KEY in .env), so
 * strangers who find the tunnel address never learn the PC's local IP.
 */
class ServerInfoController extends Controller
{
    public function show(Request $request, LanAddress $lan): JsonResponse
    {
        $expected = (string) config('hotel.server_info_key');
        $given = (string) $request->header('X-Server-Key');

        // Off until a key is set. Same answer for "off" and "wrong key".
        if ($expected === '' || ! hash_equals($expected, $given)) {
            return response()->json(['message' => 'Not found.'], 404);
        }

        $ip = $lan->refresh();
        $port = (int) config('hotel.server_port');

        return response()->json([
            'lan_ip' => $ip,
            'lan_url' => $ip ? "http://{$ip}:{$port}/api" : null,
        ]);
    }
}
