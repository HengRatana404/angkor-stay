<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // One row for every card or QR payment the guest starts. The server checks THIS row
        // (not the app) before it marks a booking paid. Payments are simulated: no real money moves.
        Schema::create('payment_intents', function (Blueprint $table) {
            $table->id();
            $table->foreignId('booking_id')->constrained()->restrictOnDelete();
            $table->string('channel', 10);          // card | khqr
            $table->decimal('amount', 10, 2);       // what must be paid, after the online discount
            $table->string('status', 12)->default('pending'); // pending | paid | cancelled | expired | refunded
            $table->string('reference', 30)->unique(); // shown to the guest, saved on the payment
            $table->text('qr_payload')->nullable();    // the text inside the QR code (QR payments only)
            $table->string('card_brand', 20)->nullable();
            $table->string('card_last4', 4)->nullable(); // only the last 4 digits are ever kept
            $table->timestamp('expires_at');
            $table->timestamp('paid_at')->nullable();
            $table->timestamps();

            $table->index(['booking_id', 'status']);
        });

        // The old "open payment page" id is not needed any more.
        Schema::table('bookings', function (Blueprint $table) {
            $table->dropColumn('checkout_session_id');
        });

        // Online payment is always simulated now, so the demo-mode switch is gone.
        DB::table('settings')->where('key', 'demo_payment_mode')->delete();
    }

    public function down(): void
    {
        Schema::table('bookings', function (Blueprint $table) {
            $table->string('checkout_session_id')->nullable()->index();
        });

        Schema::dropIfExists('payment_intents');
    }
};
