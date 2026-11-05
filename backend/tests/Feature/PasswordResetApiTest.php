<?php

namespace Tests\Feature;

use App\Mail\VerificationCodeMail;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Mail;
use Tests\TestCase;

class PasswordResetApiTest extends TestCase
{
    use RefreshDatabase;

    private function verifiedUser(): User
    {
        $user = User::create([
            'name' => 'Sok Dara',
            'email' => 'dara@example.com',
            'phone' => '012345678',
            'password' => 'old-password-1',
        ]);
        $user->forceFill(['email_verified_at' => now()])->save();

        return $user;
    }

    private function resetCode(): string
    {
        return Mail::sent(VerificationCodeMail::class)->last()->code;
    }

    private function wrongCodeFor(string $code): string
    {
        return $code === '000000' ? '111111' : '000000';
    }

    public function test_staff_and_admin_get_no_reset_code_the_admin_resets_for_them(): void
    {
        Mail::fake();

        foreach (['staff', 'admin'] as $role) {
            $user = $this->verifiedUser();
            $user->forceFill(['role' => $role])->save();

            $this->postJson('/api/auth/forgot-password', ['email' => $user->email])
                ->assertOk()
                ->assertJsonPath('message', 'If this email has an account, we sent a 6-digit code.');

            $user->delete();
        }

        Mail::assertNothingSent();
    }

    public function test_forgot_password_emails_a_reset_code(): void
    {
        Mail::fake();
        $this->verifiedUser();

        $this->postJson('/api/auth/forgot-password', ['email' => 'dara@example.com'])->assertOk();

        Mail::assertSent(VerificationCodeMail::class, fn ($m) => $m->purpose === 'reset');
        $this->assertMatchesRegularExpression('/^\d{6}$/', $this->resetCode());
    }

    public function test_forgot_password_answers_the_same_for_unknown_emails(): void
    {
        Mail::fake();
        $this->verifiedUser();

        $known = $this->postJson('/api/auth/forgot-password', ['email' => 'dara@example.com'])->assertOk()->json();
        $unknown = $this->postJson('/api/auth/forgot-password', ['email' => 'nobody@example.com'])->assertOk()->json();

        $this->assertSame($known, $unknown);
        Mail::assertSent(VerificationCodeMail::class, 1);
    }

    public function test_forgot_password_sends_nothing_to_unverified_or_disabled_accounts(): void
    {
        Mail::fake();
        User::create(['name' => 'New', 'email' => 'new@example.com', 'phone' => '099999999', 'password' => 'secret1234']);
        $this->verifiedUser()->forceFill(['is_active' => false])->save();

        $this->postJson('/api/auth/forgot-password', ['email' => 'new@example.com'])->assertOk();
        $this->postJson('/api/auth/forgot-password', ['email' => 'dara@example.com'])->assertOk();

        Mail::assertNothingSent();
    }

    public function test_check_reset_code_accepts_the_right_code_without_using_it_up(): void
    {
        Mail::fake();
        $this->verifiedUser();
        $this->postJson('/api/auth/forgot-password', ['email' => 'dara@example.com'])->assertOk();
        $code = $this->resetCode();

        $this->postJson('/api/auth/check-reset-code', ['email' => 'dara@example.com', 'code' => $code])->assertOk();
        $this->postJson('/api/auth/check-reset-code', ['email' => 'dara@example.com', 'code' => $code])->assertOk();
    }

    public function test_check_reset_code_rejects_a_wrong_code(): void
    {
        Mail::fake();
        $this->verifiedUser();
        $this->postJson('/api/auth/forgot-password', ['email' => 'dara@example.com'])->assertOk();

        $this->postJson('/api/auth/check-reset-code', [
            'email' => 'dara@example.com',
            'code' => $this->wrongCodeFor($this->resetCode()),
        ])->assertStatus(422)->assertJsonPath('message', 'The code is wrong or has expired.');
    }

