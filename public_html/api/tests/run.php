<?php
declare(strict_types=1);

require __DIR__ . '/../core/Env.php';
require __DIR__ . '/../core/ApiException.php';
require __DIR__ . '/../core/Database.php';
require __DIR__ . '/../core/Crypto.php';
Env::load(__DIR__ . '/../.env');

if (Env::get('DB_NAME') === null) {
    fwrite(STDERR, "No .env found. Copy .env.example to .env and point DB_* at a\n"
        . "test database before running the suite.\n");
    exit(2);
}

$base = getenv('CC_TEST_BASE') ?: 'http://127.0.0.1:8899/v1';
$pass = 0;
$fail = 0;
$failures = [];

function section(string $name): void { echo "\n{$name}\n"; }

function check(string $label, bool $ok, string $detail = ''): void
{
    global $pass, $fail, $failures;
    if ($ok) {
        $pass++;
        echo "   PASS  {$label}\n";
    } else {
        $fail++;
        $failures[] = $label;
        echo "   FAIL  {$label}" . ($detail !== '' ? " — {$detail}" : '') . "\n";
    }
}

/** @return array{status:int, body:array, headers:array} */
function call(string $path, string $method = 'GET', ?array $body = null, ?string $token = null, ?string $raw = null): array
{
    global $base;
    $handle = curl_init($base . $path);
    $headers = ['Accept: application/json', 'Content-Type: application/json'];
    if ($token !== null) {
        $headers[] = 'Authorization: Bearer ' . $token;
    }
    $payload = $raw ?? ($body === null ? null : json_encode($body, JSON_UNESCAPED_SLASHES));
    $parsedHeaders = [];
    curl_setopt_array($handle, [
        CURLOPT_CUSTOMREQUEST => $method,
        CURLOPT_HTTPHEADER => array_merge($headers, ['Expect:']),
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 20,
        // Collected separately: mixing headers into the body breaks as soon as
        // an interim 100-continue response appears.
        CURLOPT_HEADERFUNCTION => static function ($handle, string $line) use (&$parsedHeaders): int {
            if (str_contains($line, ':')) {
                [$name, $value] = explode(':', $line, 2);
                $parsedHeaders[strtolower(trim($name))] = trim($value);
            }
            return strlen($line);
        },
    ]);
    if ($payload !== null) {
        curl_setopt($handle, CURLOPT_POSTFIELDS, $payload);
    }
    $response = curl_exec($handle);
    $status = (int) curl_getinfo($handle, CURLINFO_RESPONSE_CODE);
    $rawBody = is_string($response) ? $response : '';
    $decoded = json_decode($rawBody, true);
    return ['status' => $status, 'body' => is_array($decoded) ? $decoded : [], 'headers' => $parsedHeaders];
}

$sealed = static fn(array $data): array => ['payload' => Crypto::encrypt($data)];
$uuid = static function (): string {
    $b = random_bytes(16);
    $b[6] = chr((ord($b[6]) & 0x0f) | 0x40);
    $b[8] = chr((ord($b[8]) & 0x3f) | 0x80);
    return vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($b), 4));
};
$iso = static fn(int $offsetSeconds = 0): string =>
    (new DateTimeImmutable("@" . (time() + $offsetSeconds)))->format('Y-m-d\TH:i:s.v\Z');
$suffix = bin2hex(random_bytes(4));

// The suite creates several accounts, which would trip the registration limit
// on a second run. Counters are test state, so they start clean.
Database::run('DELETE FROM rate_limits');

// ---------------------------------------------------------------- health
section('HEALTH');
$r = call('/health');
check('health endpoint', $r['status'] === 200 && ($r['body']['status'] ?? '') === 'ok', "got {$r['status']}");

$r = call('/nope');
check('unknown endpoint is 404', $r['status'] === 404, "got {$r['status']}");
$r = call('/health', 'DELETE');
check('wrong method is 405', $r['status'] === 405, "got {$r['status']}");

// ------------------------------------------------------------------ auth
section('AUTH');
$email = "anton-{$suffix}@example.com";

$r = call('/auth/register', 'POST', ['email' => $email, 'password' => 'short']);
check('weak password rejected', $r['status'] === 422 && isset($r['body']['error']['fields']['password']));

