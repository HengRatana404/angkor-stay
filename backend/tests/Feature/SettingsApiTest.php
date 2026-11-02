<?php

namespace Tests\Feature;

use App\Models\Setting;
use App\Services\SettingsService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\MakesUsers;
use Tests\TestCase;

class SettingsApiTest extends TestCase
{
    use MakesUsers;
    use RefreshDatabase;

    private function asAdmin(): void
    {
        Sanctum::actingAs($this->makeUser('admin'));
    }

    private function valid(array $override = []): array
    {
        return array_merge([
            'online_discount_percent' => 20,
            'check_in_time' => '15:00',
            'check_out_time' => '11:00',
            'staff_login_restricted' => true,
            'allowed_networks' => ['127.0.0.1/32', '192.168.123.0/24'],
            'demo_payment_mode' => true,
        ], $override);
    }

    public function test_the_defaults_are_shown_before_anything_is_saved(): void
    {
        $this->asAdmin();

        $this->getJson('/api/admin/settings')
            ->assertOk()
            ->assertJsonPath('data.online_discount_percent', 15)
            ->assertJsonPath('data.check_in_time', '14:00')
            ->assertJsonPath('data.check_out_time', '12:00')
            ->assertJsonPath('data.staff_login_restricted', true)
            ->assertJsonPath('data.demo_payment_mode', false)
            ->assertJsonPath('your_ip', '127.0.0.1')
            ->assertJsonStructure(['data' => ['allowed_networks']]);
    }

    public function test_the_admin_can_save_every_setting(): void
    {
        $this->asAdmin();

        $this->putJson('/api/admin/settings', $this->valid())
            ->assertOk()
            ->assertJsonPath('data.online_discount_percent', 20)
            ->assertJsonPath('data.check_in_time', '15:00')
            ->assertJsonPath('data.check_out_time', '11:00')
            ->assertJsonPath('data.demo_payment_mode', true)
            ->assertJsonPath('data.allowed_networks', ['127.0.0.1/32', '192.168.123.0/24']);

        // And it is still there on the next visit.
        $this->getJson('/api/admin/settings')
            ->assertOk()
            ->assertJsonPath('data.online_discount_percent', 20)
            ->assertJsonPath('data.demo_payment_mode', true);
    }

    public function test_saved_values_keep_their_type(): void
    {
        $this->asAdmin();
        $this->putJson('/api/admin/settings', $this->valid(['online_discount_percent' => '25', 'demo_payment_mode' => 0]))->assertOk();

        $data = $this->getJson('/api/admin/settings')->json('data');

        $this->assertSame(25, $data['online_discount_percent']);
        $this->assertFalse($data['demo_payment_mode']);
        $this->assertTrue($data['staff_login_restricted']);
    }

    public function test_saving_twice_updates_the_same_rows(): void
    {
        $this->asAdmin();

        $this->putJson('/api/admin/settings', $this->valid())->assertOk();
        $rows = Setting::count();
        $this->putJson('/api/admin/settings', $this->valid(['online_discount_percent' => 10]))->assertOk();

        $this->assertSame($rows, Setting::count());
        $this->assertSame(10, app(SettingsService::class)->get('online_discount_percent'));
    }

    public function test_a_setting_with_no_saved_row_falls_back_to_the_default(): void
    {
        Setting::create(['key' => 'online_discount_percent', 'value' => json_encode(30)]);
        $this->asAdmin();

        $data = $this->getJson('/api/admin/settings')->json('data');

        $this->assertSame(30, $data['online_discount_percent']);
        $this->assertSame('14:00', $data['check_in_time']);
    }

    public function test_the_discount_must_be_a_whole_number_from_0_to_50(): void
    {
        $this->asAdmin();

        foreach ([-1, 51, 100, 'abc', 15.5, null, ''] as $bad) {
            $this->putJson('/api/admin/settings', $this->valid(['online_discount_percent' => $bad]))
                ->assertStatus(422)->assertJsonValidationErrors(['online_discount_percent']);
        }

        foreach ([0, 50, 15] as $good) {
            $this->putJson('/api/admin/settings', $this->valid(['online_discount_percent' => $good]))->assertOk();
        }
    }

    public function test_times_must_look_like_hh_mm(): void
    {
        $this->asAdmin();

        foreach (['25:00', '2pm', 'noon', '14:60', '1400', ''] as $bad) {
            $this->putJson('/api/admin/settings', $this->valid(['check_in_time' => $bad]))
                ->assertStatus(422)->assertJsonValidationErrors(['check_in_time']);
            $this->putJson('/api/admin/settings', $this->valid(['check_out_time' => $bad]))
                ->assertStatus(422)->assertJsonValidationErrors(['check_out_time']);
        }

        $this->putJson('/api/admin/settings', $this->valid(['check_in_time' => '00:00', 'check_out_time' => '23:59']))->assertOk();
    }

