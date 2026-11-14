<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\StoreStaffRequest;
use App\Http\Requests\Admin\UpdateStaffRequest;
use App\Http\Resources\StaffResource;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

/**
 * Admin only: staff accounts. Staff are created here, never by registering.
 * Only accounts with the `staff` role can be reached, so an admin cannot
 * change another admin or a customer from this screen.
 */
class StaffController extends Controller
{
    public function index(): AnonymousResourceCollection
    {
        return StaffResource::collection(
            User::where('role', 'staff')->orderBy('name')->get()
        );
    }

    public function store(StoreStaffRequest $request): JsonResponse
    {
        $data = $request->validated();

        $staff = new User([
            'name' => $data['name'],
            'email' => $data['email'],
            'phone' => $data['phone'],
            'password' => $data['password'],
        ]);
        // Role and status are never taken from the request body.
        $staff->forceFill([
            'role' => 'staff',
            'is_active' => true,
            'email_verified_at' => now(),
        ])->save();

        return (new StaffResource($staff))->response()->setStatusCode(201);
    }

    public function update(UpdateStaffRequest $request, int $id): StaffResource
    {
        $staff = User::where('role', 'staff')->findOrFail($id);
        $data = $request->validated();

        $staff->fill(collect($data)->only(['name', 'phone', 'password'])->all());

        if (array_key_exists('is_active', $data)) {
            $staff->is_active = $data['is_active'];
        }

        $staff->save();

        // A disabled account, or one with a new password, is logged out everywhere.
        if (array_key_exists('is_active', $data) && ! $data['is_active'] || array_key_exists('password', $data)) {
            $staff->tokens()->delete();
        }

        return new StaffResource($staff);
    }
}
