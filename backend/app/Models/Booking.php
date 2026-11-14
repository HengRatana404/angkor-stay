<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Booking extends Model
{
    public const STATUS_PENDING = 'pending';
    public const STATUS_CONFIRMED = 'confirmed';
    public const STATUS_CHECKED_IN = 'checked_in';
    public const STATUS_CHECKED_OUT = 'checked_out';
    public const STATUS_CANCELLED = 'cancelled';
    public const STATUS_NO_SHOW = 'no_show';

    public const STATUSES = [
        self::STATUS_PENDING, self::STATUS_CONFIRMED, self::STATUS_CHECKED_IN,
        self::STATUS_CHECKED_OUT, self::STATUS_CANCELLED, self::STATUS_NO_SHOW,
    ];

    public const CHOICE_HOTEL = 'hotel';
    public const CHOICE_ONLINE = 'online';

    /** Minutes a room is held while the customer decides how to pay. */
    public const HOLD_MINUTES = 5;

    /** One customer may hold at most this many rooms at the same time. */
    public const MAX_HOLDS_PER_USER = 2;

    /**
     * One customer may keep at most this many unpaid "pay at hotel" rooms.
     * Without a limit, someone could block the whole hotel for free.
     */
    public const MAX_KEPT_UNPAID_PER_USER = 3;

    protected $fillable = [
        'user_id', 'room_id', 'check_in_date', 'check_out_date', 'guests',
        'nights', 'price_per_night', 'total_price', 'status', 'payment_choice',
        'hold_expires_at', 'checked_in_at', 'checked_in_by', 'checked_out_at', 'checked_out_by',
        'discount_percent', 'discount_amount', 'guest_deleted_at',
    ];

    protected function casts(): array
    {
        return [
            'check_in_date' => 'date',
            'check_out_date' => 'date',
            'guests' => 'integer',
            'nights' => 'integer',
            'price_per_night' => 'decimal:2',
            'total_price' => 'decimal:2',
            'discount_percent' => 'integer',
            'discount_amount' => 'decimal:2',
            'hold_expires_at' => 'datetime',
            'checked_in_at' => 'datetime',
            'checked_out_at' => 'datetime',
            'guest_deleted_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function room(): BelongsTo
    {
        return $this->belongsTo(Room::class);
    }

    public function payments(): HasMany
    {
        return $this->hasMany(Payment::class);
    }

    /** Every card or QR payment the guest started for this booking. */
    public function intents(): HasMany
    {
        return $this->hasMany(PaymentIntent::class);
    }

    public function checkedInBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'checked_in_by');
    }

    public function checkedOutBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'checked_out_by');
    }

    /** The short number guests and staff use, such as AS-0012. */
    public function getCodeAttribute(): string
    {
        return 'AS-' . str_pad((string) $this->id, 4, '0', STR_PAD_LEFT);
    }

    /** What the guest has to pay: the price minus the online discount. */
    public function getAmountDueAttribute(): float
    {
        return round((float) $this->total_price - (float) $this->discount_amount, 2);
    }

    // ------------------------------------------------------------ state checks

    /** A pending booking whose 5-minute hold has run out. It keeps nothing. */
    public function isExpiredHold(): bool
    {
        return $this->status === self::STATUS_PENDING
            && $this->hold_expires_at !== null
            && $this->hold_expires_at->isPast();
    }

    public function isPaid(): bool
    {
        // Use the loaded list when there is one, so lists do not ask the database again.
        if ($this->relationLoaded('payments')) {
            return $this->payments->contains('status', Payment::STATUS_PAID);
        }

        return $this->payments()->where('status', Payment::STATUS_PAID)->exists();
    }

    /**
     * May the guest cancel this booking in the app?
     * Yes before check-in, unless they paid at the front desk (then the desk returns the money).
     */
    public function canBeCancelledByGuest(): bool
    {
        if ($this->status === self::STATUS_PENDING) {
            return true;
        }

        if ($this->status !== self::STATUS_CONFIRMED) {
            return false;
        }

        return ! $this->payments()
            ->where('status', Payment::STATUS_PAID)
            ->where('method', '!=', Payment::METHOD_ONLINE)
            ->exists();
    }

    public function canTakePayment(): bool
    {
        return $this->status === self::STATUS_PENDING && ! $this->isExpiredHold() && ! $this->isPaid();
    }

    public function canCheckIn(): bool
    {
        return $this->checkInProblem() === null;
    }

    public function canCheckOut(): bool
    {
        return $this->status === self::STATUS_CHECKED_IN;
    }

    /** Why this guest cannot check in now, or null when they can. */
    /**
     * After this moment a guest who has not arrived counts as a no-show: noon (the check-out time)
     * on the day after check-in. The clean-up job marks the booking then, and staff can no longer check in.
     */
    public function noShowCutoff(): \Illuminate\Support\Carbon
    {
        $time = (string) app(\App\Services\SettingsService::class)->get('check_out_time'); // "12:00"

        return \Illuminate\Support\Carbon::parse($this->check_in_date->toDateString() . ' ' . $time, config('app.timezone'))->addDay();
    }

    public function checkInProblem(): ?string
    {
        switch ($this->status) {
            case self::STATUS_CONFIRMED:
                $today = now()->toDateString();
                if ($today < $this->check_in_date->toDateString()) {
                    return 'Check-in opens on ' . $this->check_in_date->format('D j M') . '.';
                }
                if ($today >= $this->check_out_date->toDateString()) {
                    return 'This stay is already over.';
                }
                if (now()->gte($this->noShowCutoff())) {
                    return 'The arrival time has passed, so this booking counts as a no-show.';
                }

                return null;
            case self::STATUS_PENDING:
                return $this->isExpiredHold()
                    ? 'The hold ran out, so this booking keeps no room.'
                    : 'Take payment first.';
            case self::STATUS_CHECKED_IN:
                return 'This guest is already checked in.';
            case self::STATUS_CHECKED_OUT:
                return 'This guest already checked out.';
            default:
                return 'This booking is ' . str_replace('_', ' ', $this->status) . '.';
        }
    }

    // ------------------------------------------------------------------ scopes

    /**
     * Bookings that keep a room busy:
     * confirmed or checked in, or pending and still held
     * (the hold has not run out, or it is kept for pay-at-hotel).
     */
    /** A guest's own bookings, without the ones they deleted from their account. */
    public function scopeForGuest(Builder $query, int $userId): Builder
    {
        return $query->where('user_id', $userId)->whereNull('guest_deleted_at');
    }

    public function scopeBlocking(Builder $query): Builder
    {
        return $query->where(function (Builder $q) {
            $q->whereIn('status', [self::STATUS_CONFIRMED, self::STATUS_CHECKED_IN])
                ->orWhere(function (Builder $q) {
                    $q->where('status', self::STATUS_PENDING)
                        ->where(function (Builder $q) {
                            $q->whereNull('hold_expires_at')
                                ->orWhere('hold_expires_at', '>', now());
                        });
                });
        });
    }

    /** Pending bookings whose 5-minute hold is still running. */
    public function scopeHolding(Builder $query): Builder
    {
        return $query->where('status', self::STATUS_PENDING)
            ->whereNotNull('hold_expires_at')
            ->where('hold_expires_at', '>', now());
    }

    /** Pending bookings kept for pay-at-hotel: no countdown, waiting for the guest to arrive. */
    public function scopeKeptUnpaid(Builder $query): Builder
    {
        return $query->where('status', self::STATUS_PENDING)->whereNull('hold_expires_at');
    }

    /** Everything staff care about: not a hold that has already run out. */
    public function scopeVisibleToStaff(Builder $query): Builder
    {
        return $query->where(function (Builder $q) {
            $q->where('status', '!=', self::STATUS_PENDING)
                ->orWhereNull('hold_expires_at')
                ->orWhere('hold_expires_at', '>', now());
        });
    }

    /**
     * Stays that share at least one night with [$checkIn, $checkOut).
     * The check-out day is free, so one guest can leave in the morning
     * and the next guest arrive the same day.
     */
    public function scopeOverlapping(Builder $query, $checkIn, $checkOut): Builder
    {
        return $query->where('check_in_date', '<', $checkOut)
            ->where('check_out_date', '>', $checkIn);
    }
}
