<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\RoomRequest;
use App\Models\Booking;
use App\Models\Room;
use Illuminate\Http\JsonResponse;

/** Admin: add, change and delete single rooms. History is protected. */
class RoomAdminController extends Controller
{
    public function store(RoomRequest $request): JsonResponse
    {
        $room = Room::create($request->safe()->only(['room_number', 'room_type_id', 'floor', 'status']))->fresh();

        return response()->json(['data' => $this->shape($room)], 201);
    }

    public function update(RoomRequest $request, int $id): JsonResponse
    {
        $room = Room::findOrFail($id);
        $data = $request->safe()->only(['room_number', 'room_type_id', 'floor', 'status']);

        // A room with bookings keeps its type: those bookings were priced with it.
        if (isset($data['room_type_id']) && (int) $data['room_type_id'] !== $room->room_type_id
            && $room->bookings()->exists()) {
            return response()->json([
                'message' => 'This room already has bookings, so its type cannot change.',
                'code' => 'room_has_bookings',
            ], 409);
        }

        // Taking a room out of service must not leave a guest without a room.
        if (($data['status'] ?? null) === Room::STATUS_MAINTENANCE && $room->status !== Room::STATUS_MAINTENANCE) {
            $upcoming = $room->bookings()->blocking()
                ->where('check_out_date', '>=', now()->toDateString())
                ->count();

            if ($upcoming > 0) {
                return response()->json([
                    'message' => "This room has {$upcoming} upcoming booking(s). Cancel or move them first.",
                    'code' => 'room_has_upcoming',
                ], 409);
            }
        }

        $room->update($data);

        return response()->json(['data' => $this->shape($room)]);
    }

    public function destroy(int $id): JsonResponse
    {
        $room = Room::findOrFail($id);

        if ($room->bookings()->exists()) {
            return response()->json([
                'message' => 'This room has bookings, so it cannot be deleted. Set it to maintenance instead.',
                'code' => 'room_has_bookings',
            ], 409);
        }

        $room->delete();

        return response()->json(['message' => 'The room was deleted.']);
    }

    private function shape(Room $r): array
    {
        return [
            'id' => $r->id,
            'room_number' => $r->room_number,
            'room_type_id' => $r->room_type_id,
            'floor' => $r->floor,
            'status' => $r->status,
        ];
    }
}
