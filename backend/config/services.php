<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Third Party Services
    |--------------------------------------------------------------------------
    |
    | This file is for storing the credentials for third party services such
    | as Resend, Postmark, AWS, and more. This file provides the de facto
    | location for this type of information, allowing packages to have
    | a conventional file to locate the various service credentials.
    |
    */

    'postmark' => [
        'key' => env('POSTMARK_API_KEY'),
    ],

    'resend' => [
        'key' => env('RESEND_API_KEY'),
    ],

    'ses' => [
        'key' => env('AWS_ACCESS_KEY_ID'),
        'secret' => env('AWS_SECRET_ACCESS_KEY'),
        'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
    ],

    // A file of trusted certificate authorities, for PCs where PHP has none (Windows).
    // Example: HTTP_CA_BUNDLE="C:\Program Files\Git\usr\ssl\certs\ca-bundle.crt"
    'http' => [
        'ca_bundle' => env('HTTP_CA_BUNDLE'),
    ],

    // ABA PayWay SANDBOX (Cambodia). Values come by email after registering at
    // developer.payway.com.kh. The "Public Key" they send is the secret used to sign requests.
    // The RSA public key is only needed for refunds: save it as a file and give its path.
    'payway' => [
        'merchant_id' => env('PAYWAY_MERCHANT_ID'),
        'api_key' => env('PAYWAY_PUBLIC_KEY'),
        'base_url' => env('PAYWAY_BASE_URL', 'https://checkout-sandbox.payway.com.kh'),
        'rsa_public_key_path' => env('PAYWAY_RSA_PUBLIC_KEY_PATH', storage_path('app/payway_rsa_public.pem')),
    ],

    // Stripe test mode. Put the secret key (sk_test_...) in backend/.env as STRIPE_SECRET.
    // Live keys (sk_live_...) are refused on purpose: this is a school project.
    'stripe' => [
        'secret' => env('STRIPE_SECRET'),
    ],

    'slack' => [
        'notifications' => [
            'bot_user_oauth_token' => env('SLACK_BOT_USER_OAUTH_TOKEN'),
            'channel' => env('SLACK_BOT_USER_DEFAULT_CHANNEL'),
        ],
    ],

];
