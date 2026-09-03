<?php
declare(strict_types=1);

final class Auth
{
    public static function accessTtl(): int
    {
        return Env::int('ACCESS_TOKEN_TTL_SECONDS', 3600);
    }

    private static function refreshTtlDays(): int
    {
        return Env::int('REFRESH_TOKEN_TTL_DAYS', 60);
    }

    /**
     * Verifies the signature AND that the session is still valid server-side.
     * A signature check alone would keep accepting a token after logout, a
     * password change, or account deletion until it expired.
     */
    public static function requireUser(Request $request): string
    {
        $token = $request->bearerToken();
        if ($token === null) {
            throw ApiException::unauthorized();
        }
        $claims = Jwt::verify($token);
        $userId = (string) ($claims['sub'] ?? '');
        if ($userId === '') {
            throw ApiException::unauthorized();
        }
        $row = Database::one('SELECT token_version FROM users WHERE id = :id', ['id' => $userId]);
        if ($row === null) {
            throw ApiException::unauthorized('This account no longer exists.');
        }
        if ((int) ($claims['ver'] ?? -1) !== (int) $row['token_version']) {
            throw ApiException::unauthorized('Your session ended. Sign in again.');
        }
        return $userId;
    }

    public static function signAccessToken(array $user): string
    {
        return Jwt::sign([
            'sub' => $user['id'],
            'email' => $user['email'],
            'ver' => (int) ($user['token_version'] ?? 0),
        ], self::accessTtl());
    }

    public static function issueRefreshToken(string $userId): string
    {
        $raw = rtrim(strtr(base64_encode(random_bytes(48)), '+/', '-_'), '=');
        Database::run(
            'INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at) VALUES (:id, :user, :hash, :expires)',
            [
                'id' => Uuid::v4(),
                'user' => $userId,
                'hash' => hash('sha256', $raw),
                'expires' => Clock::store(Clock::now()->modify('+' . self::refreshTtlDays() . ' days')),
            ]
        );
        return $raw;
    }

    /** Rotation: the presented token is revoked so it cannot be replayed. */
    public static function rotateRefreshToken(mixed $raw): array
    {
        if (!is_string($raw) || $raw === '') {
            throw ApiException::unauthorized('Your session expired. Sign in again.');
        }
        $row = Database::one(
            'SELECT rt.id AS token_id, rt.user_id, rt.expires_at, rt.revoked_at,
                    u.email, u.created_at, u.email_verified, u.token_version
               FROM refresh_tokens rt JOIN users u ON u.id = rt.user_id
              WHERE rt.token_hash = :hash',
            ['hash' => hash('sha256', $raw)]
        );
        if ($row === null || $row['revoked_at'] !== null) {
            throw ApiException::unauthorized('Your session expired. Sign in again.');
        }
        $expires = Clock::parse($row['expires_at']);
        if ($expires === null || $expires < Clock::now()) {
            throw ApiException::unauthorized('Your session expired. Sign in again.');
        }
        Database::run('UPDATE refresh_tokens SET revoked_at = :now WHERE id = :id', [
            'now' => Clock::store(),
            'id' => $row['token_id'],
        ]);
        return [
            'user' => [
                'id' => $row['user_id'],
                'email' => $row['email'],
                'created_at' => $row['created_at'],
                'email_verified' => $row['email_verified'],
                'token_version' => $row['token_version'],
            ],
            'refreshToken' => self::issueRefreshToken($row['user_id']),
        ];
    }

    public static function revokeAllRefreshTokens(string $userId): void
    {
        Database::run(
            'UPDATE refresh_tokens SET revoked_at = :now WHERE user_id = :user AND revoked_at IS NULL',
            ['now' => Clock::store(), 'user' => $userId]
        );
    }

    /** Retires every access token already handed out; returns the new version. */
    public static function invalidateSessions(string $userId): int
    {
        Database::run('UPDATE users SET token_version = token_version + 1 WHERE id = :id', ['id' => $userId]);
        $row = Database::one('SELECT token_version FROM users WHERE id = :id', ['id' => $userId]);
        return (int) ($row['token_version'] ?? 0);
    }

    public static function sessionPayload(array $user, string $refreshToken): array
    {
        return [
            'accessToken' => self::signAccessToken($user),
            'refreshToken' => $refreshToken,
            'expiresIn' => self::accessTtl(),
            'user' => self::publicUser($user),
        ];
    }

    public static function publicUser(array $user): array
    {
        return [
            'id' => $user['id'],
            'email' => $user['email'],
            'createdAt' => Clock::iso($user['created_at'] ?? null),
            'emailVerified' => (bool) ($user['email_verified'] ?? false),
        ];
    }
}
