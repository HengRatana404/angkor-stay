<?php

namespace App\Http\Controllers;

use App\Payments\PaywayGateway;

/**
 * The page the guest's browser opens to pay with PayWay. It shows nothing but sends the
 * guest straight on to PayWay with a signed form. It confirms nothing about any payment.
 */
class PaywayPageController extends Controller
{
    public function show(string $tran, PaywayGateway $gateway)
    {
        $page = $gateway->pageFor($tran);

        if ($page === null) {
            return response()->view('payment-return', [
                'ok' => false,
                'title' => 'This payment page is closed',
                'text' => 'It was cancelled or it is too old. Go back to the Angkor Stay app to start again or to pay at the hotel.',
            ], 410);
        }

        return view('payway-redirect', $page);
    }
}
