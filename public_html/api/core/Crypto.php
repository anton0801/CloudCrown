<?php
declare(strict_types=1);

final class Crypto
{
    private const CIPHER = 'aes-256-gcm';
    private const NONCE_BYTES = 12;
    private const TAG_BYTES = 16;

    private static function key(): ?string
    {
        $hex = Env::get('PAYLOAD_KEY', '');
        if ($hex === null || strlen($hex) !== 64 || !ctype_xdigit($hex)) {
            return null;
        }
        return hex2bin($hex) ?: null;
    }

    public static function isConfigured(): bool
    {
        return self::key() !== null;
    }

    /** Layout matches CryptoKit's combined box: nonce || ciphertext || tag. */
    public static function decrypt(string $base64): array
    {
        $key = self::key();
        if ($key === null) {
            throw ApiException::validation('Encrypted payloads are not configured on this server.');
        }
        $blob = base64_decode($base64, true);
        if ($blob === false || strlen($blob) <= self::NONCE_BYTES + self::TAG_BYTES) {
            throw ApiException::validation('Payload is malformed.', ['payload' => 'Malformed.']);
        }
        $nonce = substr($blob, 0, self::NONCE_BYTES);
        $tag = substr($blob, -self::TAG_BYTES);
        $body = substr($blob, self::NONCE_BYTES, strlen($blob) - self::NONCE_BYTES - self::TAG_BYTES);

        $plain = openssl_decrypt($body, self::CIPHER, $key, OPENSSL_RAW_DATA, $nonce, $tag);
        if ($plain === false) {
            throw ApiException::validation('Payload could not be decrypted.', ['payload' => 'Bad key or corrupted data.']);
        }
        $decoded = json_decode($plain, true);
        if (!is_array($decoded)) {
            throw ApiException::validation('Payload is not a JSON object.', ['payload' => 'Malformed.']);
        }
        return $decoded;
    }

    public static function encrypt(array $payload): string
    {
        $key = self::key();
        if ($key === null) {
            throw new RuntimeException('PAYLOAD_KEY is not configured.');
        }
        $nonce = random_bytes(self::NONCE_BYTES);
        $tag = '';
        $body = openssl_encrypt(
            json_encode($payload, JSON_UNESCAPED_SLASHES),
            self::CIPHER,
            $key,
            OPENSSL_RAW_DATA,
            $nonce,
            $tag,
            '',
            self::TAG_BYTES
        );
        if ($body === false) {
            throw new RuntimeException('Encryption failed.');
        }
        return base64_encode($nonce . $body . $tag);
    }

    public static function hashPayload(array $payload): string
    {
        return hash('sha256', json_encode($payload, JSON_UNESCAPED_SLASHES));
    }
}
