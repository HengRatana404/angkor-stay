<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\UpdateSettingsRequest;
use App\Services\SettingsService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/** Admin only: discount, times and the hotel network. */
class SettingsController extends Controller
{
    public function __construct(private SettingsService $settings)
    {
    }

    public function show(Request $request): JsonResponse
    {
        return $this->respond($request);
    }

    public function update(UpdateSettingsRequest $request): JsonResponse
    {
        $this->settings->update($request->validated());

        return $this->respond($request);
    }

    private function respond(Request $request): JsonResponse
    {
        return response()->json([
            'data' => $this->settings->all(),
            // So the app can offer "use this device's network".
            'your_ip' => $request->ip(),
        ]);
    }
}
