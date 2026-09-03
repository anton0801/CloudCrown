<?php
declare(strict_types=1);

final class Clock
{
    /** Storage format: UTC with microseconds, so sync cursors never collide. */
    public const FORMAT = 'Y-m-d H:i:s.u';

    public static function now(): DateTimeImmutable
    {
        return new DateTimeImmutable('now', new DateTimeZone('UTC'));
    }

    public static function store(?DateTimeImmutable $moment = null): string
    {
        return ($moment ?? self::now())->format(self::FORMAT);
    }

    /**
     * Sync cursors travel as ISO-8601 with milliseconds, so anything they are
     * compared against is stored at that same precision. Otherwise a cursor is
     * always a fraction earlier than the row it points at and the row is sent
     * again on the next pull.
     */
    public static function storeCursor(?DateTimeImmutable $moment = null): string
    {
        $value = $moment ?? self::now();
        $milliseconds = (int) floor(((int) $value->format('u')) / 1000);
        return $value->format('Y-m-d H:i:s') . '.' . str_pad((string) $milliseconds, 3, '0', STR_PAD_LEFT) . '000';
    }

    public static function iso(string|DateTimeImmutable|null $value): ?string
    {
        if ($value === null || $value === '') {
            return null;
        }
        $moment = $value instanceof DateTimeImmutable
            ? $value
            : new DateTimeImmutable($value, new DateTimeZone('UTC'));
        return $moment->setTimezone(new DateTimeZone('UTC'))->format('Y-m-d\TH:i:s.v\Z');
    }

    /** Accepts anything ISO-8601-ish the client may send. */
    public static function parse(mixed $value): ?DateTimeImmutable
    {
        if (!is_string($value) || $value === '') {
            return null;
        }
        try {
            return (new DateTimeImmutable($value))->setTimezone(new DateTimeZone('UTC'));
        } catch (Throwable) {
            return null;
        }
    }
}
