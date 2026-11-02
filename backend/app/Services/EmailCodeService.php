<?php

namespace App\Services;

use App\Mail\VerificationCodeMail;
use App\Models\EmailCode;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Mail;

class EmailCodeService
{
    public const PURPOSE_VERIFY = 'verify';
    public const PURPOSE_RESET = 'reset';

    private const LIFETIME_MINUTES = 10;
    private const MAX_ATTEMPTS = 5;
    private const RESEND_AFTER_SECONDS = 60;

    /**
     * Make a new 6-digit code and email it.
     * Returns false when a code was sent less than a minute ago.
     */
    public function issue(string $email, string $purpose): bool
    {
        $last = EmailCode::where('email', $email)
            ->where('purpose', $purpose)
            ->latest('id')
            ->first();

        if ($last && $last->created_at->gt(now()->subSeconds(self::RESEND_AFTER_SECONDS))) {
            return false;
        }

        EmailCode::where('email', $email)->where('purpose', $purpose)->delete();

        $code = str_pad((string) random_int(0, 999999), 6, '0', STR_PAD_LEFT);

        EmailCode::create([
            'email' => $email,
            'purpose' => $purpose,
            'code_hash' => Hash::make($code),
            'expires_at' => now()->addMinutes(self::LIFETIME_MINUTES),
        ]);

        Mail::to($email)->send(new VerificationCodeMail($code, $purpose, self::LIFETIME_MINUTES));

        return true;
    }

    /**
     * Check a code. A right code is used up. A wrong code counts as an
     * attempt, and after 5 attempts the code is dead.
     */
    public function check(string $email, string $purpose, string $code): bool
    {
        $record = EmailCode::where('email', $email)
            ->where('purpose', $purpose)
            ->latest('id')
            ->first();

        if (! $record || $record->expires_at->isPast() || $record->attempts >= self::MAX_ATTEMPTS) {
            return false;
        }

        if (! Hash::check($code, $record->code_hash)) {
            $record->increment('attempts');

            return false;
        }

        return true;
    }

    /**
     * Same as check(), but a right code is used up so it works only once.
     */
    public function verify(string $email, string $purpose, string $code): bool
    {
        if (! $this->check($email, $purpose, $code)) {
            return false;
        }

        EmailCode::where('email', $email)->where('purpose', $purpose)->delete();

        return true;
    }
}
