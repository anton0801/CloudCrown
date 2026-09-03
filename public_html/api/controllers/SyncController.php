<?php
declare(strict_types=1);

final class SyncController
{
    private const COLLECTIONS = [
        'place' => 'places',
        'activity' => 'activities',
        'plan' => 'plans',
        'alert' => 'alerts',
        'feedback' => 'feedback',
    ];
    private const SINGLETONS = ['profile'];

    private static function allTypes(): array
    {
        return array_merge(array_keys(self::COLLECTIONS), self::SINGLETONS);
    }

    public static function pull(Request $request): void
    {
        $userId = Auth::requireUser($request);
        RateLimit::enforce('api', $userId, Env::int('API_LIMIT', 120), 60);

        $since = null;
        if (isset($request->query['since']) && $request->query['since'] !== '') {
            $since = Clock::parse($request->query['since']);
            if ($since === null) {
                throw ApiException::validation('Invalid `since` timestamp.', ['since' => 'Use an ISO-8601 date.']);
            }
        }

        $beforeQuery = Clock::now();

        $sql = 'SELECT entity_type, entity_id, payload, updated_at, deleted_at, server_time
                  FROM sync_records WHERE user_id = :user';
        $params = ['user' => $userId];
        if ($since !== null) {
            $sql .= ' AND server_time > :since';
            $params['since'] = Clock::storeCursor($since);
        }

        $body = [
            'serverTime' => Clock::iso($since ?? $beforeQuery),
            'profile' => null,
            'places' => [], 'activities' => [], 'plans' => [], 'alerts' => [], 'feedback' => [],
            'tombstones' => [],
        ];

        $newest = null;
        foreach (Database::all($sql, $params) as $row) {
            $rowTime = Clock::parse($row['server_time']);
            if ($rowTime !== null && ($newest === null || $rowTime > $newest)) {
                $newest = $rowTime;
            }
            if ($row['deleted_at'] !== null) {
                $body['tombstones'][] = [
                    'entityType' => $row['entity_type'],
                    'entityID' => $row['entity_id'],
                    'deletedAt' => Clock::iso($row['deleted_at']),
                ];
                continue;
            }
            if ($row['payload'] === null) {
                continue;
            }
            $decoded = json_decode((string) $row['payload'], true);
            if (!is_array($decoded)) {
                continue;
            }
            if (in_array($row['entity_type'], self::SINGLETONS, true)) {
                $body['profile'] = $decoded;
            } elseif (isset(self::COLLECTIONS[$row['entity_type']])) {
                $body[self::COLLECTIONS[$row['entity_type']]][] = $decoded;
            }
        }

        if ($newest !== null) {
            $body['serverTime'] = Clock::iso($newest);
        }
        Response::json($body);
    }

    /**
     * Last-write-wins on the client's `updatedAt`: an older write never
     * replaces a newer stored record, so two offline devices converge.
     */
    public static function push(Request $request): void
    {
        $userId = Auth::requireUser($request);
        RateLimit::enforce('api', $userId, Env::int('API_LIMIT', 120), 60);

        $body = $request->json();
        $incoming = [];

        foreach (self::COLLECTIONS as $type => $key) {
            $items = $body[$key] ?? null;
            if ($items === null) {
                continue;
            }
            if (!is_array($items) || (is_array($items) && $items !== [] && array_keys($items) !== range(0, count($items) - 1))) {
                continue;
            }
            foreach ($items as $item) {
                if (!is_array($item)) {
                    continue;
                }
                $incoming[] = self::normalize($type, $item);
            }
        }

        if (isset($body['profile']) && is_array($body['profile'])) {
            $incoming[] = self::normalize('profile', $body['profile']);
        }

        $tombstones = [];
        $rawTombstones = $body['tombstones'] ?? [];
        if (is_array($rawTombstones)) {
            foreach ($rawTombstones as $stone) {
                if (!is_array($stone)) {
                    throw ApiException::validation('Malformed tombstone.', ['tombstones' => 'Malformed entry.']);
                }
                $type = $stone['entityType'] ?? null;
                if (!is_string($type) || !in_array($type, self::allTypes(), true)) {
                    throw ApiException::validation('Unknown entity type.', ['tombstones' => 'Unsupported type.']);
                }
                if (!Uuid::isValid($stone['entityID'] ?? null)) {
                    throw ApiException::validation('A record id must be a UUID.', ['tombstones' => 'Not a valid UUID.']);
                }
                $deletedAt = Clock::parse($stone['deletedAt'] ?? null);
                if ($deletedAt === null) {
                    throw ApiException::validation('A timestamp must be an ISO-8601 date.', ['tombstones' => 'Not a valid timestamp.']);
                }
                $tombstones[] = ['type' => $type, 'id' => $stone['entityID'], 'deletedAt' => $deletedAt];
            }
        }

        $maxRecords = Env::int('MAX_RECORDS_PER_USER', 20000);
        $used = Database::one('SELECT COUNT(*) AS n FROM sync_records WHERE user_id = :user', ['user' => $userId]);
        if (((int) $used['n']) + count($incoming) > $maxRecords) {
            throw ApiException::tooLarge(
                "This account already stores {$used['n']} records; the limit is {$maxRecords}."
            );
        }

        $accepted = Database::transaction(function () use ($userId, $incoming, $tombstones): int {
            $count = 0;
            foreach ($incoming as $record) {
                $count += self::upsertRecord($userId, $record['type'], $record['id'], $record['payload'], $record['updatedAt'], null);
            }
            foreach ($tombstones as $stone) {
                $count += self::upsertRecord($userId, $stone['type'], $stone['id'], null, $stone['deletedAt'], $stone['deletedAt']);
            }
            return $count;
        });

        Response::json(['serverTime' => Clock::iso(Clock::now()), 'accepted' => $accepted]);
    }

