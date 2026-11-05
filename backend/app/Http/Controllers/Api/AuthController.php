<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\Auth\ChangePasswordRequest;
use App\Http\Requests\Auth\EmailRequest;
use App\Http\Requests\Auth\UpdateProfileRequest;
use App\Http\Requests\Auth\LoginRequest;
use App\Http\Requests\Auth\RegisterRequest;
use App\Http\Requests\Auth\ResetPasswordRequest;
use App\Http\Requests\Auth\VerifyCodeRequest;
use App\Http\Resources\UserResource;
use App\Models\User;
use App\Services\EmailCodeService;
use App\Services\SettingsService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;

class AuthController extends Controller
{
    public function __construct(
        private EmailCodeService $codes,
        private SettingsService $settings,
    ) {
    }

    public function register(RegisterRequest $request): JsonResponse
    {
        $data = $request->validated();

        // An unverified account with the same email is simply updated.
        // Role is never taken from the request: new accounts are customers.
        $user = User::updateOrCreate(
            ['email' => $data['email']],
            [
                'name' => $data['name'],
                'phone' => $data['phone'],
                'password' => $data['password'],
            ],
        );

        $this->codes->issue($user->email, EmailCodeService::PURPOSE_VERIFY);

        return response()->json([
            'message' => 'We sent a 6-digit code to your email.',
            'email' => $user->email,
        ], 201);
    }

    public function verifyEmail(VerifyCodeRequest $request): JsonResponse
    {
        $user = User::where('email', $request->email)
            ->whereNull('email_verified_at')
            ->first();

        if (! $user || ! $this->codes->verify($user->email, EmailCodeService::PURPOSE_VERIFY, $request->code)) {
            return response()->json(['message' => 'The code is wrong or has expired.'], 422);
        }

        $user->forceFill(['email_verified_at' => now()])->save();

        return response()->json([
            'token' => $user->createToken('mobile')->plainTextToken,
            'user' => new UserResource($user),
        ]);
    }

    public function resendCode(EmailRequest $request): JsonResponse
    {
        $user = User::where('email', $request->email)
            ->whereNull('email_verified_at')
            ->first();

        if ($user && ! $this->codes->issue($user->email, EmailCodeService::PURPOSE_VERIFY)) {
            return response()->json(['message' => 'Please wait a minute before asking for a new code.'], 429);
        }

        // Same answer whether or not the email exists, so nobody can probe accounts.
        return response()->json(['message' => 'If the email needs a code, we sent a new one.']);
    }

    public function forgotPassword(EmailRequest $request): JsonResponse
    {
        $user = User::where('email', $request->email)
            ->whereNotNull('email_verified_at')
            ->first();

        // Staff and admin have no real inbox: the admin sets a new password for them.
        if ($user && $user->is_active && $user->role === 'customer') {
            // If a code was sent a minute ago this does nothing, quietly.
            $this->codes->issue($user->email, EmailCodeService::PURPOSE_RESET);
        }

        // Same answer for every email, so nobody can probe which emails have accounts.
        return response()->json(['message' => 'If this email has an account, we sent a 6-digit code.']);
    }

    public function checkResetCode(VerifyCodeRequest $request): JsonResponse
    {
        if (! $this->codes->check($request->email, EmailCodeService::PURPOSE_RESET, $request->code)) {
            return response()->json(['message' => 'The code is wrong or has expired.'], 422);
        }

        return response()->json(['message' => 'Code is correct.']);
    }

    public function resetPassword(ResetPasswordRequest $request): JsonResponse
    {
        $user = User::where('email', $request->email)
            ->whereNotNull('email_verified_at')
            ->first();

        if (! $user || ! $this->codes->verify($user->email, EmailCodeService::PURPOSE_RESET, $request->code)) {
            return response()->json(['message' => 'The code is wrong or has expired.'], 422);
        }

        $user->forceFill(['password' => $request->password])->save();

        // Anyone logged in with the old password is logged out everywhere.
        $user->tokens()->delete();

        return response()->json(['message' => 'Your password was changed. Please log in.']);
    }

    public function login(LoginRequest $request): JsonResponse
    {
        $user = User::where('email', $request->email)->first();

        if (! $user || ! Hash::check($request->password, $user->password)) {
            return response()->json(['message' => 'The email or password is wrong.'], 422);
        }

        if (! $user->email_verified_at) {
            return response()->json([
                'message' => 'Please verify your email first.',
                'code' => 'email_not_verified',
            ], 403);
        }

        if (! $user->is_active) {
            return response()->json(['message' => 'This account is disabled.'], 403);
        }

        // Staff and admin can only log in from the hotel network. This is checked
        // after the password, so the message is not shown to someone guessing.
        if (! $this->settings->mayConnectFrom($user, $this->settings->effectiveIp($request))) {
            return response()->json([
                'message' => 'Staff and admin can only log in on the hotel network.',
                'code' => 'outside_hotel_network',
            ], 403);
        }

        return response()->json([
            'token' => $user->createToken('mobile')->plainTextToken,
            'user' => new UserResource($user),
        ]);
    }

    public function logout(Request $request): JsonResponse
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json(['message' => 'Logged out.']);
    }

    public function me(Request $request): UserResource
    {
        return new UserResource($request->user());
    }

    /** Name and phone only. Email and role are never taken from the request. */
    public function updateProfile(UpdateProfileRequest $request): UserResource
    {
        $user = $request->user();
        $user->fill($request->safe()->only(['name', 'phone']))->save();

        return new UserResource($user);
    }

    /** A new password logs the guest out everywhere else, but not on this phone. */
    public function changePassword(ChangePasswordRequest $request): JsonResponse
    {
        $user = $request->user();
        $user->forceFill(['password' => $request->input('password')])->save();

        $user->tokens()->where('id', '!=', $user->currentAccessToken()->id)->delete();

        return response()->json(['message' => 'Your password was changed.']);
    }
}
