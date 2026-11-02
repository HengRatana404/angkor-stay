<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\StayDatesRequest;
use App\Http\Resources\RoomTypeResource;
use App\Models\Room;
use App\Models\RoomType;
use App\Services\AvailabilityService;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

class RoomTypeController extends Controller
{
    public function __construct(private AvailabilityService $availability)
    {
    }

    /**
     * All room types. With ?check_in_date=...&check_out_date=... each type
     * also says how many rooms are free for those nights (available_rooms).
     */
    public function index(StayDatesRequest $request): AnonymousResourceCollection
    {
        $types = RoomType::query()
            ->with('images')
            ->withCount(['rooms' => fn ($q) => $q->where('status', Room::STATUS_AVAILABLE)])
            ->orderBy('price_per_night')
            ->get();

        $types->each(fn (RoomType $type) => $this->addAvailability($type, $request));

        return RoomTypeResource::collection($types);
    }

    public function show(StayDatesRequest $request, RoomType $roomType): RoomTypeResource
    {
        $roomType->load('images')
            ->loadCount(['rooms' => fn ($q) => $q->where('status', Room::STATUS_AVAILABLE)]);

        $this->addAvailability($roomType, $request);

        return new RoomTypeResource($roomType);
    }

    private function addAvailability(RoomType $type, StayDatesRequest $request): void
    {
        if ($request->filled('check_in_date') && $request->filled('check_out_date')) {
            $type->setAttribute('available_rooms', $this->availability->countFree(
                $type,
                $request->input('check_in_date'),
                $request->input('check_out_date'),
            ));
        }
    }
}
