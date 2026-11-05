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
Route::get('/room-types/{roomType}', [RoomTypeController::class, 'show'])->where('roomType', '[0-9]{1,9}');

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
    // Only guests edit their own name and phone. Staff and admin accounts are managed by the admin.
    Route::patch('/auth/profile', [AuthController::class, 'updateProfile'])->middleware('role:customer');
    Route::post('/auth/change-password', [AuthController::class, 'changePassword'])->middleware('throttle:5,1');

    Route::prefix('bookings')->group(function () {
        Route::get('/', [BookingController::class, 'index']);
        Route::post('/', [BookingController::class, 'store'])->middleware('throttle:20,1');
        Route::post('/{id}/cancel', [BookingController::class, 'cancel'])->where('id', '[0-9]{1,9}')->middleware('throttle:20,1');
        Route::get('/{id}', [BookingController::class, 'show'])->where('id', '[0-9]{1,9}');
        Route::post('/{id}/release', [BookingController::class, 'release'])->where('id', '[0-9]{1,9}');
        Route::delete('/{id}', [BookingController::class, 'destroy'])->where('id', '[0-9]{1,9}')->middleware('throttle:20,1');
        Route::post('/{id}/pay-at-hotel', [BookingController::class, 'payAtHotel'])->where('id', '[0-9]{1,9}');

        // Pay online (simulated): a card, or a QR code. The server checks every payment in the database.
        Route::post('/{id}/pay-card', [OnlinePaymentController::class, 'payByCard'])->where('id', '[0-9]{1,9}')->middleware('throttle:20,1');
        Route::post('/{id}/pay-qr', [OnlinePaymentController::class, 'startQr'])->where('id', '[0-9]{1,9}')->middleware('throttle:20,1');
        Route::post('/{id}/verify-payment', [OnlinePaymentController::class, 'verify'])->where('id', '[0-9]{1,9}')->middleware('throttle:30,1');
    });

    // Staff and admin: bookings, payment at the hotel, check-in and check-out.
    Route::prefix('staff/bookings')->middleware('role:staff,admin')->group(function () {
        Route::get('/', [StaffBookingController::class, 'index']);
        Route::get('/{id}', [StaffBookingController::class, 'show'])->where('id', '[0-9]{1,9}');
        Route::post('/{id}/payments', [StaffBookingController::class, 'takePayment'])->where('id', '[0-9]{1,9}');
        Route::post('/{id}/check-in', [StaffBookingController::class, 'checkIn'])->where('id', '[0-9]{1,9}');
        Route::post('/{id}/check-out', [StaffBookingController::class, 'checkOut'])->where('id', '[0-9]{1,9}');
    });

    // Admin only.
    Route::prefix('admin')->middleware('role:admin')->group(function () {
        Route::get('/staff', [StaffController::class, 'index']);
        Route::post('/staff', [StaffController::class, 'store']);
        Route::patch('/staff/{id}', [StaffController::class, 'update'])->where('id', '[0-9]{1,9}');

        Route::get('/dashboard', [DashboardController::class, 'show']);

        Route::get('/room-types', [RoomTypeAdminController::class, 'index']);
        Route::post('/room-types', [RoomTypeAdminController::class, 'store']);
        Route::patch('/room-types/{id}', [RoomTypeAdminController::class, 'update'])->where('id', '[0-9]{1,9}');
        Route::delete('/room-types/{id}', [RoomTypeAdminController::class, 'destroy'])->where('id', '[0-9]{1,9}');

        Route::post('/rooms', [RoomAdminController::class, 'store']);
        Route::patch('/rooms/{id}', [RoomAdminController::class, 'update'])->where('id', '[0-9]{1,9}');
        Route::delete('/rooms/{id}', [RoomAdminController::class, 'destroy'])->where('id', '[0-9]{1,9}');

        Route::post('/maintenance/run', [MaintenanceController::class, 'run'])->middleware('throttle:10,1');

        Route::get('/settings', [SettingsController::class, 'show']);
        Route::put('/settings', [SettingsController::class, 'update']);
    });
});
