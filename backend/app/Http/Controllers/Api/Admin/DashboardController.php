<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Models\Booking;
use App\Models\Payment;
use App\Models\Room;
use Illuminate\Http\JsonResponse;

/**
 * The admin's first screen: today's movement, rooms, money, bookings waiting to be paid,
 * and the last 7 days. Every number is counted straight from the database.
 */
class DashboardController extends Controller
{
    public function show(): JsonResponse
    {
        $today = now()->toDateString();

        return response()->json(['data' => [
            'date' => $today,
            'today' => $this->today($today),
            'rooms' => $this->rooms(),
            'money' => $this->money($today),
            'pending' => $this->pending(),
            'last_7_days' => $this->lastSevenDays(),
        ]]);
    }

    private function today(string $today): array
    {
        // Guests expected to arrive today: kept, paid, or already in. Cancelled and no-show never count.
        $arriving = Booking::whereDate('check_in_date', $today)
            ->where(fn ($q) => $q->whereIn('status', [Booking::STATUS_CONFIRMED, Booking::STATUS_CHECKED_IN, Booking::STATUS_CHECKED_OUT])
                ->orWhere(fn ($q) => $q->keptUnpaid()));

        $leaving = Booking::whereDate('check_out_date', $today)
            ->whereIn('status', [Booking::STATUS_CHECKED_IN, Booking::STATUS_CHECKED_OUT]);

        return [
            'check_ins' => (clone $arriving)->count(),
            'checked_in_so_far' => (clone $arriving)->whereIn('status', [Booking::STATUS_CHECKED_IN, Booking::STATUS_CHECKED_OUT])->count(),
            'check_outs' => (clone $leaving)->count(),
            'checked_out_so_far' => (clone $leaving)->where('status', Booking::STATUS_CHECKED_OUT)->count(),
        ];
    }

    private function rooms(): array
    {
        $total = Room::count();
        $maintenance = Room::where('status', Room::STATUS_MAINTENANCE)->count();
        $occupied = Booking::where('status', Booking::STATUS_CHECKED_IN)->distinct()->count('room_id');

        return [
            'total' => $total,
            'occupied' => $occupied,
            'maintenance' => $maintenance,
            'free' => max(0, $total - $maintenance - $occupied),
        ];
    }

    private function money(string $today): array
    {
        $paid = fn () => Payment::where('status', Payment::STATUS_PAID);
        $monthStart = now()->startOfMonth()->toDateString();
        $monthEnd = now()->endOfMonth()->toDateString();
        $month = fn () => $paid()->whereDate('paid_at', '>=', $monthStart)->whereDate('paid_at', '<=', $monthEnd);

        return [
            'today' => $this->sum($paid()->whereDate('paid_at', $today)),
            'month' => $this->sum($month()),
            'month_online' => $this->sum($month()->where('method', Payment::METHOD_ONLINE)),
            'month_hotel' => $this->sum($month()->whereIn('method', Payment::HOTEL_METHODS)),
            'month_refunded' => $this->sum(
                Payment::where('status', Payment::STATUS_REFUNDED)
                    ->whereDate('paid_at', '>=', $monthStart)->whereDate('paid_at', '<=', $monthEnd)
            ),
        ];
    }

    private function sum($query): float
    {
        return round((float) $query->sum('amount'), 2);
    }

    /** Bookings kept for the front desk and not paid yet, soonest check-in first. */
    private function pending(): array
    {
        $query = Booking::keptUnpaid();
        $count = (clone $query)->count();

        $items = $query->with(['user:id,name', 'room:id,room_number'])
            ->orderBy('check_in_date')->orderBy('id')
            ->limit(20)->get()
            ->map(fn (Booking $b) => [
                'id' => $b->id,
                'code' => $b->code,
                'guest' => $b->user?->name,
                'room_number' => $b->room?->room_number,
                'check_in_date' => $b->check_in_date->toDateString(),
                'check_out_date' => $b->check_out_date->toDateString(),
                'amount_due' => (float) $b->amount_due,
            ])->values();

        return ['count' => $count, 'items' => $items];
    }

    /** Oldest day first: bookings made that day (not cancelled) and money received that day. */
    private function lastSevenDays(): array
    {
        $days = [];
        for ($i = 6; $i >= 0; $i--) {
            $days[] = now()->subDays($i)->toDateString();
        }

        $bookings = Booking::visibleToStaff()
            ->whereNotIn('status', [Booking::STATUS_CANCELLED, Booking::STATUS_NO_SHOW])
            ->whereDate('created_at', '>=', $days[0])
            ->pluck('created_at')
            ->countBy(fn ($d) => $d->toDateString());

        $money = Payment::where('status', Payment::STATUS_PAID)
            ->whereDate('paid_at', '>=', $days[0])
            ->get(['amount', 'paid_at'])
            ->groupBy(fn ($p) => $p->paid_at->toDateString())
            ->map(fn ($g) => round((float) $g->sum('amount'), 2));

        return array_map(fn ($d) => [
            'date' => $d,
            'bookings' => (int) ($bookings[$d] ?? 0),
            'money' => (float) ($money[$d] ?? 0),
        ], $days);
    }
}
