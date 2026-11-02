<?php

namespace Tests\Feature;

use App\Services\SettingsService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\MakesUsers;
use Tests\TestCase;

class HotelNetworkTest extends TestCase
{
    use MakesUsers;
    use RefreshDatabase;

    private const OUTSIDE = '8.8.8.8';

    private function login(string $email, string $ip)
    {
        return $this->fromIp($ip)->postJson('/api/auth/login', ['email' => $email, 'password' => 'secret1234']);
    }

    private function settings(): SettingsService
    {
        return app(SettingsService::class);
    }

    // ------------------------------------------------------------------ login

    public function test_staff_can_log_in_from_the_hotel_network(): void
    {
        $staff = $this->makeUser('staff');

        $this->login($staff->email, '192.168.123.6')->assertOk()->assertJsonPath('user.role', 'staff');
        $this->login($staff->email, '127.0.0.1')->assertOk();
    }

    public function test_staff_cannot_log_in_from_the_public_internet(): void
    {
        $staff = $this->makeUser('staff');

        $this->login($staff->email, self::OUTSIDE)
            ->assertStatus(403)
            ->assertJsonPath('code', 'outside_hotel_network');

        $this->assertDatabaseCount('personal_access_tokens', 0);
    }

    public function test_admin_cannot_log_in_from_the_public_internet_either(): void
    {
        $admin = $this->makeUser('admin');

        $this->login($admin->email, self::OUTSIDE)->assertStatus(403)->assertJsonPath('code', 'outside_hotel_network');
    }

    public function test_customers_can_log_in_from_anywhere(): void
    {
        $customer = $this->makeUser('customer');

        $this->login($customer->email, self::OUTSIDE)->assertOk();
        $this->login($customer->email, '2001:db8::1')->assertOk();
    }

    public function test_a_wrong_password_from_outside_says_wrong_password_not_wrong_network(): void
    {
        $staff = $this->makeUser('staff');

        $this->fromIp(self::OUTSIDE)
            ->postJson('/api/auth/login', ['email' => $staff->email, 'password' => 'wrong-wrong'])
            ->assertStatus(422)
            ->assertJsonMissing(['code' => 'outside_hotel_network']);
    }

    public function test_the_rule_can_be_switched_off(): void
    {
        $staff = $this->makeUser('staff');
        $this->settings()->update(['staff_login_restricted' => false]);

        $this->login($staff->email, self::OUTSIDE)->assertOk();
    }

    // ------------------------------------------------------- which addresses

    public function test_the_default_covers_home_and_hotel_wifi_but_not_the_internet(): void
    {
        $staff = $this->makeUser('staff');

        foreach (['127.0.0.1', '::1', '192.168.123.6', '192.168.0.1', '10.1.2.3', '172.16.0.5', '172.20.1.1', '172.31.255.254'] as $ip) {
            $this->login($staff->email, $ip)->assertOk();
        }

        foreach (['8.8.8.8', '172.32.0.1', '172.15.255.255', '100.64.0.1', '1.1.1.1', '2001:db8::1'] as $ip) {
            $this->login($staff->email, $ip)->assertStatus(403);
        }
    }

    public function test_a_chosen_network_lets_in_only_that_network(): void
    {
        $staff = $this->makeUser('staff');
        $this->settings()->update(['allowed_networks' => ['192.168.123.0/24']]);

        $this->login($staff->email, '192.168.123.50')->assertOk();
        $this->login($staff->email, '192.168.123.255')->assertOk();
        $this->login($staff->email, '192.168.124.5')->assertStatus(403);
        $this->login($staff->email, '192.168.122.5')->assertStatus(403);
        $this->login($staff->email, '127.0.0.1')->assertStatus(403);
        $this->login($staff->email, '10.0.0.1')->assertStatus(403);
    }

    public function test_a_single_address_and_several_networks_work(): void
    {
        $staff = $this->makeUser('staff');
        $this->settings()->update(['allowed_networks' => ['203.0.113.7/32', '10.9.0.0/16']]);

        $this->login($staff->email, '203.0.113.7')->assertOk();
        $this->login($staff->email, '203.0.113.8')->assertStatus(403);
        $this->login($staff->email, '10.9.200.1')->assertOk();
        $this->login($staff->email, '10.10.0.1')->assertStatus(403);
    }

    public function test_ipv6_networks_work(): void
    {
        $staff = $this->makeUser('staff');
        $this->settings()->update(['allowed_networks' => ['2001:db8:abcd::/48']]);

        $this->login($staff->email, '2001:db8:abcd:1::5')->assertOk();
        $this->login($staff->email, '2001:db8:abce::5')->assertStatus(403);
    }

    public function test_a_forged_forwarding_header_cannot_get_around_the_rule(): void
    {
        $staff = $this->makeUser('staff');

        $this->fromIp(self::OUTSIDE)
            ->withHeaders([
                'X-Forwarded-For' => '127.0.0.1',
                'X-Real-IP' => '192.168.123.6',
                'Forwarded' => 'for=127.0.0.1',
                'Client-IP' => '127.0.0.1',
            ])
            ->postJson('/api/auth/login', ['email' => $staff->email, 'password' => 'secret1234'])
            ->assertStatus(403)
            ->assertJsonPath('code', 'outside_hotel_network');
    }