    public function test_every_field_is_required(): void
    {
        $this->asAdmin();

        $this->putJson('/api/admin/settings', [])
            ->assertStatus(422)
            ->assertJsonValidationErrors([
                'online_discount_percent', 'check_in_time', 'check_out_time',
                'staff_login_restricted', 'allowed_networks', 'demo_payment_mode',
            ]);
    }

    public function test_networks_must_be_real_networks(): void
    {
        $this->asAdmin();

        foreach (['banana', '999.1.1.1', '192.168.1.0/33', '1.2.3', '192.168.1.0/ab'] as $bad) {
            $this->putJson('/api/admin/settings', $this->valid(['allowed_networks' => ['127.0.0.1/32', $bad]]))
                ->assertStatus(422)
                ->assertJsonValidationErrors(['allowed_networks.1']);
        }
    }

    public function test_there_must_be_at_least_one_network_and_not_too_many(): void
    {
        $this->asAdmin();

        $this->putJson('/api/admin/settings', $this->valid(['allowed_networks' => []]))
            ->assertStatus(422)->assertJsonValidationErrors(['allowed_networks']);

        $this->putJson('/api/admin/settings', $this->valid(['allowed_networks' => ['', '   ']]))
            ->assertStatus(422)->assertJsonValidationErrors(['allowed_networks']);

        $many = array_map(fn ($i) => "10.{$i}.0.0/16", range(1, 21));
        $this->putJson('/api/admin/settings', $this->valid(['allowed_networks' => array_merge(['127.0.0.1'], $many)]))
            ->assertStatus(422)->assertJsonValidationErrors(['allowed_networks']);
    }

    public function test_networks_are_cleaned_before_saving(): void
    {
        $this->asAdmin();

        $this->putJson('/api/admin/settings', $this->valid([
            'allowed_networks' => [' 127.0.0.1 ', '192.168.5.0/24', '192.168.5.0/24', '', '10.0.0.7'],
        ]))
            ->assertOk()
            ->assertJsonPath('data.allowed_networks', ['127.0.0.1/32', '192.168.5.0/24', '10.0.0.7/32']);
    }

    // ------------------------------------------------------ lock-out guard

    public function test_the_admin_cannot_save_a_network_that_would_lock_them_out(): void
    {
        $this->asAdmin();

        $this->putJson('/api/admin/settings', $this->valid(['allowed_networks' => ['192.168.77.0/24']]))
            ->assertStatus(422)
            ->assertJsonValidationErrors(['allowed_networks']);

        $message = $this->putJson('/api/admin/settings', $this->valid(['allowed_networks' => ['192.168.77.0/24']]))
            ->json('errors.allowed_networks.0');
        $this->assertStringContainsString('lock yourself out', $message);
        $this->assertStringContainsString('127.0.0.1', $message);

        // Nothing was saved.
        $this->assertSame(0, Setting::count());
    }

    public function test_the_guard_lets_the_admin_save_a_network_that_includes_their_device(): void
    {
        $this->asAdmin();

        $this->fromIp('192.168.77.20')
            ->putJson('/api/admin/settings', $this->valid(['allowed_networks' => ['192.168.77.0/24']]))
            ->assertOk();
    }

    public function test_the_guard_is_skipped_when_the_rule_is_switched_off(): void
    {
        $this->asAdmin();

        $this->putJson('/api/admin/settings', $this->valid([
            'staff_login_restricted' => false,
            'allowed_networks' => ['192.168.77.0/24'],
        ]))->assertOk();
    }

    public function test_a_forged_header_does_not_fool_the_guard(): void
    {
        $this->asAdmin();

        $this->withHeaders(['X-Forwarded-For' => '192.168.77.20'])
            ->putJson('/api/admin/settings', $this->valid(['allowed_networks' => ['192.168.77.0/24']]))
            ->assertStatus(422);
    }

    // ---------------------------------------------------- settings are used

    public function test_saving_the_network_changes_who_can_log_in(): void
    {
        $staff = $this->makeUser('staff');
        $this->asAdmin();

        $this->fromIp('192.168.77.20')
            ->putJson('/api/admin/settings', $this->valid(['allowed_networks' => ['192.168.77.0/24']]))
            ->assertOk();

        $this->app['auth']->forgetGuards();
        $this->fromIp('192.168.77.5')->postJson('/api/auth/login', ['email' => $staff->email, 'password' => 'secret1234'])->assertOk();
        $this->fromIp('192.168.78.5')->postJson('/api/auth/login', ['email' => $staff->email, 'password' => 'secret1234'])->assertStatus(403);
    }

    public function test_switching_the_rule_off_in_the_app_lets_staff_in_from_anywhere(): void
    {
        $staff = $this->makeUser('staff');
        $this->asAdmin();

        $this->putJson('/api/admin/settings', $this->valid(['staff_login_restricted' => false]))->assertOk();

        $this->app['auth']->forgetGuards();
        $this->fromIp('8.8.8.8')->postJson('/api/auth/login', ['email' => $staff->email, 'password' => 'secret1234'])->assertOk();
    }
}
