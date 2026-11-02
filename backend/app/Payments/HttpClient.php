<?php

namespace App\Payments;

use Illuminate\Http\Client\PendingRequest;
use Illuminate\Support\Facades\Http;

/**
 * The web client the payment gateways use to talk to Stripe and PayWay.
 *
 * Some PCs (Windows with a plain PHP install) have no list of trusted certificate
 * authorities, so PHP refuses every https site. HTTP_CA_BUNDLE in .env can point
 * to such a list. Checking certificates is never turned off.
 */
class HttpClient
{
    public static function make(): PendingRequest
    {
        $client = Http::timeout(15);

        $bundle = config('services.http.ca_bundle');
        if (is_string($bundle) && $bundle !== '' && is_file($bundle)) {
            $client = $client->withOptions(['verify' => $bundle]);
        }

        return $client;
    }
}
