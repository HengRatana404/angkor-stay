<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\StoreBookingRequest;
use App\Http\Resources\BookingResource;
use App\Models\Booking;
use App\Models\RoomType;
use App\Payments\PaymentException;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use App\Services\AvailabilityService;
use App\Services\OnlinePaymentService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class BookingController extends Controller
{
    public function __construct(
        private AvailabilityService $availability,
        private OnlinePaymentService $online,
    ) {
    }

    /**
     * Book a room: check it is free, pick a room number, hold it for 5 minutes.
     * Nothing is paid here. The room is checked BEFORE any payment.
     */
    public function store(StoreBookingRequest $request): JsonResponse
    {
        $user = $request->user();
        $in = $request->input('check_in_date');
        $out = $request->input('check_out_date');
        $guests = (int) $request->input('guests');

        $booking = DB::transaction(function () use ($user, $request, $in, $out, $guests) {
            // Lock this room type. If two customers book at the same moment,
            // the second one waits here until the first is saved, and then
            // sees the room as taken. So the first one wins.
            $type = RoomType::whereKey($request->input('room_type_id'))->lockForUpdate()->firstOrFail();

            if ($guests > $type->capacity) {
                throw ValidationException::withMessages([
                    'guests' => "A {$type->name} room fits up to {$type->capacity} guests.",
                ]);
            }

            $holds = Booking::where('user_id', $user->id)->holding()->count();
            if ($holds >= Booking::MAX_HOLDS_PER_USER) {
                return response()->json([
                    'message' => 'You already have ' . Booking::MAX_HOLDS_PER_USER
                        . ' rooms waiting for payment. Finish or release one first.',
                    'code' => 'too_many_holds',
                ], 409);
            }

            $room = $this->availability->freeRooms($type, $in, $out)->orderBy('room_number')->first();
            if (! $room) {
                return response()->json([
                    'message' => "No {$type->name} room left for these dates.",
                    'code' => 'no_room_left',
                ], 409);
            }

            $nights = (int) $request->nights();

            return Booking::create([
                'user_id' => $user->id,
                'room_id' => $room->id,
                'check_in_date' => $in,
                'check_out_date' => $out,
                'guests' => $guests,
                'nights' => $nights,
                'price_per_night' => $type->price_per_night,
                'total_price' => round($nights * (float) $type->price_per_night, 2),
                'status' => Booking::STATUS_PENDING,
                'hold_expires_at' => now()->addMinutes(Booking::HOLD_MINUTES),
            ]);
        });

        if ($booking instanceof JsonResponse) {
            return $booking;
        }

        return (new BookingResource($booking->load('room.roomType.images')))
            ->response()
            ->setStatusCode(201);
    }

    public function show(Request $request, int $id): BookingResource
    {
        return new BookingResource($this->ownBooking($request, $id)->load('room.roomType.images'));
    }

    /** The guest's own bookings, newest first. A hold that already ran out never kept anything, so it is left out. */
    public function index(Request $request): AnonymousResourceCollection
    {
        $bookings = Booking::forGuest($request->user()->id)
            ->visibleToStaff()
            ->with('room.roomType.images')
            ->orderByDesc('id')
            ->limit(100)
            ->get();

        return BookingResource::collection($bookings);
    }

    /**
     * The guest cancels before check-in.
     *  - Not paid yet: the room is simply let go.
     *  - Paid online: the money goes back in full, first. If the refund fails, nothing is cancelled.
     *  - Paid at the front desk: the desk must cancel, because they hold the money.
     */
    public function cancel(Request $request, int $id): JsonResponse
    {
        try {
            $booking = DB::transaction(function () use ($request, $id) {
                $booking = Booking::forGuest($request->user()->id)->lockForUpdate()->findOrFail($id);

                if (! in_array($booking->status, [Booking::STATUS_PENDING, Booking::STATUS_CONFIRMED], true)) {
                    throw new PaymentException('This booking can no longer be cancelled.', 'cannot_cancel', 422);
                }

                if (! $booking->canBeCancelledByGuest()) {
                    throw new PaymentException(
                        'You paid at the front desk. Please ask the front desk to cancel and return your money.',
                        'paid_at_hotel',
                        422,
                    );
                }

                if ($booking->status === Booking::STATUS_CONFIRMED) {
                    $this->online->refundOnlinePayments($booking);
                }

                // A payment page that is still open must not be payable after this.
                $this->online->abandon($booking);

                $booking->update(['status' => Booking::STATUS_CANCELLED, 'hold_expires_at' => null]);

                return $booking;
            });
        } catch (PaymentException $e) {
            return $e->toResponse();
        }

        return response()->json(['data' => (new BookingResource($booking->fresh('room.roomType.images')))->resolve()]);
    }

    /**
     * "I will pay at the hotel." The room is kept for the guest with no
     * countdown, and the booking waits as pending until staff take the payment.
     * There is no discount for this way of paying.
     */
    public function payAtHotel(Request $request, int $id): BookingResource|JsonResponse
    {
        return DB::transaction(function () use ($request, $id) {
            $booking = Booking::forGuest($request->user()->id)->lockForUpdate()->findOrFail($id);

            if ($booking->status !== Booking::STATUS_PENDING || $booking->isPaid()) {
                return response()->json([
                    'message' => 'This booking can no longer be changed.',
                    'code' => 'not_pending',
                ], 422);
            }

            // Pressing the button twice does no harm.
            if ($booking->payment_choice === Booking::CHOICE_HOTEL && $booking->hold_expires_at === null) {
                return new BookingResource($booking->load('room.roomType.images'));
            }

            if ($booking->isExpiredHold()) {
                return response()->json([
                    'message' => 'Your 5 minutes ran out and the room may be taken. Please book again.',
                    'code' => 'hold_expired',
                ], 409);
            }

            $kept = Booking::where('user_id', $booking->user_id)
                ->keptUnpaid()
                ->where('check_out_date', '>=', now()->toDateString())
                ->where('id', '!=', $booking->id)
                ->count();

            if ($kept >= Booking::MAX_KEPT_UNPAID_PER_USER) {
                return response()->json([
                    'message' => 'You already have ' . Booking::MAX_KEPT_UNPAID_PER_USER
                        . ' rooms waiting to be paid at the hotel. Cancel one first.',
                    'code' => 'too_many_unpaid',
                ], 409);
            }

            // If the guest had started paying online, close that page and drop the online discount.
            $this->online->abandon($booking);

            $booking->update([
                'payment_choice' => Booking::CHOICE_HOTEL,
                'hold_expires_at' => null, // kept until staff act
            ]);

            return new BookingResource($booking->load('room.roomType.images'));
        });
    }

    /** Let go of a room that is still waiting for payment. */
    public function release(Request $request, int $id): JsonResponse
    {
        // Locked like cancel(): a payment that lands at the same moment cannot be overwritten.
        return DB::transaction(function () use ($request, $id) {
            $booking = Booking::forGuest($request->user()->id)->lockForUpdate()->findOrFail($id);

            if ($booking->status !== Booking::STATUS_PENDING) {
                return response()->json(['message' => 'This booking can no longer be released.'], 422);
            }

            // A payment page that is still open must not be payable after this.
            $this->online->abandon($booking);

            $booking->update(['status' => Booking::STATUS_CANCELLED, 'hold_expires_at' => null]);

            return response()->json(['message' => 'The room was released.']);
        });
    }

    /**
     * The guest deletes a FINISHED booking from their account for good. The hotel keeps its own
     * record (staff, admin, payments), so no money history is lost. A running booking must be
     * cancelled first.
     */
    public function destroy(Request $request, int $id): JsonResponse
    {
        return DB::transaction(function () use ($request, $id) {
            $booking = Booking::forGuest($request->user()->id)->lockForUpdate()->findOrFail($id);

            $finished = [Booking::STATUS_CANCELLED, Booking::STATUS_NO_SHOW, Booking::STATUS_CHECKED_OUT];
            if (! in_array($booking->status, $finished, true)) {
                return response()->json([
                    'message' => 'Only a finished booking can be deleted. Cancel it first.',
                    'code' => 'cannot_delete',
                ], 422);
            }

            $booking->update(['guest_deleted_at' => now()]);

            return response()->json(['message' => 'The booking was deleted.']);
        });
    }

    /** A customer sees only their own bookings; anything else looks like it does not exist. */
    private function ownBooking(Request $request, int $id): Booking
    {
        return Booking::forGuest($request->user()->id)->findOrFail($id);
    }
}
