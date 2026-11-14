<?php

namespace Tests\Feature;

use App\Models\User;
use Database\Seeders\StaffSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\MakesUsers;
use Tests\TestCase;

class StaffAdminApiTest extends TestCase
{
    use MakesUsers;
    use RefreshDatabase;

    private function asAdmin(): User
    {
        $admin = $this->makeUser('admin');
        Sanctum::actingAs($admin);

        return $admin;
    }

    private function staffPayload(array $override = []): array
    {
        return array_merge([
            'name' => 'Sok Dara',
            'email' => 'dara.staff@example.com',
            'phone' => '012111222',
            'password' => 'desk-pass-1',
        ], $override);
    }

    // ----------------------------------------------------------- who may enter

    public function test_a_guest_cannot_use_the_admin_routes(): void
    {
        $this->getJson('/api/admin/staff')->assertUnauthorized();
        $this->postJson('/api/admin/staff', $this->staffPayload())->assertUnauthorized();
        $this->patchJson('/api/admin/staff/1', ['name' => 'x'])->assertUnauthorized();
        $this->getJson('/api/admin/settings')->assertUnauthorized();
        $this->putJson('/api/admin/settings', [])->assertUnauthorized();
    }

    public function test_customers_and_staff_cannot_use_the_admin_routes(): void
    {
        foreach (['customer', 'staff'] as $role) {
            Sanctum::actingAs($this->makeUser($role));

            $this->getJson('/api/admin/staff')->assertStatus(403)->assertJsonPath('code', 'forbidden_role');
            $this->postJson('/api/admin/staff', $this->staffPayload(['email' => "{$role}@new.example.com"]))->assertStatus(403);
            $this->patchJson('/api/admin/staff/1', ['name' => 'x'])->assertStatus(403);
            $this->getJson('/api/admin/settings')->assertStatus(403);
            $this->putJson('/api/admin/settings', [])->assertStatus(403);
        }

        $this->assertSame(0, User::where('email', 'like', '%@new.example.com')->count());
    }

    // ------------------------------------------------------------------- list

    public function test_the_admin_sees_staff_only_sorted_by_name(): void
    {
        $this->makeUser('customer');
        $this->makeUser('admin');
        $this->makeUser('staff', ['name' => 'Zara']);
        $this->makeUser('staff', ['name' => 'Anna']);
        $this->asAdmin();

        $names = collect($this->getJson('/api/admin/staff')->assertOk()->json('data'))->pluck('name')->all();

        $this->assertSame(['Anna', 'Zara'], $names);
    }

    public function test_the_list_never_shows_passwords(): void
    {
        $this->makeUser('staff');
        $this->asAdmin();

        $row = $this->getJson('/api/admin/staff')->assertOk()->json('data.0');

        $this->assertArrayNotHasKey('password', $row);
        $this->assertSame(['id', 'name', 'email', 'phone', 'role', 'is_active', 'created_at'], array_keys($row));
    }

    // ----------------------------------------------------------------- create

    public function test_the_admin_creates_a_staff_member_who_can_log_in_at_once(): void
    {
        $this->asAdmin();

        $this->postJson('/api/admin/staff', $this->staffPayload())
            ->assertCreated()
            ->assertJsonPath('data.role', 'staff')
            ->assertJsonPath('data.is_active', true)
            ->assertJsonPath('data.email', 'dara.staff@example.com');

        $staff = User::where('email', 'dara.staff@example.com')->first();
        $this->assertSame('staff', $staff->role);
        $this->assertNotNull($staff->email_verified_at);
        $this->assertTrue(Hash::check('desk-pass-1', $staff->password));
        $this->assertNotSame('desk-pass-1', $staff->password);

        $this->app['auth']->forgetGuards();
        $this->postJson('/api/auth/login', ['email' => 'dara.staff@example.com', 'password' => 'desk-pass-1'])
            ->assertOk()
            ->assertJsonPath('user.role', 'staff');
    }

    public function test_the_request_cannot_choose_the_role_or_status(): void
    {
        $this->asAdmin();

        $this->postJson('/api/admin/staff', $this->staffPayload(['role' => 'admin', 'is_active' => false, 'email_verified_at' => null]))
            ->assertCreated()
            ->assertJsonPath('data.role', 'staff')
            ->assertJsonPath('data.is_active', true);

        $this->assertSame(0, User::where('email', 'dara.staff@example.com')->where('role', 'admin')->count());
    }

