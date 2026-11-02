<?php

use App\Http\Controllers\Api\Admin\DashboardController;
use App\Http\Controllers\Api\Admin\MaintenanceController;
use App\Http\Controllers\Api\Admin\RoomAdminController;
use App\Http\Controllers\Api\Admin\RoomTypeAdminController;
use App\Http\Controllers\Api\Admin\SettingsController;
use App\Http\Controllers\Api\Admin\StaffController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\BookingController;
use App\Http\Controllers\Api\OnlinePaymentController;
use App\Http\Controllers\Api\PublicSettingsController;
use App\Http\Controllers\Api\RoomTypeController;
use App\Http\Controllers\Api\Staff\BookingController as StaffBookingController;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Route;

Route::get('/health', function () {
    try {
        DB::connection()->getPdo();
        $database = 'connected';
    } catch (\Throwable $e) {
        $database = 'error';
    }

    return response()->json([
        'app' => 'Angkor Stay API',
        'status' => $database === 'connected' ? 'ok' : 'degraded',
        'database' => $database,
    ], $database === 'connected' ? 200 : 503);
});

// The few settings every guest may see: the online discount and the check-in time.
Route::get('/settings/public', [PublicSettingsController::class, 'show']);

// Anyone can look at the rooms, like on a hotel website.
Route::get('/room-types', [RoomTypeController::class, 'index']);
Route::get('/room-types/{roomType}', [RoomTypeController::class, 'show']);

Route::prefix('auth')->group(function () {
    Route::middleware('throttle:10,1')->group(function () {
        Route::post('/register', [AuthController::class, 'register']);
        Route::post('/verify-email', [AuthController::class, 'verifyEmail']);
        Route::post('/resend-code', [AuthController::class, 'resendCode']);
        Route::post('/login', [AuthController::class, 'login']);
        Route::post('/forgot-password', [AuthController::class, 'forgotPassword']);
        Route::post('/check-reset-code', [AuthController::class, 'checkResetCode']);
        Route::post('/reset-password', [AuthController::class, 'resetPassword']);
    });

    // Logging out is always allowed, even for staff outside the hotel network.
    Route::post('/logout', [AuthController::class, 'logout'])->middleware('auth:sanctum');
});

// Everything below needs a login. Staff and admin must also be on the hotel network
// (`hotel.network`). Customers can connect from anywhere.
Route::middleware(['auth:sanctum', 'hotel.network'])->group(function () {
    Route::get('/auth/me', [AuthController::class, 'me']);
    Route::patch('/auth/profile', [AuthController::class, 'updateProfile']);
    Route::post('/auth/change-password', [AuthController::class, 'changePassword'])->middleware('throttle:5,1');

    Route::prefix('bookings')->group(function () {
        Route::get('/', [BookingController::class, 'index']);
        Route::post('/', [BookingController::class, 'store'])->middleware('throttle:20,1');
        Route::post('/{id}/cancel', [BookingController::class, 'cancel'])->whereNumber('id')->middleware('throttle:20,1');
        Route::get('/{id}', [BookingController::class, 'show'])->whereNumber('id');
        Route::post('/{id}/release', [BookingController::class, 'release'])->whereNumber('id');
        Route::post('/{id}/pay-at-hotel', [BookingController::class, 'payAtHotel'])->whereNumber('id');

        // Pay online: choose it, then ask the server to check the payment.
        Route::post('/{id}/pay-online', [OnlinePaymentController::class, 'start'])->whereNumber('id')->middleware('throttle:20,1');
        Route::post('/{id}/verify-payment', [OnlinePaymentController::class, 'verify'])->whereNumber('id')->middleware('throttle:30,1');
        Route::post('/{id}/demo-pay', [OnlinePaymentController::class, 'demoPay'])->whereNumber('id')->middleware('throttle:20,1');
    });

    // Staff and admin: bookings, payment at the hotel, check-in and check-out.
    Route::prefix('staff/bookings')->middleware('role:staff,admin')->group(function () {
        Route::get('/', [StaffBookingController::class, 'index']);
        Route::get('/{id}', [StaffBookingController::class, 'show'])->whereNumber('id');
        Route::post('/{id}/payments', [StaffBookingController::class, 'takePayment'])->whereNumber('id');
        Route::post('/{id}/check-in', [StaffBookingController::class, 'checkIn'])->whereNumber('id');
        Route::post('/{id}/check-out', [StaffBookingController::class, 'checkOut'])->whereNumber('id');
    });

    // Admin only.
    Route::prefix('admin')->middleware('role:admin')->group(function () {
        Route::get('/staff', [StaffController::class, 'index']);
        Route::post('/staff', [StaffController::class, 'store']);
        Route::patch('/staff/{id}', [StaffController::class, 'update'])->whereNumber('id');

        Route::get('/dashboard', [DashboardController::class, 'show']);

        Route::get('/room-types', [RoomTypeAdminController::class, 'index']);
        Route::post('/room-types', [RoomTypeAdminController::class, 'store']);
        Route::patch('/room-types/{id}', [RoomTypeAdminController::class, 'update'])->whereNumber('id');
        Route::delete('/room-types/{id}', [RoomTypeAdminController::class, 'destroy'])->whereNumber('id');

        Route::post('/rooms', [RoomAdminController::class, 'store']);
        Route::patch('/rooms/{id}', [RoomAdminController::class, 'update'])->whereNumber('id');
        Route::delete('/rooms/{id}', [RoomAdminController::class, 'destroy'])->whereNumber('id');

        Route::post('/maintenance/run', [MaintenanceController::class, 'run'])->middleware('throttle:10,1');

        Route::get('/settings', [SettingsController::class, 'show']);
        Route::put('/settings', [SettingsController::class, 'update']);
    });
});
