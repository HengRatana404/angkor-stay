<?php

namespace App\Payments;

use Carbon\CarbonInterface;

/**
 * The text inside a payment QR code, written in the EMV QR format that Cambodia's KHQR uses
 * (the same layout banking apps read). The merchant account is a DEMO account, so a real
 * banking app can read the code but nobody is ever paid: the payment is simulated.
 *
 * Layout: tag (2 digits) + length (2 digits) + value, repeated, and a CRC-16 on the end.
 */
final class KhqrPayload
{
    public const DEMO_ACCOUNT = 'angkorstay@demo';
    public const MERCHANT_NAME = 'Angkor Stay';
    public const CITY = 'Phnom Penh';

    public static function build(string $billNumber, float $amount, CarbonInterface $expiresAt): string
    {
        $created = now();

        $body = self::tlv('00', '01')                                   // format version
            . self::tlv('01', '12')                                     // 12 = a one-time (dynamic) code
            . self::tlv('29', self::tlv('00', self::DEMO_ACCOUNT))      // merchant account (demo)
            . self::tlv('52', '7011')                                   // category: hotels
            . self::tlv('53', '840')                                    // currency: US dollar
            . self::tlv('54', number_format($amount, 2, '.', ''))       // amount
            . self::tlv('58', 'KH')
            . self::tlv('59', self::MERCHANT_NAME)
            . self::tlv('60', self::CITY)
            . self::tlv('62', self::tlv('01', $billNumber) . self::tlv('07', 'APP')) // bill number, terminal
            . self::tlv('99', self::tlv('00', (string) $created->getTimestampMs())
                . self::tlv('01', (string) $expiresAt->getTimestampMs())); // created and expiry time

        $withCrcTag = $body . '6304';

        return $withCrcTag . self::crc16($withCrcTag);
    }

    /** Is the code whole? The last 4 characters must be the CRC of everything before them. */
    public static function isValid(string $payload): bool
    {
        if (strlen($payload) < 8 || substr($payload, -8, 4) !== '6304') {
            return false;
        }

        return strtoupper(substr($payload, -4)) === self::crc16(substr($payload, 0, -4));
    }

    /** Reads the top-level tags into ['tag' => 'value']. */
    public static function parse(string $payload): array
    {
        $out = [];
        $i = 0;
        while ($i + 4 <= strlen($payload)) {
            $tag = substr($payload, $i, 2);
            $len = (int) substr($payload, $i + 2, 2);
            $out[$tag] = substr($payload, $i + 4, $len);
            $i += 4 + $len;
        }

        return $out;
    }

    private static function tlv(string $tag, string $value): string
    {
        return $tag . str_pad((string) strlen($value), 2, '0', STR_PAD_LEFT) . $value;
    }

    /** CRC-16/CCITT-FALSE, as the EMV QR standard asks. Upper-case hex, 4 characters. */
    private static function crc16(string $data): string
    {
        $crc = 0xFFFF;
        foreach (str_split($data) as $char) {
            $crc ^= ord($char) << 8;
            for ($bit = 0; $bit < 8; $bit++) {
                $crc = ($crc & 0x8000) ? (($crc << 1) ^ 0x1021) : ($crc << 1);
                $crc &= 0xFFFF;
            }
        }

        return strtoupper(str_pad(dechex($crc), 4, '0', STR_PAD_LEFT));
    }
}
