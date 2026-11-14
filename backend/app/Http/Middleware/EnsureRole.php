<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Lets only the listed roles through, for example `role:admin`
 * or `role:staff,admin`. Use it after `auth:sanctum`.
 */
class EnsureRole
{
    public function handle(Request $request, Closure $next, string ...$roles): Response
    {
        $user = $request->user();

        if (! $user || ! in_array($user->role, $roles, true)) {
            return response()->json([
                'message' => 'This account is not allowed to do that.',
                'code' => 'forbidden_role',
            ], 403);
        }

        return $next($request);
    }
}
