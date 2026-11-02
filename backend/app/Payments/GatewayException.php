<?php

namespace App\Payments;

use RuntimeException;

/** The payment company could not do what we asked (down, refused, wrong key). */
class GatewayException extends RuntimeException
{
}
