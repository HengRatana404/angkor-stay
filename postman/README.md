# Angkor Stay: Postman collection

80 saved requests for every endpoint of the API, in 9 folders.

Files:

- `angkor-stay.postman_collection.json` : the requests (with tests). This is the only file you need.

Every request already has its full address, for example `http://127.0.0.1:8000/api/room-types`, like a plain Postman request. **No environment is needed.**

## Import on another PC

1. Start PostgreSQL and the API (`php artisan serve --host=0.0.0.0 --port=8000` in `backend`).
2. Open Postman. Click **Import** and drop in the collection file.
3. Click the collection name, open the **Variables** tab, and type these in the **Current value** column (they stay on your PC):
   - `customer_email` / `customer_password`: any verified guest account
   - `staff_email` / `staff_password`: the staff account (see `backend/.env` `SEED_*`)
   - `admin_email` / `admin_password`: the admin account
   - Leave the three `*_token` values empty. Folder 1 fills them in. Press **Save**.
4. Staff and admin can only log in from the hotel network. On the same PC as the API this is `127.0.0.1`, which is allowed by default. If you are locked out, run `php artisan hotel:network off`.

## How to run

**One request:** open it and press **Send**. Every request has tests. A green "Test Results" tab means the answer was what we expect.

**Everything:** right click the collection, **Run collection**. Run folders **0 to 7**, in order. **Un-tick folder 8.**

Folder 1 logs in and saves the tokens, so it must run first. Later folders save ids such as `booking_a` for the folders after them.

Run results on the last check: 70 requests, 113 checks, 0 failed (with Newman 6.2.3). The other 10 requests (folder 8) are manual only.

## Folders

| Folder | What it shows |
|---|---|
| 0. Start here | health check, public settings |
| 1. Log in | three logins (tokens saved), who am I, wrong password, empty fields |
| 2. Rooms | room types, free rooms for my dates |
| 3. Guest | book (5 minute hold), keep for pay at hotel, cancel, pay online (15% off), verify, release, validation errors |
| 4. Staff | find a booking, take payment (cash, with the staff name saved), refused payments, too-early check-in |
| 5. Admin | dashboard, staff accounts, settings, room types and rooms (create, price, delete), run the automatic jobs |
| 6. Security checks | every one must be refused (401, 403, 404) |
| 7. "No room left" | a one-room type, the first guest takes it, the second gets **409 No room left** |
| 8. Manual only | register, verify email, forgot password, change password, log out (they send real emails or end your session) |

## Screenshots for the slides

| Slide | Request | Expect |
|---|---|---|
| Success | `3. Guest / A: book a Single room` | 201, status pending, countdown |
| Success | `4. Staff / Take payment for B (cash)` | 201, status confirmed, `received_by` is the staff name |
| Success | `5. Admin / Dashboard` | 200, today, rooms, money, pending, 7 days |
| Validation error | `1. Log in / Log in with empty fields` | 422 with a message for each field |
| Validation error | `3. Guest / Book with too many guests` | 422 "A Single room fits up to 2 guests." |
| No room left | `7. Scenario / Guest again: no room left (409)` | 409, code `no_room_left` |
| Security | `6. Security checks / Guest cannot open the admin dashboard` | 403 |

Take the screenshot with the **Body**, the **status code** and the green **Test Results** visible.

Ready-made screenshots of these requests (taken from the Postman app) are in the `screenshots/` folder:

| File | Shows |
|---|---|
| `01-success-book-room-201.png` | book a room, 201 Created, status pending |
| `02-validation-error-too-many-guests-422.png` | 422 "A Single room fits up to 2 guests." |
| `03-success-staff-takes-payment-201.png` | staff takes cash payment, 201, `received_by` is the staff name |
| `04-validation-error-empty-login-422.png` | 422 with a message for each missing field |
| `05-security-guest-blocked-from-admin-403.png` | 403, a guest cannot open the admin dashboard |
| `06-no-room-left-409.png` | 409 `no_room_left` |
| `07-success-admin-dashboard-200.png` | 200, admin dashboard with rooms and money |

## Good to know

- **Rate limits:** the API allows 20 booking requests per minute. If you run the whole collection twice in a row, wait one minute.
- **Pay by card or QR:** the payments are simulated (no bank, no real money). Any card number works, but the expiry date must be `MM/YY` and not in the past: `11/26` is good until the end of November 2026. The QR request returns the KHQR text; "I have paid" makes the server check the payment in the database.
- **Run the automatic jobs now** is in folder 8 (manual only) on purpose: it changes real bookings. It frees old holds and, after 12:00 on the day after check-in, marks guests as no-show and refunds their online payments. Never put it in a collection run, and never run it on a database you cannot lose.
- **Folder 7** leaves one small room type, "Postman One-Room Suite", with its room set to maintenance. It is safe to run again.
- **Folder 5** creates a staff account named "Postman Staff" each run and turns it off again. Accounts are never deleted, so old payments keep the staff name.
- **Settings:** the "Save hotel settings" request sends back the values it just read, so a full run changes nothing. Edit the body to try a change.
