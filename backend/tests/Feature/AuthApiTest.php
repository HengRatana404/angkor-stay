<?php

namespace Tests\Feature;

use App\Mail\VerificationCodeMail;
use App\Models\EmailCode;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Mail;
use Tests\TestCase;

class AuthApiTest extends TestCase
{
    use RefreshDatabase;

    private function registerPayload(array $override = []): array
    {
        return array_merge([
            'name' => 'Sok Dara',
            'email' => 'dara@example.com',
            'phone' => '012345678',
            'password' => 'secret1234',
            'password_confirmation' => 'secret1234',
        ], $override);
    }

    private function sentCode(): string
    {
        $mails = Mail::sent(VerificationCodeMail::class);

        return $mails->last()->code;
    }

    private function registerAndVerify(array $override = []): array
    {
        $payload = $this->registerPayload($override);
        $this->postJson('/api/auth/register', $payload)->assertCreated();

        return $this->postJson('/api/auth/verify-email', [
            'email' => $payload['email'],
            'code' => $this->sentCode(),
        ])->assertOk()->json();
    }

    public function test_register_creates_unverified_customer_and_emails_a_code(): void
    {
        Mail::fake();

        $this->postJson('/api/auth/register', $this->registerPayload())
            ->assertCreated()
            ->assertJsonPath('email', 'dara@example.com');

        $user = User::where('email', 'dara@example.com')->first();
        $this->assertNull($user->email_verified_at);
        $this->assertSame('customer', $user->role);
        Mail::assertSent(VerificationCodeMail::class, 1);
        $this->assertMatchesRegularExpression('/^\d{6}$/', $this->sentCode());
    }

    public function test_register_cannot_pick_its_own_role(): void
    {
        Mail::fake();

        $this->postJson('/api/auth/register', $this->registerPayload(['role' => 'admin']))
            ->assertCreated();

        $this->assertSame('customer', User::first()->role);
    }

    public function test_register_validates_input(): void
    {
        $this->postJson('/api/auth/register', [])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['name', 'email', 'phone', 'password']);

        $this->postJson('/api/auth/register', $this->registerPayload(['password_confirmation' => 'other']))
            ->assertStatus(422)
            ->assertJsonValidationErrors(['password']);

