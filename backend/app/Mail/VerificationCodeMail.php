<?php

namespace App\Mail;

use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;

class VerificationCodeMail extends Mailable
{
    public function __construct(
        public string $code,
        public string $purpose,
        public int $minutes,
    ) {
    }

    public function envelope(): Envelope
    {
        // The code is in the subject so the user can read it in the notification.
        $subject = $this->purpose === 'reset'
            ? "{$this->code} is your Angkor Stay password reset code"
            : "{$this->code} is your Angkor Stay verification code";

        return new Envelope(subject: $subject);
    }

    public function content(): Content
    {
        return new Content(
            view: 'emails.code',
            text: 'emails.code-text',
        );
    }
}