$r = call('/auth/register', 'POST', ['email' => 'not-an-email', 'password' => 'GoodPass1']);
check('bad email rejected', $r['status'] === 422 && isset($r['body']['error']['fields']['email']));

$r = call('/auth/register', 'POST', ['email' => ['$ne' => null], 'password' => 'GoodPass1']);
check('object injected as email rejected', $r['status'] === 422, "got {$r['status']}");

$r = call('/auth/register', 'POST', ['email' => strtoupper($email), 'password' => 'GoodPass1']);
check('registration succeeds', $r['status'] === 201 && !empty($r['body']['accessToken']), json_encode($r['body']));
check('email normalised to lowercase', ($r['body']['user']['email'] ?? '') === $email);
$access = $r['body']['accessToken'] ?? '';
$refresh = $r['body']['refreshToken'] ?? '';
$userId = $r['body']['user']['id'] ?? '';
check('expiresIn reported', ($r['body']['expiresIn'] ?? 0) === 3600);

$r = call('/auth/register', 'POST', ['email' => $email, 'password' => 'GoodPass1']);
check('duplicate email rejected case-insensitively',
    $r['status'] === 409 && ($r['body']['error']['code'] ?? '') === 'email_already_registered');

$r = call('/auth/login', 'POST', ['email' => $email, 'password' => 'WrongPass1']);
check('wrong password rejected', $r['status'] === 401 && ($r['body']['error']['code'] ?? '') === 'invalid_credentials');

$r = call('/auth/login', 'POST', ['email' => "nobody-{$suffix}@example.com", 'password' => 'GoodPass1']);
check('unknown account gives the same error', $r['status'] === 401 && ($r['body']['error']['code'] ?? '') === 'invalid_credentials');

$r = call('/auth/login', 'POST', ['email' => $email, 'password' => 'GoodPass1']);
check('login succeeds', $r['status'] === 200 && !empty($r['body']['accessToken']));

$r = call('/auth/me', 'GET', null, $access);
check('authenticated profile', $r['status'] === 200 && ($r['body']['email'] ?? '') === $email, json_encode($r['body']));
check('Authorization header survives the rewrite', $r['status'] === 200);

check('missing token rejected', call('/auth/me')['status'] === 401);
check('invalid token rejected', call('/auth/me', 'GET', null, 'garbage')['status'] === 401);

// --------------------------------------------------------------- forgery
section('TOKEN FORGERY');
$parts = explode('.', $access);
check('stripped signature rejected', call('/auth/me', 'GET', null, "{$parts[0]}.{$parts[1]}.")['status'] === 401);
$noneHeader = rtrim(strtr(base64_encode(json_encode(['alg' => 'none', 'typ' => 'JWT'])), '+/', '-_'), '=');
check('alg=none rejected', call('/auth/me', 'GET', null, "{$noneHeader}.{$parts[1]}.")['status'] === 401);
$other = call('/auth/register', 'POST', ['email' => "victim-{$suffix}@example.com", 'password' => 'GoodPass1']);
if (empty($other['body']['accessToken'])) {
    fwrite(STDERR, "Could not create the second test account (status {$other['status']}). "
        . "If this is 429, clear the rate_limits table and retry.\n");
    exit(2);
}
$otherParts = explode('.', $other['body']['accessToken']);
check('swapped signature rejected',
    call('/auth/me', 'GET', null, "{$parts[0]}.{$parts[1]}.{$otherParts[2]}")['status'] === 401);

// ---------------------------------------------------------------- rotate
section('TOKEN ROTATION');
$r = call('/auth/refresh', 'POST', ['refreshToken' => $refresh]);
check('refresh issues a new pair', $r['status'] === 200 && ($r['body']['refreshToken'] ?? '') !== $refresh, "got {$r['status']}");
$rotated = $r['body']['refreshToken'] ?? '';
$access = $r['body']['accessToken'] ?? $access;
check('used refresh token cannot be replayed', call('/auth/refresh', 'POST', ['refreshToken' => $refresh])['status'] === 401);
$r = call('/auth/refresh', 'POST', ['refreshToken' => $rotated]);
check('current refresh token still works', $r['status'] === 200);
$rotated = $r['body']['refreshToken'] ?? $rotated;
$access = $r['body']['accessToken'] ?? $access;

