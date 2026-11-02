<?php

namespace Tests\Feature;

use App\Mail\VerificationCodeMail;
use Tests\TestCase;

class VerificationMailTest extends TestCase
{
    public function test_verify_email_has_the_code_in_subject_html_and_text(): void
    {
        $mail = new VerificationCodeMail('482913', 'verify', 10);

        $mail->assertHasSubject('482913 is your Angkor Stay verification code');
        $mail->assertSeeInHtml('482913');
        $mail->assertSeeInHtml('Angkor Stay');
        $mail->assertSeeInHtml('10 minutes');
        $mail->assertSeeInText('482913');
        $mail->assertSeeInText('confirm your email');
    }

    public function test_reset_email_says_it_is_for_a_password_reset(): void
    {
        $mail = new VerificationCodeMail('111222', 'reset', 10);

        $mail->assertHasSubject('111222 is your Angkor Stay password reset code');
        $mail->assertSeeInHtml('reset your Angkor Stay password');
        $mail->assertSeeInText('Your password stays the same');
    }

    public function test_email_warns_never_to_share_the_code(): void
    {
        $mail = new VerificationCodeMail('123456', 'verify', 10);

        $mail->assertSeeInText('Never share this code');
    }
}