    public function test_creating_staff_checks_the_input(): void
    {
        $this->makeUser('customer', ['email' => 'taken@example.com', 'email_verified_at' => null]);
        $this->makeUser('customer', ['phone' => '099888777']);
        $this->asAdmin();

        $this->postJson('/api/admin/staff', [])
            ->assertStatus(422)->assertJsonValidationErrors(['name', 'email', 'phone', 'password']);

        // An email used by any account, even one never verified, is taken.
        $this->postJson('/api/admin/staff', $this->staffPayload(['email' => 'taken@example.com']))
            ->assertStatus(422)->assertJsonValidationErrors(['email']);

        $this->postJson('/api/admin/staff', $this->staffPayload(['phone' => '099888777']))
            ->assertStatus(422)->assertJsonValidationErrors(['phone']);

        $this->postJson('/api/admin/staff', $this->staffPayload(['phone' => 'abc']))
            ->assertStatus(422)->assertJsonValidationErrors(['phone']);

        $this->postJson('/api/admin/staff', $this->staffPayload(['password' => 'short']))
            ->assertStatus(422)->assertJsonValidationErrors(['password']);

        $this->postJson('/api/admin/staff', $this->staffPayload(['email' => 'not-an-email']))
            ->assertStatus(422)->assertJsonValidationErrors(['email']);

        $this->assertSame(0, User::where('role', 'staff')->count());
    }

    public function test_two_staff_cannot_share_an_email(): void
    {
        $this->asAdmin();

        $this->postJson('/api/admin/staff', $this->staffPayload())->assertCreated();
        $this->postJson('/api/admin/staff', $this->staffPayload(['phone' => '012333444']))
            ->assertStatus(422)->assertJsonValidationErrors(['email']);
    }

    // ----------------------------------------------------------------- update

    public function test_the_admin_can_change_a_staff_name_and_phone(): void
    {
        $staff = $this->makeUser('staff');
        $this->asAdmin();

        $this->patchJson("/api/admin/staff/{$staff->id}", ['name' => 'New Name', 'phone' => '012555666'])
            ->assertOk()
            ->assertJsonPath('data.name', 'New Name')
            ->assertJsonPath('data.phone', '012555666');

        $this->assertSame('New Name', $staff->fresh()->name);
    }

    public function test_changing_the_name_keeps_the_staff_member_logged_in(): void
    {
        $staff = $this->makeUser('staff');
        $staff->createToken('mobile');
        $this->asAdmin();

        $this->patchJson("/api/admin/staff/{$staff->id}", ['name' => 'Renamed'])->assertOk();

        $this->assertSame(1, $staff->tokens()->count());
    }

    public function test_update_checks_the_input(): void
    {
        $staff = $this->makeUser('staff');
        $this->asAdmin();

        $this->patchJson("/api/admin/staff/{$staff->id}", ['phone' => 'abc'])
            ->assertStatus(422)->assertJsonValidationErrors(['phone']);
        $this->patchJson("/api/admin/staff/{$staff->id}", ['name' => ''])
            ->assertStatus(422)->assertJsonValidationErrors(['name']);
        $this->patchJson("/api/admin/staff/{$staff->id}", ['password' => 'short'])
            ->assertStatus(422)->assertJsonValidationErrors(['password']);
        $this->patchJson("/api/admin/staff/{$staff->id}", ['is_active' => 'maybe'])
            ->assertStatus(422)->assertJsonValidationErrors(['is_active']);
    }

    public function test_a_staff_member_may_keep_their_own_phone_number(): void
    {
        $staff = $this->makeUser('staff', ['phone' => '012777888']);
        $this->asAdmin();

        $this->patchJson("/api/admin/staff/{$staff->id}", ['phone' => '012777888'])->assertOk();
    }

    public function test_only_staff_can_be_changed_here(): void
    {
        $other = $this->makeUser('admin');
        $customer = $this->makeUser('customer');
        $this->asAdmin();

        $this->patchJson("/api/admin/staff/{$other->id}", ['is_active' => false])->assertNotFound();
        $this->patchJson("/api/admin/staff/{$customer->id}", ['is_active' => false])->assertNotFound();
        $this->patchJson('/api/admin/staff/9999', ['is_active' => false])->assertNotFound();

        $this->assertTrue($other->fresh()->is_active);
        $this->assertTrue($customer->fresh()->is_active);
    }

    // ------------------------------------------------------- disable / enable

    public function test_a_disabled_staff_member_cannot_log_in_and_is_logged_out_everywhere(): void
    {
        $staff = $this->makeUser('staff');
        $token = $staff->createToken('mobile')->plainTextToken;
        $this->asAdmin();

        $this->patchJson("/api/admin/staff/{$staff->id}", ['is_active' => false])
            ->assertOk()->assertJsonPath('data.is_active', false);

        $this->assertSame(0, $staff->tokens()->count());

        $this->app['auth']->forgetGuards();
        $this->postJson('/api/auth/login', ['email' => $staff->email, 'password' => 'secret1234'])
            ->assertStatus(403)->assertJsonPath('message', 'This account is disabled.');

        $this->withToken($token)->getJson('/api/auth/me')->assertUnauthorized();
    }