// ------------------------------------------------------------------ sync
section('SYNC');
$placeId = $uuid();
$planId = $uuid();
$t0 = $iso(-60);

$r = call('/sync', 'POST', [
    'clientTime' => $iso(),
    'places' => [['id' => $placeId, 'name' => 'Berlin', 'updatedAt' => $t0]],
    'plans' => [['id' => $planId, 'title' => 'Walk', 'updatedAt' => $t0]],
    'tombstones' => [],
], $access);
check('push accepted', $r['status'] === 200 && ($r['body']['accepted'] ?? 0) === 2, json_encode($r['body']));

$r = call('/sync', 'GET', null, $access);
check('pull returns pushed records', count($r['body']['places'] ?? []) === 1 && count($r['body']['plans'] ?? []) === 1);
check('payload round-trips intact', ($r['body']['places'][0]['name'] ?? '') === 'Berlin');
$serverTime = $r['body']['serverTime'] ?? '';

call('/sync', 'POST', ['clientTime' => $iso(), 'places' => [['id' => $placeId, 'name' => 'STALE', 'updatedAt' => $iso(-600)]]], $access);
$r = call('/sync', 'GET', null, $access);
check('older write does not overwrite newer', ($r['body']['places'][0]['name'] ?? '') === 'Berlin');

call('/sync', 'POST', ['clientTime' => $iso(), 'places' => [['id' => $placeId, 'name' => 'Berlin Mitte', 'updatedAt' => $iso(60)]]], $access);
$r = call('/sync', 'GET', null, $access);
check('newer write wins', ($r['body']['places'][0]['name'] ?? '') === 'Berlin Mitte');

$r = call('/sync?since=' . urlencode($serverTime), 'GET', null, $access);
check('delta pull returns only changed records',
    count($r['body']['places'] ?? []) === 1 && count($r['body']['plans'] ?? []) === 0,
    'places=' . count($r['body']['places'] ?? []) . ' plans=' . count($r['body']['plans'] ?? []));

$r = call('/sync', 'POST', ['clientTime' => $iso(), 'tombstones' => [
    ['entityType' => 'plan', 'entityID' => $planId, 'deletedAt' => $iso(120)],
]], $access);
check('tombstone accepted', $r['status'] === 200);
$r = call('/sync', 'GET', null, $access);
check('deleted record no longer returned', count($r['body']['plans'] ?? []) === 0);
$found = false;
foreach ($r['body']['tombstones'] ?? [] as $stone) {
    if (($stone['entityID'] ?? '') === $planId) { $found = true; }
}
check('deletion surfaces as a tombstone', $found);

$r = call('/sync', 'POST', ['clientTime' => $iso(), 'places' => [['id' => $uuid(), 'name' => 'No timestamp']]], $access);
check('record without updatedAt rejected', $r['status'] === 422, "got {$r['status']}");
$r = call('/sync', 'POST', ['clientTime' => $iso(), 'places' => [['id' => 'not-a-uuid', 'name' => 'x', 'updatedAt' => $iso()]]], $access);
check('non-UUID id gives 422 not 500', $r['status'] === 422, "got {$r['status']}");
$r = call('/sync', 'POST', ['clientTime' => $iso(), 'places' => [['id' => $uuid(), 'name' => 'x', 'updatedAt' => 'garbage']]], $access);
check('invalid updatedAt gives 422 not 500', $r['status'] === 422, "got {$r['status']}");
$r = call('/sync?since=not-a-date', 'GET', null, $access);
check('invalid since rejected', $r['status'] === 422, "got {$r['status']}");
$r = call('/sync', 'POST', ['clientTime' => $iso(), 'tombstones' => [
    ['entityType' => 'users; DROP TABLE users', 'entityID' => $uuid(), 'deletedAt' => $iso()],
]], $access);
check('unknown entity type rejected', $r['status'] === 422, "got {$r['status']}");
check('users table intact', Database::one('SELECT COUNT(*) AS n FROM users')['n'] > 0);
$r = call('/sync', 'POST', ['clientTime' => $iso(), 'places' => 'not-an-array'], $access);
check('wrong type for a collection does not crash', $r['status'] < 500, "got {$r['status']}");

