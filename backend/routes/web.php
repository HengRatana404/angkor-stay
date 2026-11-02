<?php

use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return view('welcome');
});

// The page that sends the guest's browser on to ABA PayWay with a signed form.
Route::get('/payment/payway/{tran}', [\App\Http\Controllers\PaywayPageController::class, 'show'])
    ->where('tran', '[A-Za-z0-9\-]{3,20}');

// Where the payment company sends the guest's browser after the payment page. These pages only
// say "go back to the app". They confirm nothing: the app asks the server, and the
// server asks Stripe, so opening these links by hand can never mark a booking paid.
Route::get('/payment/success', fn () => view('payment-return', [
    'ok' => true,
    'title' => 'Payment received',
    'text' => 'Thank you. Go back to the Angkor Stay app. It will check your payment and confirm your room.',
]));

Route::get('/payment/cancelled', fn () => view('payment-return', [
    'ok' => false,
    'title' => 'Payment cancelled',
    'text' => 'Nothing was charged. Go back to the Angkor Stay app to try again or to pay at the hotel.',
]));
