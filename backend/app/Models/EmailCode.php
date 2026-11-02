<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class EmailCode extends Model
{
    protected $fillable = ['email', 'purpose', 'code_hash', 'attempts', 'expires_at'];

    protected function casts(): array
    {
        return [
            'expires_at' => 'datetime',
        ];
    }
}