// ------------------------------------------------------------- isolation
section('ISOLATION');
$attacker = call('/auth/register', 'POST', ['email' => "attacker-{$suffix}@example.com", 'password' => 'GoodPass1']);
$attackerToken = $attacker['body']['accessToken'] ?? '';
$r = call('/sync', 'GET', null, $attackerToken);
check('another account sees no data', count($r['body']['places'] ?? []) === 0 && count($r['body']['plans'] ?? []) === 0);

call('/sync', 'POST', ['clientTime' => $iso(), 'places' => [
    ['id' => $placeId, 'name' => 'overwritten', 'updatedAt' => $iso(3600)],
]], $attackerToken);
$owner = call('/sync', 'GET', null, $access);
$ownerName = '';
foreach ($owner['body']['places'] ?? [] as $place) {
    if (($place['id'] ?? '') === $placeId) { $ownerName = $place['name'] ?? ''; }
}
check('another account cannot overwrite a record by id', $ownerName === 'Berlin Mitte', $ownerName);

call('/sync', 'POST', ['clientTime' => $iso(), 'tombstones' => [
    ['entityType' => 'place', 'entityID' => $placeId, 'deletedAt' => $iso(7200)],
]], $attackerToken);
$owner = call('/sync', 'GET', null, $access);
$stillThere = false;
foreach ($owner['body']['places'] ?? [] as $place) {
    if (($place['id'] ?? '') === $placeId) { $stillThere = true; }
}
check('another account cannot delete a record by id', $stillThere);

// -------------------------------------------------------------- attribution
section('ATTRIBUTION');
$anchor = "af-{$suffix}";
$r = call('/horizon/observe', 'POST', $sealed(['anchor' => $anchor, 'os_line' => 'iOS 18.5', 'vessel' => 'app.sendal.cloudcrown']));
check('encrypted observe accepted', $r['status'] === 200, "got {$r['status']}");
$r = call('/horizon/observe', 'POST', null, null, '{"payload":"bm90LWVuY3J5cHRlZA=="}');
check('garbage payload rejected', $r['status'] === 422, "got {$r['status']}");
$r = call('/horizon/observe', 'POST', $sealed(['os_line' => 'iOS']));
check('missing device key rejected', $r['status'] === 422, "got {$r['status']}");

$device = Database::one('SELECT * FROM devices WHERE anchor = :a', ['a' => $anchor]);
check('device row created', $device !== null);
check('launch counted', (int) $device['launch_count'] === 1, (string) $device['launch_count']);
check('source_ip stored whole', $device['source_ip'] !== null && preg_match('/^[a-f0-9]{64}$/', $device['source_ip']) !== 1, (string) $device['source_ip']);

call('/horizon/observe', 'POST', $sealed(['anchor' => $anchor, 'signal' => 'fcm-1', 'catalog_id' => '111', 'relay_id' => 'proj-1']));
$device = Database::one('SELECT * FROM devices WHERE anchor = :a', ['a' => $anchor]);
check('second launch counted', (int) $device['launch_count'] === 2, (string) $device['launch_count']);
check('later fields filled in', $device['signal_token'] === 'fcm-1' && $device['catalog_id'] === '111');
check('earlier fields not wiped', $device['os_line'] === 'iOS 18.5', (string) $device['os_line']);

call('/horizon/observe', 'POST', $sealed(['anchor' => $anchor, 'os_line' => null, 'vessel' => '']));
$device = Database::one('SELECT * FROM devices WHERE anchor = :a', ['a' => $anchor]);
check('null and empty do not overwrite', $device['os_line'] === 'iOS 18.5' && $device['vessel'] === 'app.sendal.cloudcrown');

call('/horizon/observe', 'POST', $sealed(['anchor' => $anchor, 'ad_id' => '00000000-0000-0000-0000-000000000000']));
$device = Database::one('SELECT * FROM devices WHERE anchor = :a', ['a' => $anchor]);
check('all-zero IDFA discarded', $device['ad_id'] === null, (string) $device['ad_id']);

