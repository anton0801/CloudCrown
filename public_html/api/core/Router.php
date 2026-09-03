<?php
declare(strict_types=1);

final class Router
{
    private array $routes = [];

    public function add(string $method, string $pattern, callable $handler): void
    {
        $this->routes[] = [strtoupper($method), $pattern, $handler];
    }

    public function get(string $p, callable $h): void { $this->add('GET', $p, $h); }
    public function post(string $p, callable $h): void { $this->add('POST', $p, $h); }
    public function delete(string $p, callable $h): void { $this->add('DELETE', $p, $h); }

    public function dispatch(Request $request): void
    {
        $allowedForPath = [];
        foreach ($this->routes as [$method, $pattern, $handler]) {
            $params = $this->match($pattern, $request->path);
            if ($params === null) {
                continue;
            }
            if ($method !== $request->method) {
                $allowedForPath[] = $method;
                continue;
            }
            $handler($request->withParams($params));
            return;
        }
        if ($allowedForPath !== []) {
            header('Allow: ' . implode(', ', array_unique($allowedForPath)));
            throw new ApiException(405, 'method_not_allowed', 'That method is not allowed here.');
        }
        throw ApiException::notFound('Unknown endpoint.');
    }

    private function match(string $pattern, string $path): ?array
    {
        $patternParts = explode('/', trim($pattern, '/'));
        $pathParts = explode('/', trim($path, '/'));
        if (count($patternParts) !== count($pathParts)) {
            return null;
        }
        $params = [];
        foreach ($patternParts as $index => $part) {
            if ($part !== '' && $part[0] === ':') {
                $params[substr($part, 1)] = $pathParts[$index];
                continue;
            }
            if ($part !== $pathParts[$index]) {
                return null;
            }
        }
        return $params;
    }
}
