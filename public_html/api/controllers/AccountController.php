<?php
declare(strict_types=1);

final class AccountController
{
    /** Guideline 5.1.1(v): removes the account itself, not merely its data. */
    public static function destroy(Request $request): void
    {
        $userId = Auth::requireUser($request);
        $body = $request->json();

        if (($body['confirmation'] ?? '') !== 'DELETE') {
            throw ApiException::validation('Confirmation missing.', ['confirmation' => 'Type DELETE to confirm.']);
        }
        $password = is_string($body['password'] ?? null) ? $body['password'] : '';

        $row = Database::one('SELECT password_hash FROM users WHERE id = :id', ['id' => $userId]);
        if ($row === null) {
            throw ApiException::notFound('Account not found.');
        }
        if (!Passwords::verify($password, $row['password_hash'])) {
            throw ApiException::invalidCredentials();
        }

        $purgeDays = Env::int('DELETION_PURGE_DAYS', 30);
        $purgeAt = Clock::now()->modify("+{$purgeDays} days");

        Database::transaction(function () use ($userId, $purgeAt): void {
            Database::run(
                'INSERT INTO deletion_log (id, user_id, deleted_at, purge_at) VALUES (:id, :user, :now, :purge)',
                ['id' => Uuid::v4(), 'user' => $userId, 'now' => Clock::store(), 'purge' => Clock::store($purgeAt)]
            );
            // refresh_tokens, sync_records and device links cascade from users.
            Database::run('DELETE FROM users WHERE id = :id', ['id' => $userId]);
        });

        Response::json([
            'deletedAt' => Clock::iso(Clock::now()),
            'purgeAt' => Clock::iso($purgeAt),
            'message' => 'Your account and all synced data have been deleted.',
        ]);
    }
}