$before = (int) Database::one('SELECT COUNT(*) AS n FROM devices')['n'];
call('/horizon/observe', 'POST', $sealed(['anchor' => "{$anchor}-reinstall", 'os_line' => 'iOS 18.5']));
check('reinstall creates a new row', (int) Database::one('SELECT COUNT(*) AS n FROM devices')['n'] === $before + 1);

$trace = ['af_status' => 'Non-organic', 'media_source' => 'test_ms', 'campaign' => 'test_cmp', 'extra' => 'x'];
$r = call('/horizon/resolve', 'POST', $sealed(['anchor' => $anchor, 'ad_id' => 'AAAA-BBBB', 'trace' => $trace]));
check('resolve succeeds', $r['status'] === 200, "got {$r['status']}");
check('authorized reported from external ok', ($r['body']['authorized'] ?? null) === true, json_encode($r['body']));
check('analytics-service header set', ($r['headers']['analytics-service'] ?? '') === 'https://offers.example.com/x', $r['headers']['analytics-service'] ?? 'none');
check('message passed through', ($r['body']['message'] ?? '') === 'welcome');
$device = Database::one('SELECT * FROM devices WHERE anchor = :a', ['a' => $anchor]);
check('resolve does not count a launch', (int) $device['launch_count'] === 4, (string) $device['launch_count']);
check('attribution summary kept', $device['attr_status'] === 'Non-organic' && $device['attr_media_source'] === 'test_ms');
check('IDFA stored', $device['ad_id'] === 'AAAA-BBBB');

$traces = Database::all('SELECT * FROM device_traces WHERE device_id = :d', ['d' => $device['id']]);
check('full conversion stored as JSON', count($traces) === 1 && json_decode($traces[0]['payload'], true)['extra'] === 'x');
call('/horizon/resolve', 'POST', $sealed(['anchor' => $anchor, 'trace' => $trace]));
check('identical conversion deduplicated',
    (int) Database::one('SELECT COUNT(*) AS n FROM device_traces WHERE device_id = :d', ['d' => $device['id']])['n'] === 1);
call('/horizon/resolve', 'POST', $sealed(['anchor' => $anchor, 'trace' => array_merge($trace, ['extra' => 'y'])]));
check('different conversion stored separately',
    (int) Database::one('SELECT COUNT(*) AS n FROM device_traces WHERE device_id = :d', ['d' => $device['id']])['n'] === 2);

$log = Database::one('SELECT * FROM forward_log WHERE device_id = :d ORDER BY created_at DESC LIMIT 1', ['d' => $device['id']]);
$sent = json_decode($log['request_body'], true);
check('forward uses fixed external key names',
    ($sent['af_id'] ?? '') === $anchor && array_key_exists('push_token', $sent)
    && array_key_exists('firebase_project_id', $sent) && array_key_exists('store_id', $sent),
    implode(',', array_keys($sent)));
check('forward carries source_ip', !empty($sent['source_ip']));
check('forward carries the conversion verbatim', ($sent['af_status'] ?? '') === 'Non-organic');
check('no User-Agent field is forwarded', !array_key_exists('User-Agent', $sent) && !array_key_exists('user_agent', $sent));

$r = call('/horizon/link', 'POST', $sealed(['anchor' => $anchor]), $access);
check('device linked to account', $r['status'] === 204, "got {$r['status']}");
check('link row stored', (int) Database::one('SELECT COUNT(*) AS n FROM device_accounts')['n'] >= 1);
check('linking twice is idempotent', call('/horizon/link', 'POST', $sealed(['anchor' => $anchor]), $access)['status'] === 204);
check('unknown device rejected', call('/horizon/link', 'POST', $sealed(['anchor' => 'nope']), $access)['status'] === 404);
check('link requires authentication', call('/horizon/link', 'POST', $sealed(['anchor' => $anchor]))['status'] === 401);

