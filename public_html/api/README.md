# CloudCrown API — PHP 8 + MySQL

Accounts, cross-device sync and device attribution for the CloudCrown iOS app.
Plain PHP 8.1+, MySQL 5.7+ / MariaDB 10.2+. **No Composer, no framework.**

Weather and air-quality data are not proxied here — the app fetches those
directly from Open-Meteo. This service stores accounts, the records a user
creates, and attribution.

## Endpoints

| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `/v1/health` | – | Liveness probe |
| POST | `/v1/auth/register` | – | Create an account |
| POST | `/v1/auth/login` | – | Sign in |
| POST | `/v1/auth/refresh` | – | Rotate the refresh token |
| POST | `/v1/auth/logout` | Bearer | Revoke every token for the account |
| GET | `/v1/auth/me` | Bearer | Current account |
| POST | `/v1/auth/password` | Bearer | Change password, returns a new session |
| DELETE | `/v1/account` | Bearer | **Permanently delete the account** |
| GET | `/v1/sync?since=` | Bearer | Pull changes |
| POST | `/v1/sync` | Bearer | Push changes |
| POST | `/v1/horizon/observe` | – | Device facts available at app open |
| POST | `/v1/horizon/resolve` | – | Attribution; the response closes the splash |
| POST | `/v1/horizon/link` | Bearer | Tie the device record to the account |

Full contract: [`openapi.yaml`](openapi.yaml).

## Deploying to Namecheap cPanel

The API and the website share one domain. The API lives in an `api/` subfolder,
so its base URL is **`https://cloudcrown-app.space/api/v1`** — no subdomain
needed. The router derives its own prefix from `SCRIPT_NAME`, so the same files
also work unchanged at a document root if you ever add `api.` as a subdomain.

### 1. Create the database
cPanel → **MySQL® Databases**
- Create a database, e.g. `cpaneluser_cloudcrown`
- Create a user with a strong password
- Add the user to the database with **ALL PRIVILEGES**

cPanel prefixes both names with your account name; note the real ones.

### 2. Upload
Target layout inside `public_html` (the document root of cloudcrown-app.space):

```
public_html/
  .htaccess          <- from web/
  index.html         <- from web/
  privacy.html       <- from web/
  support.html       <- from web/
  assets/style.css   <- from web/
  api/               <- everything from api/
    .htaccess
    index.php
    core/  security/  controllers/  database/  tools/
```

So: contents of `web/` go to the root, and the `api/` folder goes inside it.
`tests/`, `README.md` and the `.example` files do not need uploading.

The upload must include the leading-dot files (`.htaccess`, and later `.env`).
File Manager hides them until Settings → **Show Hidden Files** is enabled.

### 3. Configure
Copy `.env.production.example` to `api/.env` and fill in the three database
values. `JWT_SECRET` and `PAYLOAD_KEY` are already filled in there.

On cPanel `DB_HOST=localhost` is normally correct. If the connection fails,
read the socket path from cPanel → phpMyAdmin → Variables → `socket` and set
`DB_SOCKET` instead.

### 4. Create the tables
cPanel → **Terminal**, if your plan has it:
```bash
cd ~/public_html/api && php database/migrate.php
```

No Terminal? Import `api/database/schema.sql` through **phpMyAdmin → Import**.

### 5. Enable HTTPS
cPanel → **SSL/TLS Status** → select the domain → **Run AutoSSL**.
Without a valid certificate iOS App Transport Security blocks every request in
a Release build and the app simply receives nothing.

Leave `FORCE_HTTPS=false` until the certificate is issued, otherwise every
request answers 403 and it looks like the API is broken.

### 6. Check it
```bash
curl https://cloudcrown-app.space/api/v1/health
# {"status":"ok","time":"..."}
```

Then confirm the rewrite is preserving the auth header — the single most common
cPanel failure:
```bash
curl -i https://cloudcrown-app.space/api/v1/auth/me -H "Authorization: Bearer nonsense"
# expected: 401 with {"error":{"code":"unauthorized",...}}
# a 200, or an Apache error page, means .htaccess is not being applied
```

And that the website still answers:
```bash
curl -o /dev/null -w "%{http_code}\n" https://cloudcrown-app.space/
curl -o /dev/null -w "%{http_code}\n" https://cloudcrown-app.space/privacy
```

### Why `.htaccess` is required
1. cPanel runs PHP over CGI/FastCGI, which **drops the `Authorization` header**.
   The rewrite copies it into `HTTP_AUTHORIZATION`; without it every
   authenticated request answers 401.
