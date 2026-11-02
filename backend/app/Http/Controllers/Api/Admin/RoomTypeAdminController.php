<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\RoomTypeRequest;
use App\Models\RoomType;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;

/**
 * Admin: room types (name, price, size, photos).
 * Old bookings keep the price they were made with, so a new price only affects new bookings.
 */
class RoomTypeAdminController extends Controller
{
    public function index(): JsonResponse
    {
        $types = RoomType::with(['images', 'rooms' => fn ($q) => $q->orderBy('room_number')])
            ->orderBy('price_per_night')
            ->get();

        return response()->json(['data' => $types->map(fn (RoomType $t) => $this->shape($t))->values()]);
    }

    public function store(RoomTypeRequest $request): JsonResponse
    {
        $type = DB::transaction(function () use ($request) {
            $type = RoomType::create($request->safe()->only(['name', 'description', 'price_per_night', 'capacity']));
            $this->saveImages($type, $request->input('images', []));

            return $type;
        });

        return response()->json(['data' => $this->shape($type->fresh(['images', 'rooms']))], 201);
    }

    public function update(RoomTypeRequest $request, int $id): JsonResponse
    {
        $type = RoomType::findOrFail($id);

        DB::transaction(function () use ($request, $type) {
            $type->update($request->safe()->only(['name', 'description', 'price_per_night', 'capacity']));

            if ($request->has('images')) {
                $this->saveImages($type, $request->input('images', []));
            }
        });

        return response()->json(['data' => $this->shape($type->fresh(['images', 'rooms']))]);
    }

    public function destroy(int $id): JsonResponse
    {
        $type = RoomType::withCount('rooms')->findOrFail($id);

        if ($type->rooms_count > 0) {
            return response()->json([
                'message' => "This type still has {$type->rooms_count} room(s). Move or delete the rooms first.",
                'code' => 'has_rooms',
            ], 409);
        }

        $type->delete(); // its photos go with it

        return response()->json(['message' => 'The room type was deleted.']);
    }

    private function saveImages(RoomType $type, array $urls): void
    {
        $type->images()->delete();

        foreach (array_values($urls) as $i => $url) {
            $type->images()->create(['url' => $url, 'sort_order' => $i]);
        }
    }

    private function shape(RoomType $t): array
    {
        return [
            'id' => $t->id,
            'name' => $t->name,
            'description' => $t->description,
            'price_per_night' => (float) $t->price_per_night,
            'capacity' => $t->capacity,
            'images' => $t->images->pluck('url')->values(),
            'rooms' => $t->rooms->map(fn ($r) => [
                'id' => $r->id,
                'room_number' => $r->room_number,
                'floor' => $r->floor,
                'status' => $r->status,
            ])->values(),
        ];
    }
}
