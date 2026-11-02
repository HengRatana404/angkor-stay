<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\SettingsService;
use Illuminate\Http\JsonResponse;

/**
 * The few settings every guest may see (to show "save 15% online" and the
 * check-in time). Network rules, demo mode and the rest stay admin only.
 */
class PublicSettingsController extends Controller
{
    public function show(SettingsService $settings): JsonResponse
    {
        return response()->json([
            'data' => [
                'online_discount_percent' => (int) $settings->get('online_discount_percent'),
                'check_in_time' => $settings->get('check_in_time'),
                'check_out_time' => $settings->get('check_out_time'),
            ],
        ]);
    }
}
