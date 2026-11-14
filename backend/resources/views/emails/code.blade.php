<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Angkor Stay</title>
</head>
<body style="margin:0; padding:24px; background:#FAF6EE; font-family:Arial, Helvetica, sans-serif; color:#3E2A1C;">
    <div style="max-width:440px; margin:0 auto; background:#ffffff; border:1px solid #E6DCC8; border-radius:8px; padding:24px;">
        <h2 style="margin:0 0 4px; color:#3E2A1C;">Angkor Stay</h2>
        <p style="margin:0 0 20px; color:#8A7355; font-size:13px;">Hotel &amp; guesthouse, Siem Reap, Cambodia</p>

        <p style="margin:0 0 8px;">Hello,</p>
        <p style="margin:0 0 16px;">
            @if ($purpose === 'reset')
                You asked to reset your Angkor Stay password. Enter this code in the app:
            @else
                Thank you for creating an Angkor Stay account. Enter this code in the app to confirm your email:
            @endif
        </p>

        <p style="margin:0 0 16px; padding:12px; background:#FAF6EE; text-align:center; font-size:30px; letter-spacing:8px; font-weight:bold; color:#3E2A1C;">{{ $code }}</p>

        <p style="margin:0 0 8px;">This code works for {{ $minutes }} minutes and can be used once.</p>
        <p style="margin:0 0 20px; color:#6B5A44; font-size:13px;">
            Never share this code with anyone. Angkor Stay staff will never ask for it.
            @if ($purpose === 'reset')
                If you did not ask to reset your password, you can ignore this email. Your password stays the same.
            @else
                If you did not create an account, you can ignore this email.
            @endif
        </p>

        <p style="margin:0; color:#8A7355; font-size:12px;">
            Angkor Stay is a student demo project. This is an automatic message, please do not reply.
        </p>
    </div>
</body>
</html>
