<?php
declare(strict_types=1);

final class Request
{
    public string $method;
    public string $path;
    public array $query;
    private ?array $body = null;
    private array $params = [];

    public function __construct()
    {
        $this->method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
        $uri = $_SERVER['REQUEST_URI'] ?? '/';
        $path = parse_url($uri, PHP_URL_PATH) ?: '/';
        $this->path = '/' . trim(self::stripBasePath($path), '/');
        $this->query = $_GET ?? [];
    }

    /**
     * The API works both at a document root and in a subfolder such as
     * /api. The prefix is taken from SCRIPT_NAME so no configuration is
     * needed either way.
     */
    private static function stripBasePath(string $path): string
    {
        $script = $_SERVER['SCRIPT_NAME'] ?? '';
        if ($script === '') {
            return $path;
        }
        $base = rtrim(str_replace('\\', '/', dirname($script)), '/');
        if ($base === '' || $base === '.') {
            return $path;
        }
        if ($path === $base) {
            return '/';
        }
        if (str_starts_with($path, $base . '/')) {
            return substr($path, strlen($base));
        }
        return $path;
    }

    public function withParams(array $params): self
    {
        $clone = clone $this;
        $clone->params = $params;
        return $clone;
    }

    public function param(string $name): ?string
    {
        return $this->params[$name] ?? null;
    }

    public function json(): array
    {
        if ($this->body !== null) {
            return $this->body;
        }
        $raw = file_get_contents('php://input');
        if ($raw === false || $raw === '') {
            return $this->body = [];
        }
        $limit = Env::int('MAX_BODY_BYTES', 4 * 1024 * 1024);
        if (strlen($raw) > $limit) {
            throw ApiException::tooLarge('That request is too large.');
        }
        $decoded = json_decode($raw, true);
        if (!is_array($decoded)) {
            throw new ApiException(400, 'malformed_json', 'The request body is not valid JSON.');
        }
        return $this->body = $decoded;
    }

    /**
     * cPanel/FastCGI commonly strips Authorization, so the .htaccess copies it
     * into REDIRECT_HTTP_AUTHORIZATION. Both spellings are accepted here.
     */
    public function bearerToken(): ?string
    {
        $candidates = [
            $_SERVER['HTTP_AUTHORIZATION'] ?? null,
            $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? null,
        ];
        if (function_exists('apache_request_headers')) {
            $headers = apache_request_headers();
            foreach ($headers as $name => $value) {
                if (strcasecmp($name, 'Authorization') === 0) {
                    $candidates[] = $value;
                }
            }
        }
        foreach ($candidates as $header) {
            if (!is_string($header) || $header === '') {
                continue;
            }
            if (preg_match('/^Bearer\s+(.+)$/i', trim($header), $matches) === 1) {
                return trim($matches[1]);
            }
        }
        return null;
    }

    public function clientIp(): string
    {
        $forwarded = $_SERVER['HTTP_X_FORWARDED_FOR'] ?? '';
        if ($forwarded !== '') {
            $first = trim(explode(',', $forwarded)[0]);
            if ($first !== '') {
                return $first;
            }
        }
        return $_SERVER['REMOTE_ADDR'] ?? '';
    }
}
