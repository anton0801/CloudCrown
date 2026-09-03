<?php
/**
 * TEMPORARY DIAGNOSTIC — delete after use.
 *
 * Загрузи этот файл в public_html/api/ и открой:
 *   https://cloudcrown-app.space/api/check.php?k=cc-diag-9f3a
 * Покажет версию PHP, наличие .env и ключей, и на каком именно файле
 * падает бутстрап (именно это даёт 500 на всех эндпоинтах, включая health).
 * ПОСЛЕ проверки — УДАЛИ файл с сервера.
 */

if (($_GET['k'] ?? '') !== 'cc-diag-9f3a') {
    http_response_code(404);
    exit;
}

@ini_set('display_errors', '1');
@ini_set('log_errors', '1');
error_reporting(E_ALL);
while (ob_get_level() > 0) { ob_end_flush(); }
header('Content-Type: text/plain; charset=utf-8');

function say(string $s): void { echo $s . "\n"; @flush(); }

say('PHP        : ' . PHP_VERSION);
say('SAPI       : ' . PHP_SAPI);
say('cwd        : ' . __DIR__);
say('');

$env = __DIR__ . '/.env';
say('.env exists : ' . (file_exists($env) ? 'YES' : 'NO'));
say('.env readable: ' . (is_readable($env) ? 'YES' : 'NO'));
say('');

$files = [
    'core/Env.php', 'core/ApiException.php', 'core/Uuid.php', 'core/Clock.php',
    'core/Request.php', 'core/Response.php', 'core/Database.php', 'core/Crypto.php',
    'core/Http.php', 'core/Router.php',
    'security/Jwt.php', 'security/Passwords.php', 'security/RateLimit.php', 'security/Auth.php',
    'controllers/AuthController.php', 'controllers/AccountController.php',
    'controllers/SyncController.php', 'controllers/HorizonController.php',
];

say('--- require each bootstrap file (last "..." before an abrupt stop = broken file) ---');
foreach ($files as $f) {
    $p = __DIR__ . '/' . $f;
    echo str_pad($f, 42) . ' ... '; @flush();
    if (!file_exists($p))    { say('MISSING'); continue; }
    if (!is_readable($p))    { say('UNREADABLE (permissions)'); continue; }
    require $p;              // a compile fatal here stops the script; the "..." above pinpoints it
    say('ok');
}
say('--- all required files loaded ---');
say('');

Env::load($env);
say('APP_ENV     : ' . (Env::get('APP_ENV', '(unset->production)')));
say('PAYLOAD_KEY : ' . (Env::get('PAYLOAD_KEY') ? 'set (' . strlen((string) Env::get('PAYLOAD_KEY')) . ' chars)' : 'MISSING'));
say('JWT_SECRET  : ' . (Env::get('JWT_SECRET') ? 'set' : 'MISSING'));
say('DB_HOST     : ' . (Env::get('DB_HOST') ?: 'MISSING'));
say('DB_NAME     : ' . (Env::get('DB_NAME') ?: 'MISSING'));
say('FORWARD_URL : ' . (Env::get('FORWARD_URL') ? 'set' : '(empty)'));
say('');

try {
    $row = Database::one('SELECT 1 AS ok');
    say('DB connect  : OK');
    $t = Database::one("SHOW TABLES LIKE 'devices'");
    say('devices tbl : ' . ($t ? 'present' : 'MISSING (schema not imported?)'));
} catch (Throwable $e) {
    say('DB connect  : FAIL -> ' . $e->getMessage());
}

try {
    say('Crypto conf : ' . (Crypto::isConfigured() ? 'configured' : 'NOT configured (PAYLOAD_KEY missing/short)'));
} catch (Throwable $e) {
    say('Crypto conf : ERROR -> ' . $e->getMessage());
}

say('');
say('DONE. Удали этот файл после проверки.');
