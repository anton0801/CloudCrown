<?php
declare(strict_types=1);

require __DIR__ . '/../core/Env.php';
require __DIR__ . '/../core/ApiException.php';
require __DIR__ . '/../core/Database.php';
Env::load(__DIR__ . '/../.env');

if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}

$tables = [
    'users' => ['id', 'email', 'email_verified', 'token_version', 'created_at'],
    'refresh_tokens' => ['user_id', 'expires_at', 'revoked_at', 'created_at'],
    'sync_records' => ['user_id', 'entity_type', 'entity_id', 'updated_at', 'deleted_at', 'server_time'],
    'devices' => ['anchor', 'os_line', 'vessel', 'catalog_id', 'ad_id', 'launch_count', 'attr_status', 'attr_media_source', 'source_ip', 'updated_at'],
    'device_traces' => ['device_id', 'payload_hash', 'created_at'],
    'forward_log' => ['device_id', 'response_status', 'ok', 'target_url', 'error', 'created_at'],
    'device_accounts' => ['device_id', 'user_id', 'linked_at'],
    'rate_limits' => ['bucket', 'hits', 'window_start'],
    'deletion_log' => ['user_id', 'deleted_at', 'purge_at'],
];

$only = $argv[1] ?? null;
$limit = (int) ($argv[2] ?? 10);

echo "CloudCrown database\n";
echo str_repeat('=', 78) . "\n\n";

foreach ($tables as $table => $columns) {
    if ($only !== null && $only !== $table) {
        continue;
    }
    try {
        $count = (int) Database::one("SELECT COUNT(*) AS n FROM {$table}")['n'];
    } catch (Throwable $error) {
        echo "{$table}: unavailable ({$error->getMessage()})\n\n";
        continue;
    }
    echo "{$table}  —  {$count} row" . ($count === 1 ? '' : 's') . "\n";
    if ($count === 0) {
        echo "\n";
        continue;
    }
    $order = in_array('created_at', $columns, true) ? 'created_at'
        : (in_array('updated_at', $columns, true) ? 'updated_at'
        : (in_array('window_start', $columns, true) ? 'window_start' : $columns[0]));
    $rows = Database::all(
        'SELECT ' . implode(', ', $columns) . " FROM {$table} ORDER BY {$order} DESC LIMIT {$limit}"
    );
    $widths = [];
    foreach ($columns as $column) {
        $widths[$column] = strlen($column);
    }
    foreach ($rows as $row) {
        foreach ($columns as $column) {
            $widths[$column] = max($widths[$column], strlen(substr((string) ($row[$column] ?? ''), 0, 38)));
        }
    }
    $line = '';
    foreach ($columns as $column) {
        $line .= str_pad($column, $widths[$column] + 2);
    }
    echo "  " . rtrim($line) . "\n";
    echo "  " . str_repeat('-', max(10, strlen(rtrim($line)))) . "\n";
    foreach ($rows as $row) {
        $line = '';
        foreach ($columns as $column) {
            $value = (string) ($row[$column] ?? '');
            if (strlen($value) > 38) {
                $value = substr($value, 0, 35) . '...';
            }
            $line .= str_pad($value === '' ? '-' : $value, $widths[$column] + 2);
        }
        echo "  " . rtrim($line) . "\n";
    }
    echo "\n";
}

echo "usage: php tools/inspect.php [table] [limit]\n";