        $this->postJson('/api/auth/register', $this->registerPayload(['password' => 'short', 'password_confirmation' => 'short']))
            ->assertStatus(422)
            ->assertJsonValidationErrors(['password']);
    }

    public function test_verified_email_cannot_register_again(): void
    {
        Mail::fake();
        $this->registerAndVerify();

        $this->postJson('/api/auth/register', $this->registerPayload())
            ->assertStatus(422)
            ->assertJsonValidationErrors(['email']);
    }

    public function test_unverified_email_can_register_again(): void
    {
        Mail::fake();
        $this->postJson('/api/auth/register', $this->registerPayload())->assertCreated();
        $this->travel(2)->minutes();

        $this->postJson('/api/auth/register', $this->registerPayload(['name' => 'New Name']))
            ->assertCreated();

        $this->assertSame(1, User::count());
        $this->assertSame('New Name', User::first()->name);
    }

    public function test_right_code_verifies_and_returns_a_working_token(): void
    {
        Mail::fake();
        $result = $this->registerAndVerify();

        $this->assertNotEmpty($result['token']);
        $this->assertTrue($result['user']['email_verified']);
        $this->assertNotNull(User::first()->email_verified_at);

        $this->withToken($result['token'])
            ->getJson('/api/auth/me')
            ->assertOk()
            ->assertJsonPath('data.email', 'dara@example.com');
    }

    public function test_wrong_code_is_rejected(): void
    {
        Mail::fake();
        $this->postJson('/api/auth/register', $this->registerPayload())->assertCreated();
        $wrong = $this->sentCode() === '000000' ? '111111' : '000000';

        $this->postJson('/api/auth/verify-email', ['email' => 'dara@example.com', 'code' => $wrong])
            ->assertStatus(422)
            ->assertJsonPath('message', 'The code is wrong or has expired.');

        $this->assertNull(User::first()->email_verified_at);
    }

    public function test_expired_code_is_rejected(): void
    {
        Mail::fake();
        $this->postJson('/api/auth/register', $this->registerPayload())->assertCreated();
        $code = $this->sentCode();

        $this->travel(11)->minutes();

        $this->postJson('/api/auth/verify-email', ['email' => 'dara@example.com', 'code' => $code])
            ->assertStatus(422);
    }

    public function test_code_dies_after_five_wrong_tries(): void
    {
        Mail::fake();
        $this->postJson('/api/auth/register', $this->registerPayload())->assertCreated();
        $code = $this->sentCode();
        $wrong = $code === '000000' ? '111111' : '000000';

        // Throttle is 10 per minute, so 5 wrong tries fit.
        for ($i = 0; $i < 5; $i++) {
            $this->postJson('/api/auth/verify-email', ['email' => 'dara@example.com', 'code' => $wrong])
                ->assertStatus(422);
        }

        $this->postJson('/api/auth/verify-email', ['email' => 'dara@example.com', 'code' => $code])
            ->assertStatus(422);
    }

    public function test_code_is_stored_hashed_and_used_only_once(): void
    {
        Mail::fake();
        $this->postJson('/api/auth/register', $this->registerPayload())->assertCreated();
        $code = $this->sentCode();

        $this->assertNotSame($code, EmailCode::first()->code_hash);

        $this->postJson('/api/auth/verify-email', ['email' => 'dara@example.com', 'code' => $code])->assertOk();
        $this->postJson('/api/auth/verify-email', ['email' => 'dara@example.com', 'code' => $code])->assertStatus(422);
    }

    public function test_resend_code_is_limited_to_once_a_minute(): void
    {
        Mail::fake();
        $this->postJson('/api/auth/register', $this->registerPayload())->assertCreated();

        $this->postJson('/api/auth/resend-code', ['email' => 'dara@example.com'])->assertStatus(429);

        $this->travel(61)->seconds();

        $this->postJson('/api/auth/resend-code', ['email' => 'dara@example.com'])->assertOk();
        Mail::assertSent(VerificationCodeMail::class, 2);
    }

    public function test_resend_does_not_reveal_unknown_emails(): void
    {
        Mail::fake();

        $this->postJson('/api/auth/resend-code', ['email' => 'nobody@example.com'])->assertOk();
        Mail::assertNothingSent();
    }

    public function test_login_works_after_verification(): void
    {
        Mail::fake();
        $this->registerAndVerify();

        $this->postJson('/api/auth/login', ['email' => 'dara@example.com', 'password' => 'secret1234'])
            ->assertOk()
            ->assertJsonStructure(['token', 'user' => ['id', 'name', 'email', 'phone', 'role']]);
    }

    public function test_login_is_blocked_before_verification(): void
    {
        Mail::fake();
        $this->postJson('/api/auth/register', $this->registerPayload())->assertCreated();

        $this->postJson('/api/auth/login', ['email' => 'dara@example.com', 'password' => 'secret1234'])
            ->assertStatus(403)
            ->assertJsonPath('code', 'email_not_verified');
    }

    public function test_login_rejects_wrong_password_and_unknown_email_the_same_way(): void
    {
        Mail::fake();
        $this->registerAndVerify();

        $wrongPassword = $this->postJson('/api/auth/login', ['email' => 'dara@example.com', 'password' => 'nope-nope'])
            ->assertStatus(422)->json('message');
        $unknownEmail = $this->postJson('/api/auth/login', ['email' => 'x@example.com', 'password' => 'nope-nope'])
            ->assertStatus(422)->json('message');

        $this->assertSame($wrongPassword, $unknownEmail);
    }

    public function test_disabled_account_cannot_log_in(): void
    {
        Mail::fake();
        $this->registerAndVerify();
        User::first()->forceFill(['is_active' => false])->save();

        $this->postJson('/api/auth/login', ['email' => 'dara@example.com', 'password' => 'secret1234'])
            ->assertStatus(403);
    }

    public function test_logout_kills_the_token(): void
    {
        Mail::fake();
        $result = $this->registerAndVerify();

        $this->withToken($result['token'])->postJson('/api/auth/logout')->assertOk();

        $this->assertDatabaseCount('personal_access_tokens', 0);
    }

    public function test_me_needs_a_token(): void
    {
        $this->getJson('/api/auth/me')->assertUnauthorized();
    }
}