    private static function normalize(string $type, array $item): array
    {
        if (!isset($item['id']) || !isset($item['updatedAt'])) {
            throw ApiException::validation('Every record needs an id and updatedAt.', [$type => 'Missing id or updatedAt.']);
        }
        if (!Uuid::isValid($item['id'])) {
            throw ApiException::validation('A record id must be a UUID.', [$type => 'Not a valid UUID.']);
        }
        $updatedAt = Clock::parse($item['updatedAt']);
        if ($updatedAt === null) {
            throw ApiException::validation('A timestamp must be an ISO-8601 date.', [$type => 'Not a valid timestamp.']);
        }
        return ['type' => $type, 'id' => $item['id'], 'payload' => $item, 'updatedAt' => $updatedAt];
    }

    private static function upsertRecord(
        string $userId,
        string $type,
        string $entityId,
        ?array $payload,
        DateTimeImmutable $updatedAt,
        ?DateTimeImmutable $deletedAt
    ): int {
        $existing = Database::one(
            'SELECT updated_at, deleted_at FROM sync_records
              WHERE user_id = :user AND entity_type = :type AND entity_id = :id FOR UPDATE',
            ['user' => $userId, 'type' => $type, 'id' => $entityId]
        );

        $encoded = $payload === null ? null : json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);

        if ($existing === null) {
            Database::run(
                'INSERT INTO sync_records (user_id, entity_type, entity_id, payload, updated_at, deleted_at, server_time)
                 VALUES (:user, :type, :id, :payload, :updated, :deleted, :now)',
                [
                    'user' => $userId, 'type' => $type, 'id' => $entityId,
                    'payload' => $encoded,
                    'updated' => Clock::store($updatedAt),
                    'deleted' => $deletedAt === null ? null : Clock::store($deletedAt),
                    'now' => Clock::storeCursor(),
                ]
            );
            return 1;
        }

        $storedUpdatedAt = Clock::parse($existing['updated_at']);
        $storedIsDeleted = $existing['deleted_at'] !== null;

        if ($deletedAt !== null) {
            // A deletion wins on ties, so a delete is never lost to its own record.
            if ($storedUpdatedAt !== null && $storedUpdatedAt > $updatedAt) {
                return 0;
            }
        } else {
            $isNewer = $storedUpdatedAt === null || $storedUpdatedAt < $updatedAt;
            if (!$isNewer && !$storedIsDeleted) {
                return 0;
            }
        }

        Database::run(
            'UPDATE sync_records SET payload = :payload, updated_at = :updated, deleted_at = :deleted, server_time = :now
              WHERE user_id = :user AND entity_type = :type AND entity_id = :id',
            [
                'payload' => $encoded,
                'updated' => Clock::store($updatedAt),
                'deleted' => $deletedAt === null ? null : Clock::store($deletedAt),
                'now' => Clock::storeCursor(),
                'user' => $userId, 'type' => $type, 'id' => $entityId,
            ]
        );
        return 1;
    }
}
