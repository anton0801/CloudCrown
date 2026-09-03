<?php
declare(strict_types=1);

final class RateLimit
{
    /** Counters live in the database so they survive across PHP processes. */
    public static function enforce(string $action, string $identity, int $limit, int $windowSeconds): void
    {
        $bucket = hash('sha256', $action . '|' . $identity);
        $now = Clock::now();

        Database::run(
            'INSERT INTO rate_limits (bucket, hits, window_start) VALUES (:bucket, 1, :now)
             ON DUPLICATE KEY UPDATE
                hits = IF(window_start < :cutoff, 1, hits + 1),
                window_start = IF(window_start < :cutoff2, :now2, window_start)',
            [
                'bucket' => $bucket,
                'now' => Clock::store($now),
                'now2' => Clock::store($now),
                'cutoff' => Clock::store($now->modify("-{$windowSeconds} seconds")),
                'cutoff2' => Clock::store($now->modify("-{$windowSeconds} seconds")),
            ]
        );

        $row = Database::one('SELECT hits, window_start FROM rate_limits WHERE bucket = :bucket', ['bucket' => $bucket]);
        if ($row === null) {
            return;
        }
        if ((int) $row['hits'] > $limit) {
            $start = Clock::parse($row['window_start']);
            $retry = $windowSeconds;
            if ($start !== null) {
                $retry = max(1, $windowSeconds - ($now->getTimestamp() - $start->getTimestamp()));
            }
            throw ApiException::rateLimited($retry);
        }
    }

    public static function prune(): void
    {
        Database::run('DELETE FROM rate_limits WHERE window_start < :cutoff', [
            'cutoff' => Clock::store(Clock::now()->modify('-2 days')),
        ]);
    }
}
