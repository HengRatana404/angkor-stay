Angkor Stay
Hotel & guesthouse, Siem Reap, Cambodia

Hello,

@if ($purpose === 'reset')
You asked to reset your Angkor Stay password. Enter this code in the app:
@else
Thank you for creating an Angkor Stay account. Enter this code in the app to confirm your email:
@endif

    {{ $code }}

This code works for {{ $minutes }} minutes and can be used once.

Never share this code with anyone. Angkor Stay staff will never ask for it.
@if ($purpose === 'reset')
If you did not ask to reset your password, you can ignore this email. Your password stays the same.
@else
If you did not create an account, you can ignore this email.
@endif

Angkor Stay is a student demo project. This is an automatic message, please do not reply.
