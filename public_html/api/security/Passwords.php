<?php
declare(strict_types=1);

final class Passwords
{
    public const MIN_LENGTH = 8;

    private static function algorithm(): string
    {
        // Argon2id where the host supports it; bcrypt is the portable fallback
        // on shared hosting built without libargon2.
        return defined('PASSWORD_ARGON2ID') && in_array(PASSWORD_ARGON2ID, password_algos(), true)
            ? PASSWORD_ARGON2ID
            : PASSWORD_BCRYPT;
    }

    public static function hash(string $plain): string
    {
        $algorithm = self::algorithm();
        $options = $algorithm === PASSWORD_BCRYPT
            ? ['cost' => 12]
            : ['memory_cost' => 65536, 'time_cost' => 4, 'threads' => 2];
        $hash = password_hash($plain, $algorithm, $options);
        if (!is_string($hash)) {
            throw new RuntimeException('Password hashing failed.');
        }
        return $hash;
    }

    public static function verify(string $plain, string $hash): bool
    {
        return password_verify($plain, $hash);
    }

    /** Keeps timing steady when the account does not exist. */
    public static function burn(string $plain): void
    {
        password_verify($plain, '$2y$12$usesomesillystringfooooooooooooooooooooooooooooooooooooooo');
    }

    /** @return array{email:string,password:string} */
    public static function validate(mixed $email, mixed $password): array
    {
        $fields = [];
        $normalized = is_string($email) ? strtolower(trim($email)) : '';
        if ($normalized === '') {
            $fields['email'] = 'Enter your email address.';
        } elseif (preg_match('/^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$/', $normalized) !== 1) {
            $fields['email'] = 'That does not look like an email address.';
        }

        $plain = is_string($password) ? $password : '';
        if ($plain === '') {
            $fields['password'] = 'Enter a password.';
        } elseif (strlen($plain) < self::MIN_LENGTH) {
            $fields['password'] = 'Use at least ' . self::MIN_LENGTH . ' characters.';
        } elseif (preg_match('/\d/', $plain) !== 1) {
            $fields['password'] = 'Include at least one number.';
        } elseif (preg_match('/[A-Za-z]/', $plain) !== 1) {
            $fields['password'] = 'Include at least one letter.';
        }

        if ($fields !== []) {
            throw ApiException::validation('Please check the highlighted fields.', $fields);
        }
        return ['email' => $normalized, 'password' => $plain];
    }

    public static function meetsPolicy(mixed $password): bool
    {
        return is_string($password)
            && strlen($password) >= self::MIN_LENGTH
            && preg_match('/\d/', $password) === 1
            && preg_match('/[A-Za-z]/', $password) === 1;
    }
}
