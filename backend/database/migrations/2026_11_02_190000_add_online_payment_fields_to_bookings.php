<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('bookings', function (Blueprint $table) {
            // The online discount, saved when the guest starts paying online, so a later
            // change of the setting never changes this booking. 0 for pay-at-hotel.
            // The price to pay is total_price minus discount_amount.
            $table->unsignedSmallInteger('discount_percent')->default(0);
            $table->decimal('discount_amount', 10, 2)->default(0);

            // The Stripe Checkout page the guest is paying on. Empty when nothing is open.
            $table->string('checkout_session_id')->nullable()->index();
        });
    }

    public function down(): void
    {
        Schema::table('bookings', function (Blueprint $table) {
            $table->dropColumn(['discount_percent', 'discount_amount', 'checkout_session_id']);
        });
    }
};
