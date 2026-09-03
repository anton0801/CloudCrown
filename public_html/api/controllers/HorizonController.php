<?php
declare(strict_types=1);

final class HorizonController
{
    /**
     * Input names are specific to this app. The server keeps the mapping onto
     * its own columns, so the wire format and the schema stay independent.
     */
    private const FIELD_MAP = [
        'os_line' => 'os_line',
        'vessel' => 'vessel',
        'relay_id' => 'relay_id',
        'catalog_id' => 'catalog_id',
        'signal' => 'signal_token',
        'locale_tag' => 'locale_tag',
        'ad_id' => 'ad_id',
        'build_tag' => 'build_tag',
        'hull' => 'hull',
        'tz' => 'tz',
    ];

    public static function observe(Request $request): void
    {
        RateLimit::enforce('horizon', $request->clientIp(), Env::int('HORIZON_LIMIT', 30), 60);
        $data = self::readBody($request);
        // A push-token report sets tick=false: it updates fields but is not a
        // launch, so it must not bump launch_count.
        $countLaunch = ($data['tick'] ?? true) !== false;
        self::debugLog('observe', $data, $countLaunch);
        self::upsertDevice($data, $request->clientIp(), $countLaunch);
        Response::json(['status' => 'ok']);
    }

    public static function resolve(Request $request): void
    {
        RateLimit::enforce('horizon', $request->clientIp(), Env::int('HORIZON_LIMIT', 30), 60);
        $data = self::readBody($request);
        $ip = $request->clientIp();

        self::debugLog('resolve', $data, false);
        $device = self::upsertDevice($data, $ip, false);
        $trace = isset($data['trace']) && is_array($data['trace']) ? $data['trace'] : null;
        self::storeTrace($device['id'], $trace);

        $fresh = Database::one('SELECT * FROM devices WHERE id = :id', ['id' => $device['id']]) ?? $device;
        $outcome = self::forward($fresh, $trace, $ip);

        $headers = [];
        if ($outcome['url'] !== null) {
            $headers['analytics-service'] = $outcome['url'];
        }
        Response::json([
            'status' => 'ok',
            'authorized' => $outcome['ok'],
            'message' => $outcome['message'],
        ], 200, $headers);
    }

    public static function link(Request $request): void
    {
        $userId = Auth::requireUser($request);
        RateLimit::enforce('api', $userId, Env::int('API_LIMIT', 120), 60);

        $data = self::readBody($request);
        $anchor = self::clean($data['anchor'] ?? null);
        if ($anchor === null) {
            throw ApiException::validation('A device key is required.', ['anchor' => 'Missing.']);
        }
        $device = Database::one('SELECT id FROM devices WHERE anchor = :anchor', ['anchor' => $anchor]);
        if ($device === null) {
            throw ApiException::notFound('Unknown device.');
        }
        Database::run(
            'INSERT INTO device_accounts (device_id, user_id, linked_at) VALUES (:device, :user, :now)
             ON DUPLICATE KEY UPDATE linked_at = linked_at',
            ['device' => $device['id'], 'user' => $userId, 'now' => Clock::store()]
        );
        Response::noContent();
    }

    /**
     * Diagnostic log, off unless HORIZON_DEBUG=true. Writes to api/horizon.log,
     * which .htaccess blocks from the web. Values that could identify a user
     * (IDFA) are not written; attribution status/source are, because that is
     * exactly what needs verifying.
     */
    private static function debugLog(string $endpoint, array $data, bool $countLaunch): void
    {
        if (Env::get('HORIZON_DEBUG') !== 'true') {
            return;
        }
        $trace = isset($data['trace']) && is_array($data['trace']) ? $data['trace'] : [];
        $line = sprintf(
            "%s  %-8s anchor=%s launch=%s trace=%s af_status=%s media=%s campaign=%s trace_keys=[%s]\n",
            gmdate('Y-m-d H:i:s'),
            $endpoint,
            (string) ($data['anchor'] ?? '-'),
            $countLaunch ? 'yes' : 'no',
            $trace === [] ? 'ABSENT' : 'present',
            (string) ($trace['af_status'] ?? '-'),
            (string) ($trace['media_source'] ?? '-'),
            (string) ($trace['campaign'] ?? '-'),
            implode(',', array_keys($trace))
        );
        @file_put_contents(dirname(__DIR__) . '/horizon.log', $line, FILE_APPEND | LOCK_EX);
    }

    private static function readBody(Request $request): array
    {
        $body = $request->json();
        if (isset($body['payload']) && is_string($body['payload']) && $body['payload'] !== '') {
            return Crypto::decrypt($body['payload']);
        }
        if (Crypto::isConfigured() && Env::isProduction()) {
            throw ApiException::validation('This endpoint requires an encrypted payload.', ['payload' => 'Missing.']);
        }
        return $body;
    }

    private static function clean(mixed $value): ?string
    {
        if ($value === null) {
            return null;
        }
        $text = trim(is_string($value) ? $value : (string) $value);
        if ($text === '') {
            return null;
        }
        // An all-zero advertising identifier carries no information.
        if (preg_match('/^0+(-0+)+$/', $text) === 1) {
            return null;
        }
        return $text;
    }

