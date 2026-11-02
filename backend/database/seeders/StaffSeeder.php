<?php

namespace Database\Seeders;

use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Str;

/**
 * Makes the first admin and one staff member so the hotel can start.
 * Safe to run again: an account that exists keeps its password.
 */
class StaffSeeder extends Seeder
{
    public function run(): void
    {
        foreach (['admin', 'staff'] as $role) {
            $config = config("hotel.seed.{$role}");

            $user = User::where('email', $config['email'])->first();

            if (! $user) {
                $password = $config['password'] ?: Str::password(14, symbols: false);

                $user = new User([
                    'name' => $config['name'],
                    'email' => $config['email'],
                    'phone' => $config['phone'],
                    'password' => $password,
                ]);

                if (! $config['password'] && $this->command) {
                    $this->command->warn("No password set for the {$role} account. Made this one, shown only once: {$password}");
                }
            }

            // Make sure the account really has the role and can log in.
            $user->forceFill([
                'role' => $role,
                'is_active' => true,
                'email_verified_at' => $user->email_verified_at ?? now(),
            ])->save();
        }
    }
}
