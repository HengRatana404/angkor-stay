<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{{ $title }} · Angkor Stay</title>
</head>
<body style="margin:0; padding:24px; background:#FAF6EE; font-family:Arial, Helvetica, sans-serif; color:#3E2A1C;">
    <div style="max-width:420px; margin:48px auto; text-align:center; background:#fff; border:1px solid #E6DCC8; border-radius:8px; padding:32px 24px;">
        <div style="font-size:48px;">{{ $ok ? '✅' : '↩️' }}</div>
        <h1 style="margin:12px 0 8px; font-size:24px;">{{ $title }}</h1>
        <p style="margin:0 0 16px; line-height:1.5;">{{ $text }}</p>
        <p style="margin:0; color:#8A7355; font-size:13px;">Angkor Stay is a student demo project. You can close this page.</p>
    </div>
</body>
</html>
