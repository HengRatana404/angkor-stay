<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Services\BookingCleanupService;
use Illuminate\Http\JsonResponse;

class MaintenanceController extends Controller
{
    /** The admin runs the automatic jobs now (useful for a demo, and as a safety net). */
    public function run(BookingCleanupService $cleanup): JsonResponse
    {
        return response()->json(['data' => $cleanup->run()]);
    }
}
