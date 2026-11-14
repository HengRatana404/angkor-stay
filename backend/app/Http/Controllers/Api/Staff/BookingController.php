<?php

namespace App\Http\Controllers\Api\Staff;

use App\Http\Controllers\Controller;
use App\Http\Requests\Staff\SearchBookingsRequest;
use App\Http\Requests\Staff\TakePaymentRequest;
use App\Http\Resources\StaffBookingResource;
use App\Models\Booking;
use App\Models\Payment;
use App\Services\OnlinePaymentService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\DB;

/**
 * Staff and admin: find bookings, take payment at the hotel,
 * check guests in and out. Every action saves the staff member's name.
 */
class BookingController extends Controller
{
    public function __construct(private OnlinePaymentService $online)
    {
    }

    private const LIST_LIMIT = 100;

    private const WITH = ['user', 'room.roomType', 'payments.receivedBy', 'checkedInBy', 'checkedOutBy'];

    /**
     * Newest first. ?search= looks at the guest's name, email and phone, the
     * room number and the booking code (AS-0012 or just 12). ?status= filters.
     * A hold that already ran out is left out: it never kept anything.
     */
    public function index(SearchBookingsRequest $request): AnonymousResourceCollection
    {
        $query = Booking::query()->with(self::WITH)->visibleToStaff();

        if ($request->filled('status')) {
            $query->where('status', $request->input('status'));
        }

        if ($request->filled('search')) {
            $term = trim($request->input('search'));
            // % and _ are search symbols in SQL, so make them plain letters.
            $like = '%' . str_replace(['\\', '%', '_'], ['\\\\', '\\%', '\\_'], $term) . '%';

            $query->where(function ($q) use ($term, $like) {
                // "AS-0012", "as0012" and "12" all mean booking 12.
                if (preg_match('/^(?:as-?)?0*(\d+)$/i', $term, $m)) {
                    $q->orWhere('id', (int) $m[1]);
                }
                $q->orWhereHas('user', fn ($u) => $u
                    ->where('name', 'ilike', $like)
                    ->orWhere('email', 'ilike', $like)
                    ->orWhere('phone', 'ilike', $like));
                $q->orWhereHas('room', fn ($r) => $r->where('room_number', 'ilike', $like));
            });
        }

        return StaffBookingResource::collection($query->orderByDesc('id')->limit(self::LIST_LIMIT)->get());
    }

    public function show(int $id): StaffBookingResource
    {
        return new StaffBookingResource(Booking::with(self::WITH)->findOrFail($id));
    }

    /**
     * The guest paid at the front desk. The amount is the booking's saved
     * total (no discount at the hotel). The booking becomes confirmed.
     */
    public function takePayment(TakePaymentRequest $request, int $id): JsonResponse
    {
        $result = DB::transaction(function () use ($request, $id) {
            // Lock the booking, so two staff pressing the button at once cannot both take money.
            $booking = Booking::lockForUpdate()->findOrFail($id);

            if ($booking->isPaid()) {
                return $this->problem('This booking is already paid.', 'already_paid', 409);
            }
            if ($booking->status !== Booking::STATUS_PENDING) {
                return $this->problem(
                    'This booking is ' . str_replace('_', ' ', $booking->status) . ', so it cannot be paid.',
                    'not_pending',
                    422,
                );
            }
            if ($booking->isExpiredHold()) {
                return $this->problem(
                    'The guest\'s 5 minutes ran out, so no room is kept. They need to book again.',
                    'hold_expired',
                    409,
                );
            }

            // The guest may have an online payment page open. Close it, so they cannot
            // pay twice, and drop the online discount: at the desk the price is full.
            $this->online->abandon($booking);

            Payment::create([
                'booking_id' => $booking->id,
                'amount' => $booking->total_price,
                'method' => $request->input('method'),
                'status' => Payment::STATUS_PAID,
                'received_by' => $request->user()->id,
                'paid_at' => now(),
            ]);

            $booking->update([
                'status' => Booking::STATUS_CONFIRMED,
                'payment_choice' => Booking::CHOICE_HOTEL,
                'hold_expires_at' => null,
            ]);

            return $booking;
        });

        return $this->respond($result, 201);
    }

    public function checkIn(Request $request, int $id): JsonResponse
    {
        $result = DB::transaction(function () use ($request, $id) {
            $booking = Booking::lockForUpdate()->findOrFail($id);

            if ($problem = $booking->checkInProblem()) {
                return $this->problem($problem, 'cannot_check_in', 422);
            }

            $booking->update([
                'status' => Booking::STATUS_CHECKED_IN,
                'checked_in_at' => now(),
                'checked_in_by' => $request->user()->id,
            ]);

            return $booking;
        });

        return $this->respond($result);
    }

    public function checkOut(Request $request, int $id): JsonResponse
    {
        $result = DB::transaction(function () use ($request, $id) {
            $booking = Booking::lockForUpdate()->findOrFail($id);

            if (! $booking->canCheckOut()) {
                return $this->problem(
                    $booking->status === Booking::STATUS_CHECKED_OUT
                        ? 'This guest already checked out.'
                        : 'This guest is not checked in.',
                    'cannot_check_out',
                    422,
                );
            }

            $booking->update([
                'status' => Booking::STATUS_CHECKED_OUT,
                'checked_out_at' => now(),
                'checked_out_by' => $request->user()->id,
            ]);

            return $booking;
        });

        return $this->respond($result);
    }

    private function problem(string $message, string $code, int $status): JsonResponse
    {
        return response()->json(['message' => $message, 'code' => $code], $status);
    }

    private function respond(Booking|JsonResponse $result, int $status = 200): JsonResponse
    {
        if ($result instanceof JsonResponse) {
            return $result;
        }

        return (new StaffBookingResource($result->fresh(self::WITH)))->response()->setStatusCode($status);
    }
}