    // --------------------------------------------- an existing login token

    public function test_a_staff_token_stops_working_outside_the_hotel_network(): void
    {
        $staff = $this->makeUser('staff');
        $token = $staff->createToken('mobile')->plainTextToken;

        $this->fromIp('192.168.123.6')->withToken($token)->getJson('/api/auth/me')->assertOk();

        $this->fromIp(self::OUTSIDE)->withToken($token)->getJson('/api/auth/me')
            ->assertStatus(403)
            ->assertJsonPath('code', 'outside_hotel_network');

        // And it works again when the staff member is back.
        $this->fromIp('192.168.123.6')->withToken($token)->getJson('/api/auth/me')->assertOk();
    }

    public function test_an_admin_token_stops_working_outside_the_hotel_network(): void
    {
        $admin = $this->makeUser('admin');
        $token = $admin->createToken('mobile')->plainTextToken;

        $this->fromIp(self::OUTSIDE)->withToken($token)->getJson('/api/admin/staff')->assertStatus(403);
    }

    public function test_a_customer_token_works_from_anywhere(): void
    {
        $customer = $this->makeUser('customer');
        $token = $customer->createToken('mobile')->plainTextToken;

        $this->fromIp(self::OUTSIDE)->withToken($token)->getJson('/api/auth/me')->assertOk();
    }

    public function test_staff_outside_the_network_cannot_book_either(): void
    {
        Sanctum::actingAs($this->makeUser('staff'));

        $this->fromIp(self::OUTSIDE)->postJson('/api/bookings', [])->assertStatus(403)
            ->assertJsonPath('code', 'outside_hotel_network');
    }

    public function test_staff_can_always_log_out_even_outside_the_network(): void
    {
        $staff = $this->makeUser('staff');
        $token = $staff->createToken('mobile')->plainTextToken;

        $this->fromIp(self::OUTSIDE)->withToken($token)->postJson('/api/auth/logout')->assertOk();

        $this->assertDatabaseCount('personal_access_tokens', 0);
    }

    public function test_changing_the_rule_applies_to_logins_that_already_exist(): void
    {
        $staff = $this->makeUser('staff');
        $token = $staff->createToken('mobile')->plainTextToken;

        $this->fromIp(self::OUTSIDE)->withToken($token)->getJson('/api/auth/me')->assertStatus(403);

        $this->settings()->update(['staff_login_restricted' => false]);

        $this->fromIp(self::OUTSIDE)->withToken($token)->getJson('/api/auth/me')->assertOk();
    }

    // ----------------------------------------------------------- the helper

    public function test_networks_are_cleaned_up(): void
    {
        $this->assertSame('10.0.0.5/32', SettingsService::normalizeNetwork('10.0.0.5'));
        $this->assertSame('192.168.1.0/24', SettingsService::normalizeNetwork('  192.168.1.0/24 '));
        $this->assertSame('::1/128', SettingsService::normalizeNetwork('::1'));
        $this->assertSame('2001:db8::/32', SettingsService::normalizeNetwork('2001:db8::/32'));

        foreach (['', '  ', 'banana', '999.1.1.1', '192.168.1.0/33', '192.168.1.0/-1', '192.168.1.0/ab', '::1/129', '1.2.3'] as $bad) {
            $this->assertNull(SettingsService::normalizeNetwork($bad), "'{$bad}' should not be accepted");
        }
    }

    // ------------------------------------------------------- rescue command

    public function test_the_rescue_command_shows_and_changes_the_rule(): void
    {
        $this->artisan('hotel:network')->expectsOutputToContain('Rule is ON')->assertSuccessful();

        $this->artisan('hotel:network off')->expectsOutputToContain('Rule is OFF')->assertSuccessful();
        $this->assertFalse($this->settings()->isNetworkRestricted());

        $this->artisan('hotel:network on')->expectsOutputToContain('Rule is ON')->assertSuccessful();
        $this->assertTrue($this->settings()->isNetworkRestricted());
    }

    public function test_the_rescue_command_sets_networks_and_turns_the_rule_on(): void
    {
        $this->settings()->update(['staff_login_restricted' => false]);

        $this->artisan('hotel:network 192.168.5.0/24,10.0.0.9')->assertSuccessful();

        $this->assertTrue($this->settings()->isNetworkRestricted());
        $this->assertSame(['192.168.5.0/24', '10.0.0.9/32'], $this->settings()->allowedNetworks());
    }

    public function test_the_rescue_command_refuses_a_bad_network_and_changes_nothing(): void
    {
        $before = $this->settings()->allowedNetworks();

        $this->artisan('hotel:network banana')->assertFailed();

        $this->assertSame($before, $this->settings()->allowedNetworks());
    }
}