    public function test_reset_password_changes_the_password(): void
    {
        Mail::fake();
        $this->verifiedUser();
        $this->postJson('/api/auth/forgot-password', ['email' => 'dara@example.com'])->assertOk();

        $this->postJson('/api/auth/reset-password', [
            'email' => 'dara@example.com',
            'code' => $this->resetCode(),
            'password' => 'new-password-2',
            'password_confirmation' => 'new-password-2',
        ])->assertOk();

        $this->assertTrue(Hash::check('new-password-2', User::first()->password));

        $this->postJson('/api/auth/login', ['email' => 'dara@example.com', 'password' => 'old-password-1'])
            ->assertStatus(422);
        $this->postJson('/api/auth/login', ['email' => 'dara@example.com', 'password' => 'new-password-2'])
            ->assertOk();
    }

    public function test_reset_code_works_only_once(): void
    {
        Mail::fake();
        $this->verifiedUser();
        $this->postJson('/api/auth/forgot-password', ['email' => 'dara@example.com'])->assertOk();
        $code = $this->resetCode();
        $payload = [
            'email' => 'dara@example.com',
            'code' => $code,
            'password' => 'new-password-2',
            'password_confirmation' => 'new-password-2',
        ];

        $this->postJson('/api/auth/reset-password', $payload)->assertOk();
        $this->postJson('/api/auth/reset-password', $payload)->assertStatus(422);
    }

    public function test_reset_password_rejects_wrong_code_and_keeps_old_password(): void
    {
        Mail::fake();
        $this->verifiedUser();
        $this->postJson('/api/auth/forgot-password', ['email' => 'dara@example.com'])->assertOk();

        $this->postJson('/api/auth/reset-password', [
            'email' => 'dara@example.com',
            'code' => $this->wrongCodeFor($this->resetCode()),
            'password' => 'new-password-2',
            'password_confirmation' => 'new-password-2',
        ])->assertStatus(422);

        $this->assertTrue(Hash::check('old-password-1', User::first()->password));
    }

    public function test_reset_password_needs_matching_confirmation_and_a_strong_enough_password(): void
    {
        Mail::fake();
        $this->verifiedUser();
        $this->postJson('/api/auth/forgot-password', ['email' => 'dara@example.com'])->assertOk();
        $code = $this->resetCode();

        $this->postJson('/api/auth/reset-password', [
            'email' => 'dara@example.com', 'code' => $code,
            'password' => 'new-password-2', 'password_confirmation' => 'different-3',
        ])->assertStatus(422)->assertJsonValidationErrors(['password']);

        $this->postJson('/api/auth/reset-password', [
            'email' => 'dara@example.com', 'code' => $code,
            'password' => 'short', 'password_confirmation' => 'short',
        ])->assertStatus(422)->assertJsonValidationErrors(['password']);

        // The code was not used up by the failed tries above.
        $this->postJson('/api/auth/reset-password', [
            'email' => 'dara@example.com', 'code' => $code,
            'password' => 'new-password-2', 'password_confirmation' => 'new-password-2',
        ])->assertOk();
    }

    public function test_reset_code_cannot_be_used_to_verify_an_email_and_the_other_way_round(): void
    {
        Mail::fake();
        $this->verifiedUser();
        $this->postJson('/api/auth/forgot-password', ['email' => 'dara@example.com'])->assertOk();
        $resetCode = $this->resetCode();

        $this->postJson('/api/auth/verify-email', ['email' => 'dara@example.com', 'code' => $resetCode])
            ->assertStatus(422);
    }

    public function test_password_reset_logs_out_old_sessions(): void
    {
        Mail::fake();
        $user = $this->verifiedUser();
        $user->createToken('mobile');
        $this->assertDatabaseCount('personal_access_tokens', 1);

        $this->postJson('/api/auth/forgot-password', ['email' => 'dara@example.com'])->assertOk();
        $this->postJson('/api/auth/reset-password', [
            'email' => 'dara@example.com',
            'code' => $this->resetCode(),
            'password' => 'new-password-2',
            'password_confirmation' => 'new-password-2',
        ])->assertOk();

        $this->assertDatabaseCount('personal_access_tokens', 0);
    }
}
