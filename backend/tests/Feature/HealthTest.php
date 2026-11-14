<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class HealthTest extends TestCase
{
    use RefreshDatabase;

    public function test_health_says_ok_but_does_not_show_the_servers_address(): void
    {
        // Found by the code review: it used to show this PC's local IP to anyone, even through the tunnel.
        $this->getJson('/api/health')
            ->assertOk()
            ->assertJsonPath('status', 'ok')
            ->assertJsonPath('database', 'connected')
            ->assertJsonMissingPath('local_ip')
            ->assertJsonMissingPath('local_url');
    }
}
