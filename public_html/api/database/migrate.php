<?php
declare(strict_types=1);

require __DIR__ . '/../core/Env.php';
require __DIR__ . '/../core/ApiException.php';
require __DIR__ . '/../core/Database.php';

Env::load(__DIR__ . '/../.env');

$sql = file_get_contents(__DIR__ . '/schema.sql');
if ($sql === false) {
    fwrite(STDERR, "Cannot read schema.sql\n");
    exit(1);
}

// Strip comment-only lines first: otherwise a leading comment block would be
// glued to the statement that follows it and skipped along with it.
$stripComments = static function (string $chunk): string {
    $lines = array_filter(
        explode("\n", $chunk),
        static fn(string $line): bool => preg_match('/^\s*--/', $line) !== 1
    );
    return trim(implode("\n", $lines));
};

$statements = array_values(array_filter(
    array_map($stripComments, explode(';', $sql)),
    static fn(string $s): bool => $s !== ''
));

try {
    $pdo = Database::connection();
} catch (Throwable $error) {
    fwrite(STDERR, 'Database connection failed: ' . $error->getMessage() . "\n");
    exit(1);
}

foreach ($statements as $statement) {
    $label = 'statement';
    if (preg_match('/CREATE TABLE IF NOT EXISTS\s+(\w+)/i', $statement, $m) === 1) {
        $label = 'table ' . $m[1];
    }
    try {
        $pdo->exec($statement);
        echo "ok  {$label}\n";
    } catch (Throwable $error) {
        echo "ERR {$label}: " . $error->getMessage() . "\n";
        exit(1);
    }
}

echo "migration complete\n";
