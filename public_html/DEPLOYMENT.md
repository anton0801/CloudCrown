# CloudCrown — deploy to cloudcrown-app.space

Everything in this folder goes into `public_html` (the domain's document root).
The website is served at the root; the API answers under `/api/v1/...`.

```
public_html/
  index.html  privacy.html  support.html  assets/   .htaccess     ← website
  api/                                                             ← REST API
    index.php  .htaccess  core/ security/ controllers/ database/ tools/
    .env        ← YOU CREATE THIS from api/.env.example
```

## Steps (cPanel)

1. **Upload** the entire contents of this folder into `public_html`
   (enable File Manager → Settings → Show Hidden Files so `.htaccess` uploads).

2. **Database** — cPanel → MySQL® Databases: create a DB + user, grant ALL.

3. **Config** — copy `api/.env.example` to `api/.env` and set `DB_NAME`,
   `DB_USER`, `DB_PASS`. `JWT_SECRET` and `PAYLOAD_KEY` are already filled in
   and must stay exactly as they are (`PAYLOAD_KEY` matches the app).

4. **Tables** — Terminal: `cd ~/public_html/api && php database/migrate.php`
   (or import `api/database/schema.sql` in phpMyAdmin).

5. **HTTPS** — SSL/TLS Status → Run AutoSSL. Then set `FORCE_HTTPS=true`
   in `api/.env`.

6. **Check**
   ```
   curl https://cloudcrown-app.space/api/v1/health
   curl -o /dev/null -w "%{http_code}\n" https://cloudcrown-app.space/
   ```

## Before going public — replace placeholders in the HTML

`APP_STORE_URL`, `LEGAL_ENTITY_NAME`, `LEGAL_ENTITY_ADDRESS`, `EFFECTIVE_DATE`,
`HOSTING_REGION`.

## Optional, not needed on the server
`api/tests/` and the `*.md` files never affect runtime and are blocked from the
web by `.htaccess`. You may delete them from the upload if you prefer.

Full reference: `api/README.md`.
