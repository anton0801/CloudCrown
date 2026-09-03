<?php
declare(strict_types=1);

final class Http
{
    /** @return array{status:?int, body:string, error:?string} */
    public static function postJson(string $url, array $payload, int $timeoutMs): array
    {
        $body = json_encode($payload, JSON_UNESCAPED_SLASHES);

        if (function_exists('curl_init')) {
            $handle = curl_init($url);
            curl_setopt_array($handle, [
                CURLOPT_POST => true,
                CURLOPT_POSTFIELDS => $body,
                CURLOPT_HTTPHEADER => ['Content-Type: application/json', 'Accept: application/json'],
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_TIMEOUT_MS => $timeoutMs,
                CURLOPT_CONNECTTIMEOUT_MS => min($timeoutMs, 8000),
                CURLOPT_FOLLOWLOCATION => false,
            ]);
            $response = curl_exec($handle);
            $status = curl_getinfo($handle, CURLINFO_RESPONSE_CODE);
            $error = curl_errno($handle) !== 0 ? curl_error($handle) : null;
            // No curl_close(): it is a no-op since PHP 8.0 and emits a
            // deprecation notice on 8.5 that would corrupt the JSON response.
            return [
                'status' => $status > 0 ? $status : null,
                'body' => is_string($response) ? $response : '',
                'error' => $error,
            ];
        }

        $context = stream_context_create(['http' => [
            'method' => 'POST',
            'header' => "Content-Type: application/json\r\nAccept: application/json\r\n",
            'content' => $body,
            'timeout' => $timeoutMs / 1000,
            'ignore_errors' => true,
        ]]);
        $response = @file_get_contents($url, false, $context);
        $status = null;
        $headers = function_exists('http_get_last_response_headers')
            ? (http_get_last_response_headers() ?? [])
            : [];
        if (isset($headers[0]) && preg_match('/\s(\d{3})\s/', $headers[0], $m) === 1) {
            $status = (int) $m[1];
        }
        return [
            'status' => $status,
            'body' => is_string($response) ? $response : '',
            'error' => $response === false ? 'request failed' : null,
        ];
    }
}
