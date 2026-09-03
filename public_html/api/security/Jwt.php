<?php
declare(strict_types=1);

final class Jwt
{
    /** Hard-coded so a token claiming alg=none or RS256 can never be accepted. */
    private const ALGORITHM = 'HS256';
    private const ISSUER = 'cloudcrown-api';

    public static function sign(array $claims, int $ttlSeconds): string
    {
        $now = time();
        $payload = array_merge($claims, [
            'iss' => self::ISSUER,
            'iat' => $now,
            'exp' => $now + $ttlSeconds,
        ]);
        $header = self::base64(json_encode(['alg' => self::ALGORITHM, 'typ' => 'JWT']));
        $body = self::base64(json_encode($payload));
        $signature = self::base64(self::mac("{$header}.{$body}"));
        return "{$header}.{$body}.{$signature}";
    }

    public static function verify(string $token): array
    {
        $parts = explode('.', $token);
        if (count($parts) !== 3) {
            throw ApiException::unauthorized('Your session expired. Sign in again.');
        }
        [$header, $body, $signature] = $parts;

        $decodedHeader = json_decode(self::unbase64($header) ?: '', true);
        if (!is_array($decodedHeader) || ($decodedHeader['alg'] ?? '') !== self::ALGORITHM) {
            throw ApiException::unauthorized('Your session expired. Sign in again.');
        }

        $expected = self::base64(self::mac("{$header}.{$body}"));
        if (!hash_equals($expected, $signature)) {
            throw ApiException::unauthorized('Your session expired. Sign in again.');
        }

        $claims = json_decode(self::unbase64($body) ?: '', true);
        if (!is_array($claims)) {
            throw ApiException::unauthorized('Your session expired. Sign in again.');
        }
        if (($claims['iss'] ?? '') !== self::ISSUER) {
            throw ApiException::unauthorized('Your session expired. Sign in again.');
        }
        if (!isset($claims['exp']) || time() >= (int) $claims['exp']) {
            throw ApiException::unauthorized('Your session expired. Sign in again.');
        }
        return $claims;
    }

    private static function mac(string $data): string
    {
        return hash_hmac('sha256', $data, Env::require('JWT_SECRET'), true);
    }

    private static function base64(string $raw): string
    {
        return rtrim(strtr(base64_encode($raw), '+/', '-_'), '=');
    }

    private static function unbase64(string $encoded): string|false
    {
        return base64_decode(strtr($encoded, '-_', '+/'), true);
    }
}
