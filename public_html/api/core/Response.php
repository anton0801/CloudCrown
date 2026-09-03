<?php
declare(strict_types=1);

final class Response
{
    public static function json(mixed $payload, int $status = 200, array $headers = []): void
    {
        http_response_code($status);
        header('Content-Type: application/json; charset=utf-8');
        header('X-Content-Type-Options: nosniff');
        foreach ($headers as $name => $value) {
            header($name . ': ' . $value);
        }
        echo json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    }

    public static function noContent(): void
    {
        http_response_code(204);
        header('X-Content-Type-Options: nosniff');
    }

    public static function error(ApiException $error): void
    {
        $body = ['code' => $error->errorCode, 'message' => $error->getMessage()];
        if ($error->fields !== null) {
            $body['fields'] = $error->fields;
        }
        $headers = [];
        if ($error->status === 429) {
            $headers['Retry-After'] = '60';
        }
        self::json(['error' => $body], $error->status, $headers);
    }
}
