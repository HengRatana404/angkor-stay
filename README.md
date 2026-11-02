# Angkor Stay: hotel booking system

A hotel booking system with three kinds of users (guest, staff, admin). One Flutter mobile app, one Laravel API, one PostgreSQL database, tested with Postman.

| Part | Folder | Tech |
|---|---|---|
| Mobile app | `mobile/` | Flutter 3, Riverpod, dio, Material 3 |
| API | `backend/` | Laravel 13, PHP 8.3+, Sanctum tokens |
| Database | PostgreSQL 18 | 9 tables, see `docs/database-diagram.png` |
| API tests | `postman/` | 76 saved requests with tests |
| Slides and diagram | `docs/` | slides outline, `.pptx`, database diagram |

## What it does

- **Guest:** register with a 6-digit email code, browse room types and photos, see "X rooms left" for chosen dates, book (room is held 5 minutes), pay online (15% off) or at the hotel, QR receipt, cancel with refund, edit profile.
- **Staff:** find a booking, take payment at the desk (cash, card, KHQR), check in and check out. The staff name is saved on every payment.
- **Admin:** dashboard (today, rooms, money, last 7 days, waiting list), room types, prices and rooms, staff accounts, settings (online discount, check-in and check-out times, allowed network, demo payment mode).

Main rules: the room is checked before any payment, a database row lock makes the first guest win, staff and admin can only log in from allowed networks, a guest who never comes becomes a no-show at 12:00 the next day (online money is refunded).

## Run the backend

You need PHP 8.3+, Composer and PostgreSQL.

```bash
cd backend
composer install
cp .env.example .env          # on Windows: copy .env.example .env
php artisan key:generate
```

Create the databases (one for the app, one for the tests):

```bash
createdb angkor_stay
createdb angkor_stay_test
```

Open `backend/.env` and set at least `DB_PASSWORD`, `SEED_ADMIN_PASSWORD` and `SEED_STAFF_PASSWORD` (your own passwords, 8+ characters). Then:

```bash
php artisan migrate --seed    # tables, 3 room types, 15 rooms, 1 admin, 1 staff
php artisan serve --host=0.0.0.0 --port=8000
```

Check it: open http://127.0.0.1:8000/api/health. It should say `"status":"ok"`.

Notes:

- **Emails (verify and reset codes):** by default `MAIL_MAILER=log`, so the code is written to `backend/storage/logs/laravel.log`. For real emails set the `MAIL_*` values (for example Gmail SMTP with an app password).
- **Windows, "cURL error 60":** PHP may have no certificate list. Set `HTTP_CA_BUNDLE` in `.env` to a `ca-bundle.crt` (Git for Windows has one). Never turn certificate checks off.
- **Accounts:** the seeded admin and staff emails are in `.env` (`SEED_ADMIN_EMAIL`, `SEED_STAFF_EMAIL`). Guests register in the app.

### Online payment (sandbox only)

Online payment uses the **ABA PayWay sandbox** (test money). Put your sandbox values in `.env`: `PAYWAY_MERCHANT_ID` and `PAYWAY_PUBLIC_KEY`. Automatic refunds also need the PayWay RSA public key saved as `backend/storage/app/payway_rsa_public.pem`; without it a refund fails safely and the booking is not cancelled. Stripe test keys also work (`STRIPE_SECRET=sk_test_...`), live keys are refused.

For a presentation without real payments, turn on **Demo payment mode** in the app (Admin, Hotel settings). The payment is then faked.

### Helpful commands

```bash
php artisan hotel:network show      # who may log in as staff/admin (also: on, off, or a list of networks)
php artisan hotel:clean-up          # free old holds, mark no-shows, refund online money
php artisan schedule:work           # runs hotel:clean-up every minute
```

If you lock yourself out of the admin account by setting the wrong network, run `php artisan hotel:network off`.

## Run the mobile app

You need Flutter 3 and an Android phone or emulator.

```bash
cd mobile
flutter pub get
flutter run
```

The app talks to the API at an address you can change in the app (gear icon):

- **Android emulator:** the default `http://10.0.2.2:8000/api` works.
- **Real phone on USB:** run `adb reverse tcp:8000 tcp:8000`, then in the app set the address to `http://127.0.0.1:8000/api`.
- **Real phone on Wi-Fi:** use your PC's IP, for example `http://192.168.1.10:8000/api`. The API must run with `--host=0.0.0.0`.

Log in as the seeded admin or staff, or register a guest.

## Tests

```bash
cd backend && php artisan test          # 326 tests (needs the angkor_stay_test database)
cd mobile  && flutter test              # 146 tests
cd mobile  && flutter analyze           # no issues
```

## Postman

Import `postman/angkor-stay.postman_collection.json` and `postman/angkor-stay.postman_environment.json`, fill in the accounts in the environment, and run folders 0 to 7 in order. Details and screenshots: [postman/README.md](postman/README.md).

## Slides and diagram

- Database diagram: `docs/database-diagram.png` (code for dbdiagram.io: `docs/database.dbml`)
- Slide text for Canva: `docs/slides-outline.md`
- Slides as PowerPoint: `docs/Angkor-Stay-slides.pptx`
- Phone screenshots: `docs/screenshots/app/`

## Security

No keys or passwords are in this repository. `backend/.env` is git-ignored; `backend/.env.example` has empty values for every secret.

## Group

[Member 1 name], [Member 2 name], [Member 3 name]

Source code: https://github.com/HengRatana404/angkor-stay · Presentation video: [video link]