2. All routes are virtual — `/v1/auth/login` is not a file, so it must be
   rewritten to `index.php`.
3. It blocks direct access to `.env`, `*.sql` and the source directories.

If `mod_rewrite` is unavailable the API cannot work on that host.

## Local development

```bash
cp .env.example .env          # point DB_* at a local MySQL
php database/migrate.php
php -S 127.0.0.1:8899 index.php
```

The built-in server ignores `.htaccess` but `index.php` routes on its own, so
behaviour matches. Point Debug builds of the app at it with the scheme environment variable
`CLOUDCROWN_API_BASE_URL=http://localhost:8899/v1`. The variable is read in
Debug only; Release always uses the production URL.

## Tests

```bash
php tests/run.php
```

91 end-to-end checks against a real MySQL: validation, account-enumeration
resistance, `alg=none` and signature-forgery rejection, refresh-token rotation
and replay, session invalidation after logout / password change / deletion,
per-account isolation (including an attacker writing another account's record
id), last-write-wins sync, tombstones, delta cursors, 422-not-500 on malformed
input, SQL injection through entity types, error disclosure, rate limiting,
encrypted attribution payloads, device upsert rules, forward logging and
account deletion with cascade.

Requires `.env` pointing at a database you do not mind filling with test rows,
and a stub for `FORWARD_URL`.

## Inspecting the database

```bash
php tools/inspect.php                 # summary of every table
php tools/inspect.php devices 20      # last 20 device rows
```
CLI only; it refuses to run over HTTP.

## Security

- Passwords: **Argon2id**, falling back to bcrypt cost 12 where the host was
  built without libargon2.
- JWT HS256 written by hand: the algorithm is fixed in code and the signature
  compared with `hash_equals`, so `alg=none` and algorithm confusion cannot pass.
- Each access token carries the account's `token_version`. Logout, a password
  change and account deletion increment it, so an already-issued token dies
  immediately instead of living until it expires. Every authenticated request
  also confirms the account still exists.
- Refresh tokens: 48 random bytes, stored only as a SHA-256 hash, rotated on
  every use, so a captured token cannot be replayed after the real client uses it.
- Login answers identically for a wrong password and an unknown account, and
  always spends a hash comparison, so accounts cannot be enumerated by response
  or by timing.
- **Only prepared statements.** No SQL is ever concatenated.
- Rate limiting lives in MySQL, so counters survive across PHP processes:
  20 password checks / 15 min per IP, 15 registrations / hour per IP,
  120 authenticated requests / min per account, 30 attribution calls / min per IP.
- Request bodies capped at 4 MB; each account capped at `MAX_RECORDS_PER_USER`.
- HTTPS enforced in production (`FORCE_HTTPS`).
- Attribution payloads are AES-256-GCM. With `APP_ENV=production` and a key set,
  an unencrypted body is refused.

## Attribution notes

The device key is **`af_id`**, not an app-generated UUID, so a reinstall creates
a new row. Empty and null values never overwrite a field that is already known,
because some values only arrive in the second request. An all-zero IDFA is
discarded. `source_ip` is stored whole, not hashed.

Field names on the wire (`anchor`, `os_line`, `vessel`, `relay_id`,
`catalog_id`, `signal`, `locale_tag`, `ad_id`, `build_tag`, `hull`, `tz`,
`trace`) are specific to this app; the server maps them onto its own columns.
The outbound forward uses the analytics service's fixed names (`af_id`,
`push_token`, `store_id`, `firebase_project_id`, `idfa`, `locale`, `os`,
`bundle_id`) plus `source_ip`. **No User-Agent is collected or sent.**

When the service answers `ok:true` with a `url`, the response carries the header
`analytics-service: <url>`, which is what routes the app into the
notification-offer flow. A forward failure never fails the request: the endpoint
still answers and the attempt is recorded in `forward_log`.

## Known limitations

- **No password reset.** Deliberate: an endpoint that cannot send mail is worse
  than none. A user who forgets their password loses the account, and the app
  says so before registration. Deletion for that case goes through the support
  address.
- **Email addresses are not verified.** `emailVerified` is always `false`.
- **No 2FA**, and no account lockout beyond per-IP rate limiting.
- **No certificate pinning** in the iOS client.
- Sync is last-write-wins per record; there is no field-level merge.
- `sync_records` stores the client's JSON verbatim, so the database does not
  validate its shape. That is what lets the app model evolve without a redeploy.
- Rate-limit and `deletion_log` rows accumulate. `RateLimit::prune()` exists but
  is not scheduled; add a cron job if the tables grow.
