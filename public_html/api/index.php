<?php
declare(strict_types=1);

foreach ([
    'core/Env.php', 'core/ApiException.php', 'core/Uuid.php', 'core/Clock.php',
    'core/Request.php', 'core/Response.php', 'core/Database.php', 'core/Crypto.php',
    'core/Http.php', 'core/Router.php',
    'security/Jwt.php', 'security/Passwords.php', 'security/RateLimit.php', 'security/Auth.php',
    'controllers/AuthController.php', 'controllers/AccountController.php',
    'controllers/SyncController.php', 'controllers/HorizonController.php',
] as $file) {
    require __DIR__ . '/' . $file;
}

Env::load(__DIR__ . '/.env');

if (Env::isProduction()) {
    ini_set('display_errors', '0');
} else {
    ini_set('display_errors', '1');
}
error_reporting(E_ALL);

$request = new Request();

if ($request->method === 'OPTIONS') {
    http_response_code(204);
    header('Allow: GET, POST, DELETE, OPTIONS');
    exit;
}

if (Env::isProduction() && Env::get('FORCE_HTTPS', 'true') === 'true') {
    $secure = ($_SERVER['HTTPS'] ?? '') !== ''
        || ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https'
        || (int) ($_SERVER['SERVER_PORT'] ?? 0) === 443;
    if (!$secure) {
        Response::error(new ApiException(403, 'https_required', 'This API is only available over HTTPS.'));
        exit;
    }
}

$router = new Router();

$router->get('/v1/health', static function (): void {
    Response::json(['status' => 'ok', 'time' => Clock::iso(Clock::now())]);
});

$router->post('/v1/auth/register', [AuthController::class, 'register']);
$router->post('/v1/auth/login', [AuthController::class, 'login']);
$router->post('/v1/auth/refresh', [AuthController::class, 'refresh']);
$router->post('/v1/auth/logout', [AuthController::class, 'logout']);
$router->get('/v1/auth/me', [AuthController::class, 'me']);
$router->post('/v1/auth/password', [AuthController::class, 'changePassword']);

$router->delete('/v1/account', [AccountController::class, 'destroy']);

$router->get('/v1/sync', [SyncController::class, 'pull']);
$router->post('/v1/sync', [SyncController::class, 'push']);

$router->post('/v1/horizon/observe', [HorizonController::class, 'observe']);
$router->post('/v1/horizon/resolve', [HorizonController::class, 'resolve']);
$router->post('/v1/horizon/link', [HorizonController::class, 'link']);

try {
    $router->dispatch($request);
} catch (ApiException $error) {
    Response::error($error);
} catch (Throwable $error) {
    error_log('[cloudcrown] ' . $error->getMessage() . ' @ ' . $error->getFile() . ':' . $error->getLine());
    Response::error(new ApiException(500, 'internal_error', 'Something went wrong on the server.'));
}
