<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Indexes for the queries the app runs all the time (found by the code review):
 * a guest's own bookings, the clean-up that runs every minute, the dashboard.
 * PostgreSQL does not index foreign keys by itself. Only adds indexes, changes no data.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('bookings', function (Blueprint $table) {
            $table->index(['user_id', 'status'], 'bookings_user_status_idx');
            $table->index(['status', 'hold_expires_at'], 'bookings_status_hold_idx');
            $table->index('check_in_date', 'bookings_check_in_idx');
        });

        Schema::table('payments', function (Blueprint $table) {
            $table->index('paid_at', 'payments_paid_at_idx');
        });

        Schema::table('payment_intents', function (Blueprint $table) {
            $table->index(['status', 'expires_at'], 'payment_intents_status_expires_idx');
        });
    }

    public function down(): void
    {
        Schema::table('bookings', function (Blueprint $table) {
            $table->dropIndex('bookings_user_status_idx');
            $table->dropIndex('bookings_status_hold_idx');
            $table->dropIndex('bookings_check_in_idx');
        });

        Schema::table('payments', function (Blueprint $table) {
            $table->dropIndex('payments_paid_at_idx');
        });

        Schema::table('payment_intents', function (Blueprint $table) {
            $table->dropIndex('payment_intents_status_expires_idx');
        });
    }
};
