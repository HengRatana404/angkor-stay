<?php

namespace Tests\Feature;

use App\Models\Setting;
use App\Services\LanAddress;
use App\Services\SettingsService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class ServerInfoTest extends TestCase
{
    use RefreshDatabase;

    private function fakeLan(?string $ip): void
    {
        $this->app->bind(LanAddress::class, fn () => new class($ip) extends LanAddress
        {
            public function __construct(private ?string $fake) {}

            public function detect(): ?string
            {
                return $this->fake;
            }
        });
    }

    public function test_it_is_off_when_no_key_is_set(): void
    {
        config(['hotel.server_info_key' => '']);

        $this->getJson('/api/server-info', ['X-Server-Key' => ''])->assertNotFound();
    }

    public function test_wrong_or_missing_key_gets_nothing(): void
    {
        config(['hotel.server_info_key' => 'secret-key']);
        $this->fakeLan('192.168.1.50');

        $this->getJson('/api/server-info')->assertNotFound();
        $this->getJson('/api/server-info', ['X-Server-Key' => 'nope'])
            ->assertNotFound()
            ->assertJsonMissingPath('lan_ip');
    }

    public function test_right_key_returns_the_address_and_saves_it(): void
    {
        config(['hotel.server_info_key' => 'secret-key', 'hotel.server_port' => 8000]);
        $this->fakeLan('192.168.1.50');

        $this->getJson('/api/server-info', ['X-Server-Key' => 'secret-key'])
            ->assertOk()
            ->assertJsonPath('lan_ip', '192.168.1.50')
            ->assertJsonPath('lan_url', 'http://192.168.1.50:8000/api');

        $this->assertSame('"192.168.1.50"', Setting::where('key', 'server_lan_ip')->value('value'));
    }

    public function test_a_changed_address_replaces_the_saved_one(): void
    {
        config(['hotel.server_info_key' => 'secret-key']);
        Setting::create(['key' => 'server_lan_ip', 'value' => json_encode('10.0.0.9')]);
        $this->fakeLan('192.168.1.77');

        $this->getJson('/api/server-info', ['X-Server-Key' => 'secret-key'])
            ->assertJsonPath('lan_ip', '192.168.1.77');

        $this->assertSame(1, Setting::where('key', 'server_lan_ip')->count());
        $this->assertSame('"192.168.1.77"', Setting::where('key', 'server_lan_ip')->value('value'));
    }

    public function test_the_address_is_not_an_admin_setting(): void
    {
        Setting::create(['key' => 'server_lan_ip', 'value' => json_encode('10.0.0.9')]);

        $this->assertArrayNotHasKey('server_lan_ip', app(SettingsService::class)->all());
    }
}
