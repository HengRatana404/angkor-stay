<?php

namespace Tests\Concerns;

use App\Models\User;

trait MakesUsers
{
    private int $madeUsers = 0;

    /** A verified, active user with the given role. */
    protected function makeUser(string $role = 'customer', array $extra = []): User
    {
        $this->madeUsers++;

        $user = new User([
            'name' => ucfirst($role) . " {$this->madeUsers}",
            'email' => "{$role}{$this->madeUsers}@example.com",
            'phone' => '0130000' . str_pad((string) $this->madeUsers, 3, '0', STR_PAD_LEFT),
            'password' => 'secret1234',
        ]);

        $user->forceFill(array_merge([
            'role' => $role,
            'is_active' => true,
            'email_verified_at' => now(),
        ], $extra))->save();

        return $user;
    }

    /** The next request comes from this IP address. */
    protected function fromIp(string $ip): static
    {
        return $this->withServerVariables(['REMOTE_ADDR' => $ip]);
    }
}
