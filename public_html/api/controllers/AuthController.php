<?php
declare(strict_types=1);

final class AuthController
{
    public static function register(Request $request): void
    {
        RateLimit::enforce('register', $request->clientIp(), Env::int('REGISTER_LIMIT', 15), 3600);

        $body = $request->json();
        $credentials = Passwords::validate($body['email'] ?? null, $body['password'] ?? null);

        $existing = Database::one('SELECT id FROM users WHERE email = :email', ['email' => $credentials['email']]);
        if ($existing !== null) {
            throw ApiException::emailTaken();
        }

        $id = Uuid::v4();
        try {
            Database::run(
                'INSERT INTO users (id, email, password_hash, created_at, updated_at)
                 VALUES (:id, :email, :hash, :now, :now2)',
                [
                    'id' => $id,
                    'email' => $credentials['email'],
                    'hash' => Passwords::hash($credentials['password']),
                    'now' => Clock::store(),
                    'now2' => Clock::store(),
                ]
            );
        } catch (PDOException $error) {
            // The unique index is the real authority and closes the race
            // between two simultaneous registrations.
            if ($error->getCode() === '23000') {
                throw ApiException::emailTaken();
            }
            throw $error;
        }

        $user = Database::one(
            'SELECT id, email, created_at, email_verified, token_version FROM users WHERE id = :id',
            ['id' => $id]
        );
        Response::json(Auth::sessionPayload($user, Auth::issueRefreshToken($id)), 201);
    }

    public static function login(Request $request): void
    {
        RateLimit::enforce('login', $request->clientIp(), Env::int('LOGIN_LIMIT', 20), 900);

        $body = $request->json();
        $email = is_string($body['email'] ?? null) ? strtolower(trim($body['email'])) : '';
        $password = is_string($body['password'] ?? null) ? $body['password'] : '';

        $user = Database::one(
            'SELECT id, email, password_hash, created_at, email_verified, token_version
               FROM users WHERE email = :email',
            ['email' => $email]
        );

        // An unknown account still costs a hash comparison, so neither the
        // response nor the timing reveals whether it exists.
        if ($user === null) {
            Passwords::burn($password);
            throw ApiException::invalidCredentials();
        }
        if (!Passwords::verify($password, $user['password_hash'])) {
            throw ApiException::invalidCredentials();
        }

        Response::json(Auth::sessionPayload($user, Auth::issueRefreshToken($user['id'])));
    }

    public static function refresh(Request $request): void
    {
        $body = $request->json();
        $rotated = Auth::rotateRefreshToken($body['refreshToken'] ?? null);
        Response::json(Auth::sessionPayload($rotated['user'], $rotated['refreshToken']));
    }

    public static function logout(Request $request): void
    {
        $userId = Auth::requireUser($request);
        Auth::revokeAllRefreshTokens($userId);
        Auth::invalidateSessions($userId);
        Response::noContent();
    }

    public static function me(Request $request): void
    {
        $userId = Auth::requireUser($request);
        RateLimit::enforce('api', $userId, Env::int('API_LIMIT', 120), 60);

        $user = Database::one(
            'SELECT id, email, created_at, email_verified FROM users WHERE id = :id',
            ['id' => $userId]
        );
        if ($user === null) {
            throw ApiException::notFound('Account not found.');
        }
        Response::json(Auth::publicUser($user));
    }

    public static function changePassword(Request $request): void
    {
        $userId = Auth::requireUser($request);
        RateLimit::enforce('password', $request->clientIp(), Env::int('LOGIN_LIMIT', 20), 900);

        $body = $request->json();
        $current = is_string($body['currentPassword'] ?? null) ? $body['currentPassword'] : '';
        $next = $body['newPassword'] ?? null;

        if (!Passwords::meetsPolicy($next)) {
            throw ApiException::validation('The new password does not meet the requirements.', [
                'newPassword' => 'At least ' . Passwords::MIN_LENGTH . ' characters, with a letter and a number.',
            ]);
        }

        $row = Database::one('SELECT password_hash FROM users WHERE id = :id', ['id' => $userId]);
        if ($row === null || !Passwords::verify($current, $row['password_hash'])) {
            throw ApiException::validation('Your current password is not correct.', [
                'currentPassword' => 'That password is not correct.',
            ]);
        }

        Database::run('UPDATE users SET password_hash = :hash, updated_at = :now WHERE id = :id', [
            'hash' => Passwords::hash((string) $next),
            'now' => Clock::store(),
            'id' => $userId,
        ]);

        Auth::revokeAllRefreshTokens($userId);
        $version = Auth::invalidateSessions($userId);

        // The device that changed the password is not signed out by its own action.
        $user = Database::one('SELECT id, email, created_at, email_verified FROM users WHERE id = :id', ['id' => $userId]);
        $user['token_version'] = $version;
        Response::json(Auth::sessionPayload($user, Auth::issueRefreshToken($userId)));
    }
}
