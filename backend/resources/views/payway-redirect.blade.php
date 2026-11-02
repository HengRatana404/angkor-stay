<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Opening PayWay · Angkor Stay</title>
</head>
<body style="margin:0; padding:24px; background:#FAF6EE; font-family:Arial, Helvetica, sans-serif; color:#3E2A1C;">
    <div style="max-width:420px; margin:48px auto; text-align:center; background:#fff; border:1px solid #E6DCC8; border-radius:8px; padding:32px 24px;">
        <h1 style="margin:0 0 8px; font-size:22px;">Opening the secure payment page…</h1>
        <p style="margin:0 0 16px; line-height:1.5;">You are being sent to ABA PayWay to pay. Please wait a moment.</p>

        <form id="payway" method="POST" action="{{ $action }}">
            @foreach ($fields as $name => $value)
                <input type="hidden" name="{{ $name }}" value="{{ $value }}">
            @endforeach
            <noscript>
                <button type="submit" style="padding:12px 24px; font-size:16px;">Continue to PayWay</button>
            </noscript>
        </form>

        <p style="margin:16px 0 0; color:#8A7355; font-size:13px;">Angkor Stay is a student demo project. Sandbox payment: no real money moves.</p>
    </div>
    <script>document.getElementById('payway').submit();</script>
</body>
</html>
