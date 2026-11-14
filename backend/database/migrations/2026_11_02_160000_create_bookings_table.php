<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('bookings', function (Blueprint $table) {
            $table->id();
            // History stays: a user or room with bookings cannot be deleted.
            $table->foreignId('user_id')->constrained()->restrictOnDelete();
            $table->foreignId('room_id')->constrained()->restrictOnDelete();
            $table->date('check_in_date');
            $table->date('check_out_date');
            $table->unsignedTinyInteger('guests');
            $table->unsignedSmallInteger('nights');
            // The price is saved at booking time, so a later price change
            // never changes an old booking.
            $table->decimal('price_per_night', 8, 2);
            $table->decimal('total_price', 10, 2);
            // pending | confirmed | checked_in | checked_out | cancelled | no_show
            $table->string('status', 20)->default('pending')->index();
            // While pending: the room is held until this time. Null = kept
            // until staff act (pay at hotel).
            $table->timestamp('hold_expires_at')->nullable();
            $table->timestamps();

            $table->index(['room_id', 'check_in_date', 'check_out_date']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('bookings');
    }
};