    /** Empty values never overwrite a field that is already known. */
    private static function upsertDevice(array $data, string $ip, bool $countLaunch): array
    {
        $anchor = self::clean($data['anchor'] ?? null);
        if ($anchor === null) {
            throw ApiException::validation('A device key is required.', ['anchor' => 'Missing.']);
        }

        return Database::transaction(function () use ($data, $ip, $countLaunch, $anchor): array {
            $existing = Database::one('SELECT * FROM devices WHERE anchor = :anchor FOR UPDATE', ['anchor' => $anchor]);

            if ($existing === null) {
                $params = [
                    'id' => Uuid::v4(),
                    'anchor' => $anchor,
                    'source_ip' => self::clean($ip),
                    'launch_count' => $countLaunch ? 1 : 0,
                    'now' => Clock::store(),
                    'now2' => Clock::store(),
                ];
                foreach (self::FIELD_MAP as $input => $column) {
                    $params[$column] = self::clean($data[$input] ?? null);
                }
                $columns = array_merge(['id', 'anchor'], array_values(self::FIELD_MAP), ['source_ip', 'launch_count', 'created_at', 'updated_at']);
                $placeholders = array_map(
                    fn(string $c) => ':' . ($c === 'created_at' ? 'now' : ($c === 'updated_at' ? 'now2' : $c)),
                    $columns
                );
                Database::run(
                    'INSERT INTO devices (' . implode(', ', $columns) . ') VALUES (' . implode(', ', $placeholders) . ')',
                    $params
                );
                return Database::one('SELECT * FROM devices WHERE anchor = :anchor', ['anchor' => $anchor]);
            }

            $assignments = [];
            $params = ['anchor' => $anchor, 'now' => Clock::store()];
            foreach (self::FIELD_MAP as $input => $column) {
                $value = self::clean($data[$input] ?? null);
                if ($value === null) {
                    continue;
                }
                $assignments[] = "{$column} = :{$column}";
                $params[$column] = $value;
            }
            $ipValue = self::clean($ip);
            if ($ipValue !== null) {
                $assignments[] = 'source_ip = :source_ip';
                $params['source_ip'] = $ipValue;
            }
            if ($countLaunch) {
                $assignments[] = 'launch_count = launch_count + 1';
            }
            $assignments[] = 'updated_at = :now';

            Database::run(
                'UPDATE devices SET ' . implode(', ', $assignments) . ' WHERE anchor = :anchor',
                $params
            );
            return Database::one('SELECT * FROM devices WHERE anchor = :anchor', ['anchor' => $anchor]);
        });
    }

    private static function storeTrace(string $deviceId, ?array $trace): void
    {
        if ($trace === null || $trace === []) {
            return;
        }
        Database::run(
            'INSERT INTO device_traces (id, device_id, payload, payload_hash, created_at)
             VALUES (:id, :device, :payload, :hash, :now)
             ON DUPLICATE KEY UPDATE created_at = created_at',
            [
                'id' => Uuid::v4(),
                'device' => $deviceId,
                'payload' => json_encode($trace, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE),
                'hash' => Crypto::hashPayload($trace),
                'now' => Clock::store(),
            ]
        );

        $status = self::clean($trace['af_status'] ?? null);
        $media = self::clean($trace['media_source'] ?? null);
        $campaign = self::clean($trace['campaign'] ?? null);
        if ($status === null && $media === null && $campaign === null) {
            return;
        }
        $assignments = ['updated_at = :now'];
        $params = ['id' => $deviceId, 'now' => Clock::store()];
        foreach (['attr_status' => $status, 'attr_media_source' => $media, 'attr_campaign' => $campaign] as $column => $value) {
            if ($value === null) {
                continue;
            }
            $assignments[] = "{$column} = :{$column}";
            $params[$column] = $value;
        }
        Database::run('UPDATE devices SET ' . implode(', ', $assignments) . ' WHERE id = :id', $params);
    }

    /**
     * Outward payload uses the analytics service's fixed key names. No
     * User-Agent is collected or sent.
     * @return array{ok:bool,url:?string,message:?string}
     */
    private static function forward(array $device, ?array $trace, string $ip): array
    {
        $target = Env::get('FORWARD_URL', '');
        if ($target === null || $target === '') {
            return ['ok' => false, 'url' => null, 'message' => null];
        }

        $payload = array_merge($trace ?? [], [
            'af_id' => $device['anchor'],
            'os' => $device['os_line'],
            'bundle_id' => $device['vessel'],
            'firebase_project_id' => $device['relay_id'],
            'store_id' => $device['catalog_id'],
            'push_token' => $device['signal_token'],
            'locale' => $device['locale_tag'],
            'idfa' => $device['ad_id'],
            'source_ip' => $ip,
        ]);

        $result = Http::postJson($target, $payload, Env::int('FORWARD_TIMEOUT_MS', 15000));
        $decoded = json_decode($result['body'], true);
        $ok = is_array($decoded) && ($decoded['ok'] ?? null) === true;
        $url = $ok && isset($decoded['url']) && is_string($decoded['url']) && $decoded['url'] !== ''
            ? $decoded['url']
            : null;
        $message = is_array($decoded) && isset($decoded['message']) && is_string($decoded['message'])
            ? $decoded['message']
            : null;

        Database::run(
            'INSERT INTO forward_log (id, device_id, endpoint, request_body, response_status, response_body, ok, target_url, error, created_at)
             VALUES (:id, :device, :endpoint, :request, :status, :response, :ok, :url, :error, :now)',
            [
                'id' => Uuid::v4(),
                'device' => $device['id'],
                'endpoint' => 'resolve',
                'request' => json_encode($payload, JSON_UNESCAPED_SLASHES),
                'status' => $result['status'],
                'response' => substr($result['body'], 0, 4000),
                'ok' => $ok ? 1 : 0,
                'url' => $url,
                'error' => $result['error'],
                'now' => Clock::store(),
            ]
        );

        return ['ok' => $ok, 'url' => $url, 'message' => $message];
    }
}
