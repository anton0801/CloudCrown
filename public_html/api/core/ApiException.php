<?php
declare(strict_types=1);

final class ApiException extends RuntimeException
{
    public int $status;
    public string $errorCode;
    public ?array $fields;

    public function __construct(int $status, string $errorCode, string $message, ?array $fields = null)
    {
        parent::__construct($message);
        $this->status = $status;
        $this->errorCode = $errorCode;
        $this->fields = $fields;
    }

    public static function validation(string $message, array $fields = []): self
    {
        return new self(422, 'validation_failed', $message, $fields ?: null);
    }

    public static function invalidCredentials(): self
    {
        return new self(401, 'invalid_credentials', 'Email or password is incorrect.');
    }

    public static function emailTaken(): self
    {
        return new self(409, 'email_already_registered', 'An account already exists for this email.');
    }

    public static function unauthorized(string $message = 'Authentication required.'): self
    {
        return new self(401, 'unauthorized', $message);
    }

    public static function notFound(string $message = 'Not found.'): self
    {
        return new self(404, 'not_found', $message);
    }

    public static function tooLarge(string $message): self
    {
        return new self(413, 'payload_too_large', $message);
    }

    public static function rateLimited(int $retryAfter): self
    {
        return new self(429, 'rate_limited', "Too many attempts. Try again in {$retryAfter} seconds.");
    }
}
