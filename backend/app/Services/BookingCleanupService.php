<?php

namespace App\Services;

use App\Models\Booking;
use App\Payments\PaymentException;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * The two automatic jobs:
 *  1. Holds that ran out are tidied up (cancelled), and any payment page is closed.
 *  2. A guest who never came is a no-show at check-out time on the day AFTER the check-in date.
 *     Online money goes back in full. If a refund fails, that booking is left alone and tried again next run.
 */
class BookingCleanupService
{
    public function __construct(
        private OnlinePaymentService $online,
        private SettingsService $settings,
    ) {
    }

    /** @return array{expired_holds:int, no_shows:int, refunded:float, failed:int} */
    public function run(?Carbon $now = null): array
    {
        $now ??= now();

        $expired = $this->expireHolds($now);
        $noShows = $this->markNoShows($now);

        return [
            'expired_holds' => $expired,
            'no_shows' => $noShows['count'],
            'refunded' => $noShows['refunded'],
            'failed' => $noShows['failed'],
        ];
    }

    public function expireHolds(Carbon $now): int
    {
        $ids = Booking::where('status', Booking::STATUS_PENDING)
            ->whereNotNull('hold_expires_at')
            ->where('hold_expires_at', '<=', $now)
            ->pluck('id');

        $count = 0;

        foreach ($ids as $id) {
            $done = DB::transaction(function () use ($id, $now) {
                $booking = Booking::lockForUpdate()->find($id);

                // Re-check under the lock: the guest may have paid or chosen "pay at hotel" a moment ago.
                if (! $booking
                    || $booking->status !== Booking::STATUS_PENDING
                    || $booking->hold_expires_at === null
                    || $booking->hold_expires_at->gt($now)) {
                    return false;
                }

                $this->online->abandon($booking);
                $booking->update(['status' => Booking::STATUS_CANCELLED, 'hold_expires_at' => null]);

                return true;
            });

            $count += $done ? 1 : 0;
        }

        return $count;
    }

    /** @return array{count:int, refunded:float, failed:int} */
    public function markNoShows(Carbon $now): array
    {
        $time = (string) $this->settings->get('check_out_time'); // "12:00"

        $candidates = Booking::whereIn('status', [Booking::STATUS_PENDING, Booking::STATUS_CONFIRMED])
            ->where(fn ($q) => $q->whereNull('hold_expires_at')->orWhere('status', Booking::STATUS_CONFIRMED))
            ->whereDate('check_in_date', '<', $now->toDateString())
            ->pluck('id');

        $count = 0;
        $failed = 0;
        $refunded = 0.0;

        foreach ($candidates as $id) {
            try {
                $money = DB::transaction(function () use ($id, $now, $time) {
                    $booking = Booking::lockForUpdate()->find($id);

                    if (! $booking || ! in_array($booking->status, [Booking::STATUS_PENDING, Booking::STATUS_CONFIRMED], true)) {
                        return null;
                    }

                    $cutoff = Carbon::parse($booking->check_in_date->toDateString() . ' ' . $time, $now->getTimezone())->addDay();
                    if ($now->lt($cutoff)) {
                        return null;
                    }

                    $money = $this->online->refundOnlinePayments($booking);
                    $this->online->abandon($booking);
                    $booking->update(['status' => Booking::STATUS_NO_SHOW, 'hold_expires_at' => null]);

                    return $money;
                });
            } catch (PaymentException $e) {
                $failed++;
                Log::critical("NO-SHOW REFUND FAILED for booking {$id}: " . $e->getMessage());
                continue;
            }

            if ($money !== null) {
                $count++;
                $refunded += $money;
            }
        }

        return ['count' => $count, 'refunded' => round($refunded, 2), 'failed' => $failed];
    }
}
