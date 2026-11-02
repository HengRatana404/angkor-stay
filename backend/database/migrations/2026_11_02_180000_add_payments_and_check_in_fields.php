<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('bookings', function (Blueprint $table) {
            // How the guest chose to pay: hotel | online. Empty until they choose.
            $table->string('payment_choice', 10)->nullable()->after('status');

            // Which staff member did it, and when. Staff cannot be deleted
            // (they are turned off instead), so these always point to a person.
            $table->timestamp('checked_in_at')->nullable();
            $table->foreignId('checked_in_by')->nullable()->constrained('users')->restrictOnDelete();
            $table->timestamp('checked_out_at')->nullable();
            $table->foreignId('checked_out_by')->nullable()->constrained('users')->restrictOnDelete();
        });

        Schema::create('payments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('booking_id')->constrained()->restrictOnDelete();
            $table->decimal('amount', 10, 2);
            $table->string('method', 10); // khqr | cash | card | online
            $table->string('status', 10)->default('paid'); // paid | refunded
            // The staff member who took the money at the hotel.
            // Empty for online payments, which nobody receives by hand.
            $table->foreignId('received_by')->nullable()->constrained('users')->restrictOnDelete();
            $table->string('reference')->nullable();
            $table->timestamp('paid_at');
            $table->timestamps();

            $table->index(['booking_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('payments');

        Schema::table('bookings', function (Blueprint $table) {
            $table->dropConstrainedForeignId('checked_in_by');
            $table->dropConstrainedForeignId('checked_out_by');
            $table->dropColumn(['payment_choice', 'checked_in_at', 'checked_out_at']);
        });
    }
};
