<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Hotel settings: defaults
    |--------------------------------------------------------------------------
    |
    | These values are used until the admin changes them in the app.
    | The admin's changes are saved in the `settings` table and win over these.
    |
    */
    'defaults' => [
        // Percent off when the guest pays online.
        'online_discount_percent' => 15,

        'check_in_time' => '14:00',
        'check_out_time' => '12:00',

        // Staff and admin can only use the app from these networks.
        // The default is "any private network" (home and hotel Wi-Fi),
        // never the public internet. The admin narrows it to the real
        // hotel Wi-Fi in the settings screen.
        'staff_login_restricted' => true,
        'allowed_networks' => [
            '127.0.0.1/32',
            '::1/128',
            '10.0.0.0/8',
            '172.16.0.0/12',
            '192.168.0.0/16',
        ],
    ],

    // Secret the phone app sends to learn this PC's Wi-Fi address (GET /api/server-info).
    // Empty = that endpoint is switched off. Put the real value in backend/.env only.
    'server_info_key' => env('SERVER_INFO_KEY'),
    'server_port' => (int) env('HOTEL_SERVER_PORT', 8000),

    // On Wi-Fi where phones cannot reach this PC directly, staff and admin use the tunnel. When true,
    // a visitor coming from this PC's own public address (the same Wi-Fi) counts as the hotel network.
    'trust_same_public_ip' => (bool) env('HOTEL_TRUST_SAME_PUBLIC_IP', false),

    /*
    |--------------------------------------------------------------------------
    | Demo accounts made by `php artisan db:seed`
    |--------------------------------------------------------------------------
    |
    | Put the real values in backend/.env (never in git).
    | If a password is empty, the seeder makes a random one and prints it once.
    |
    */
    'seed' => [
        'admin' => [
            'name' => env('SEED_ADMIN_NAME', 'Hotel Admin'),
            'email' => env('SEED_ADMIN_EMAIL', 'admin@angkorstay.test'),
            'phone' => env('SEED_ADMIN_PHONE', '085000001'),
            'password' => env('SEED_ADMIN_PASSWORD'),
        ],
        'staff' => [
            'name' => env('SEED_STAFF_NAME', 'Front Desk'),
            'email' => env('SEED_STAFF_EMAIL', 'staff@angkorstay.test'),
            'phone' => env('SEED_STAFF_PHONE', '085000002'),
            'password' => env('SEED_STAFF_PASSWORD'),
        ],
    ],

];
