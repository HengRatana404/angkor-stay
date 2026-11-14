<?php

namespace App\Payments;

use Illuminate\Http\JsonResponse;
use RuntimeException;

/** A payment step that cannot go ahead. It carries the answer the app should get. */
class PaymentException extends RuntimeException
{
    public function __construct(string $message, public readonly string $errorCode, public readonly int $status)
    {
        parent::__construct($message);
    }

    public function toResponse(): JsonResponse
    {
        return response()->json(['message' => $this->getMessage(), 'code' => $this->errorCode], $this->status);
    }
}
