<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Payment extends Model
{
    public const METHOD_KHQR = 'khqr';
    public const METHOD_CASH = 'cash';
    public const METHOD_CARD = 'card';
    public const METHOD_ONLINE = 'online';

    /** The ways staff can take money at the hotel. */
    public const HOTEL_METHODS = [self::METHOD_KHQR, self::METHOD_CASH, self::METHOD_CARD];

    public const STATUS_PAID = 'paid';
    public const STATUS_REFUNDED = 'refunded';

    protected $fillable = [
        'booking_id', 'amount', 'method', 'status', 'received_by', 'reference', 'paid_at',
    ];

    protected function casts(): array
    {
        return [
            'amount' => 'decimal:2',
            'paid_at' => 'datetime',
        ];
    }

    public function booking(): BelongsTo
    {
        return $this->belongsTo(Booking::class);
    }

    public function receivedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'received_by');
    }
}
