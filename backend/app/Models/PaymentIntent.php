<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One card or QR payment the guest started. The server decides from this row,
 * and only from this row, whether a payment is real enough to confirm a booking.
 */
class PaymentIntent extends Model
{
    public const CHANNEL_CARD = 'card';
    public const CHANNEL_QR = 'khqr';

    public const STATUS_PENDING = 'pending';
    public const STATUS_PAID = 'paid';
    public const STATUS_CANCELLED = 'cancelled';
    public const STATUS_EXPIRED = 'expired';
    public const STATUS_REFUNDED = 'refunded';

    protected $fillable = [
        'booking_id', 'channel', 'amount', 'status', 'reference', 'qr_payload',
        'card_brand', 'card_last4', 'expires_at', 'paid_at',
    ];

    protected function casts(): array
    {
        return [
            'amount' => 'decimal:2',
            'expires_at' => 'datetime',
            'paid_at' => 'datetime',
        ];
    }

    public function booking(): BelongsTo
    {
        return $this->belongsTo(Booking::class);
    }

    public function scopePending(Builder $query): Builder
    {
        return $query->where('status', self::STATUS_PENDING);
    }

    public function isExpired(): bool
    {
        return $this->expires_at->lte(now());
    }

    /** "Visa ending 4242" or "KHQR": what the guest and the front desk see on a receipt. */
    public function describe(): string
    {
        return $this->channel === self::CHANNEL_CARD
            ? trim(($this->card_brand ?: 'Card') . ' ending ' . $this->card_last4)
            : 'KHQR';
    }
}
