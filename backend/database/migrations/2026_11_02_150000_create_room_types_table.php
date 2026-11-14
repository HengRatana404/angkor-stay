<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('room_types', function (Blueprint $table) {
            $table->id();
            $table->string('name', 60)->unique();
            $table->text('description');
            $table->decimal('price_per_night', 8, 2);
            $table->unsignedTinyInteger('capacity');
            $table->timestamps();
        });

        Schema::create('room_type_images', function (Blueprint $table) {
            $table->id();
            $table->foreignId('room_type_id')->constrained()->cascadeOnDelete();
            $table->string('url', 500);
            $table->unsignedSmallInteger('sort_order')->default(0);
            $table->timestamps();
        });

        Schema::create('rooms', function (Blueprint $table) {
            $table->id();
            $table->string('room_number', 10)->unique();
            // A room type that still has rooms cannot be deleted.
            $table->foreignId('room_type_id')->constrained()->restrictOnDelete();
            $table->unsignedTinyInteger('floor');
            $table->string('status', 20)->default('available'); // available | maintenance
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('rooms');
        Schema::dropIfExists('room_type_images');
        Schema::dropIfExists('room_types');
    }
};