    public function test_a_disabled_staff_member_can_be_enabled_again(): void
    {
        $staff = $this->makeUser('staff', ['is_active' => false]);
        $this->asAdmin();

        $this->patchJson("/api/admin/staff/{$staff->id}", ['is_active' => true])->assertOk();

        $this->app['auth']->forgetGuards();
        $this->postJson('/api/auth/login', ['email' => $staff->email, 'password' => 'secret1234'])->assertOk();
    }

    // -------------------------------------------------------- password reset

    public function test_the_admin_can_set_a_new_password_for_staff_who_forgot_theirs(): void
    {
        $staff = $this->makeUser('staff');
        $staff->createToken('mobile');
        $this->asAdmin();

        $this->patchJson("/api/admin/staff/{$staff->id}", ['password' => 'brand-new-pass-9'])->assertOk();

        $this->assertSame(0, $staff->tokens()->count());

        $this->app['auth']->forgetGuards();
        $this->postJson('/api/auth/login', ['email' => $staff->email, 'password' => 'secret1234'])->assertStatus(422);
        $this->postJson('/api/auth/login', ['email' => $staff->email, 'password' => 'brand-new-pass-9'])->assertOk();
    }

    public function test_a_staff_member_cannot_use_the_admin_routes_after_being_created(): void
    {
        $this->asAdmin();
        $this->postJson('/api/admin/staff', $this->staffPayload())->assertCreated();

        $this->app['auth']->forgetGuards();
        $token = $this->postJson('/api/auth/login', ['email' => 'dara.staff@example.com', 'password' => 'desk-pass-1'])
            ->assertOk()->json('token');

        $this->app['auth']->forgetGuards();
        $this->withToken($token)->getJson('/api/admin/staff')->assertStatus(403);
        $this->withToken($token)->getJson('/api/admin/settings')->assertStatus(403);
    }

    // ---------------------------------------------------------------- seeder

    public function test_the_seeder_makes_one_admin_and_one_staff_with_the_configured_passwords(): void
    {
        config([
            'hotel.seed.admin.password' => 'admin-seed-pass-1',
            'hotel.seed.staff.password' => 'staff-seed-pass-1',
        ]);

        $this->seed(StaffSeeder::class);

        $admin = User::where('email', config('hotel.seed.admin.email'))->first();
        $staff = User::where('email', config('hotel.seed.staff.email'))->first();

        $this->assertSame('admin', $admin->role);
        $this->assertSame('staff', $staff->role);
        $this->assertTrue(Hash::check('admin-seed-pass-1', $admin->password));
        $this->assertTrue(Hash::check('staff-seed-pass-1', $staff->password));
        $this->assertNotNull($admin->email_verified_at);
        $this->assertTrue($staff->is_active);

        $this->postJson('/api/auth/login', ['email' => $admin->email, 'password' => 'admin-seed-pass-1'])->assertOk();
    }

    public function test_running_the_seeder_again_changes_no_password_and_makes_no_copies(): void
    {
        config(['hotel.seed.admin.password' => 'admin-seed-pass-1', 'hotel.seed.staff.password' => 'staff-seed-pass-1']);
        $this->seed(StaffSeeder::class);

        $admin = User::where('role', 'admin')->first();
        $admin->forceFill(['password' => 'changed-by-admin-7'])->save();

        $this->seed(StaffSeeder::class);

        $this->assertSame(2, User::count());
        $this->assertTrue(Hash::check('changed-by-admin-7', $admin->fresh()->password));
    }

    public function test_the_seeder_makes_a_random_password_when_none_is_configured(): void
    {
        config(['hotel.seed.admin.password' => null, 'hotel.seed.staff.password' => '']);

        $this->seed(StaffSeeder::class);

        $admin = User::where('role', 'admin')->first();
        $this->assertNotNull($admin);
        $this->assertFalse(Hash::check('', $admin->password));
        $this->assertFalse(Hash::check('password', $admin->password));
    }

    public function test_the_seeder_re_enables_a_disabled_demo_account(): void
    {
        config(['hotel.seed.admin.password' => 'admin-seed-pass-1', 'hotel.seed.staff.password' => 'staff-seed-pass-1']);
        $this->seed(StaffSeeder::class);
        User::where('role', 'staff')->first()->forceFill(['is_active' => false])->save();

        $this->seed(StaffSeeder::class);

        $this->assertTrue(User::where('role', 'staff')->first()->is_active);
    }
}