// ---------------------------------------------------------- session death
section('SESSION INVALIDATION');
$s = call('/auth/register', 'POST', ['email' => "logout-{$suffix}@example.com", 'password' => 'GoodPass1']);
$token = $s['body']['accessToken'];
call('/auth/logout', 'POST', null, $token);
check('access token rejected after logout', call('/auth/me', 'GET', null, $token)['status'] === 401);

$s = call('/auth/register', 'POST', ['email' => "pw-{$suffix}@example.com", 'password' => 'GoodPass1']);
$token = $s['body']['accessToken'];
$changed = call('/auth/password', 'POST', ['currentPassword' => 'GoodPass1', 'newPassword' => 'Another123'], $token);
check('password change returns a replacement session', $changed['status'] === 200 && !empty($changed['body']['accessToken']), "got {$changed['status']}");
check('old access token rejected after password change', call('/auth/me', 'GET', null, $token)['status'] === 401);
check('replacement session works', call('/auth/me', 'GET', null, $changed['body']['accessToken'])['status'] === 200);
check('wrong current password rejected',
    call('/auth/password', 'POST', ['currentPassword' => 'Nope12345', 'newPassword' => 'Yet123456'], $changed['body']['accessToken'])['status'] === 422);

// ------------------------------------------------------------- deletion
section('ACCOUNT DELETION');
$s = call('/auth/register', 'POST', ['email' => "del-{$suffix}@example.com", 'password' => 'GoodPass1']);
$token = $s['body']['accessToken'];
$delId = $s['body']['user']['id'];
call('/sync', 'POST', ['clientTime' => $iso(), 'places' => [['id' => $uuid(), 'name' => 'gone', 'updatedAt' => $iso()]]], $token);

check('deletion without confirmation rejected',
    call('/account', 'DELETE', ['password' => 'GoodPass1'], $token)['status'] === 422);
check('deletion with wrong password rejected',
    call('/account', 'DELETE', ['password' => 'WrongPass1', 'confirmation' => 'DELETE'], $token)['status'] === 401);
check('still signed in after refused deletion', call('/auth/me', 'GET', null, $token)['status'] === 200);

$r = call('/account', 'DELETE', ['password' => 'GoodPass1', 'confirmation' => 'DELETE'], $token);
check('account deleted', $r['status'] === 200 && !empty($r['body']['deletedAt']), json_encode($r['body']));
check('purge date reported', !empty($r['body']['purgeAt']));
check('user row removed', (int) Database::one('SELECT COUNT(*) AS n FROM users WHERE id = :i', ['i' => $delId])['n'] === 0);
check('synced data removed by cascade', (int) Database::one('SELECT COUNT(*) AS n FROM sync_records WHERE user_id = :i', ['i' => $delId])['n'] === 0);
check('refresh tokens removed by cascade', (int) Database::one('SELECT COUNT(*) AS n FROM refresh_tokens WHERE user_id = :i', ['i' => $delId])['n'] === 0);
check('access token rejected after deletion', call('/auth/me', 'GET', null, $token)['status'] === 401);
check('deleted account cannot sign in',
    call('/auth/login', 'POST', ['email' => "del-{$suffix}@example.com", 'password' => 'GoodPass1'])['status'] === 401);
check('same email can register again',
    call('/auth/register', 'POST', ['email' => "del-{$suffix}@example.com", 'password' => 'FreshPass1'])['status'] === 201);

// ----------------------------------------------------------- disclosure
section('ERROR DISCLOSURE');
$r = call('/auth/register', 'POST', ['email' => 'x@y.co', 'password' => null]);
$asText = json_encode($r['body']);
check('no stack trace or file path in response', !str_contains($asText, '.php') && !str_contains($asText, '#0'), substr($asText, 0, 120));

// ------------------------------------------------------------ rate limit
section('RATE LIMITING');
$limited = false;
for ($i = 0; $i < 25; $i++) {
    if (call('/auth/login', 'POST', ['email' => $email, 'password' => 'wrong'])['status'] === 429) {
        $limited = true;
        break;
    }
}
check('brute-force login is rate limited', $limited);

echo "\n{$pass} passed, {$fail} failed\n";
if ($failures !== []) {
    echo "failed: " . implode('; ', $failures) . "\n";
}
exit($fail === 0 ? 0 : 1);
