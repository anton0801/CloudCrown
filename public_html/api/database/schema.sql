-- CloudCrown API schema (MySQL 5.7+ / MariaDB 10.2+)
-- Identifiers are CHAR(36) UUID strings: the app already speaks UUIDs, and this
-- keeps every row readable in phpMyAdmin without conversion.

CREATE TABLE IF NOT EXISTS users (
    id             CHAR(36)     NOT NULL,
    email          VARCHAR(190) NOT NULL,
    password_hash  VARCHAR(255) NOT NULL,
    email_verified TINYINT(1)   NOT NULL DEFAULT 0,
    token_version  INT          NOT NULL DEFAULT 0,
    created_at     DATETIME(6)  NOT NULL,
    updated_at     DATETIME(6)  NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY users_email_unique (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS refresh_tokens (
    id         CHAR(36)    NOT NULL,
    user_id    CHAR(36)    NOT NULL,
    token_hash CHAR(64)    NOT NULL,
    expires_at DATETIME(6) NOT NULL,
    revoked_at DATETIME(6) NULL,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    UNIQUE KEY refresh_tokens_hash_unique (token_hash),
    KEY refresh_tokens_user_idx (user_id),
    CONSTRAINT refresh_tokens_user_fk FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- One row per user record. The payload is the client's own JSON, so the API
-- does not need redeploying every time the app model gains a field.
CREATE TABLE IF NOT EXISTS sync_records (
    user_id     CHAR(36)    NOT NULL,
    entity_type VARCHAR(32) NOT NULL,
    entity_id   CHAR(36)    NOT NULL,
    payload     JSON        NULL,
    updated_at  DATETIME(6) NOT NULL,
    deleted_at  DATETIME(6) NULL,
    server_time DATETIME(6) NOT NULL,
    PRIMARY KEY (user_id, entity_type, entity_id),
    KEY sync_records_delta_idx (user_id, server_time),
    CONSTRAINT sync_records_user_fk FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Attribution. The device key is af_id, so a reinstall produces a new row.
CREATE TABLE IF NOT EXISTS devices (
    id                CHAR(36)     NOT NULL,
    anchor            VARCHAR(190) NOT NULL,
    os_line           VARCHAR(190) NULL,
    vessel            VARCHAR(190) NULL,
    relay_id          VARCHAR(190) NULL,
    catalog_id        VARCHAR(190) NULL,
    signal_token      VARCHAR(512) NULL,
    locale_tag        VARCHAR(64)  NULL,
    ad_id             VARCHAR(64)  NULL,
    build_tag         VARCHAR(64)  NULL,
    hull              VARCHAR(64)  NULL,
    tz                VARCHAR(64)  NULL,
    source_ip         VARCHAR(64)  NULL,
    launch_count      INT          NOT NULL DEFAULT 0,
    attr_status       VARCHAR(64)  NULL,
    attr_media_source VARCHAR(190) NULL,
    attr_campaign     VARCHAR(190) NULL,
    created_at        DATETIME(6)  NOT NULL,
    updated_at        DATETIME(6)  NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY devices_anchor_unique (anchor)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Add-only. Full conversion JSON, deduplicated per device by payload hash.
CREATE TABLE IF NOT EXISTS device_traces (
    id           CHAR(36)    NOT NULL,
    device_id    CHAR(36)    NOT NULL,
    payload      JSON        NOT NULL,
    payload_hash CHAR(64)    NOT NULL,
    created_at   DATETIME(6) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY device_traces_dedup (device_id, payload_hash),
    CONSTRAINT device_traces_device_fk FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS forward_log (
    id              CHAR(36)     NOT NULL,
    device_id       CHAR(36)     NULL,
    endpoint        VARCHAR(32)  NOT NULL,
    request_body    JSON         NULL,
    response_status INT          NULL,
    response_body   TEXT         NULL,
    ok              TINYINT(1)   NULL,
    target_url      VARCHAR(512) NULL,
    error           VARCHAR(512) NULL,
    created_at      DATETIME(6)  NOT NULL,
    PRIMARY KEY (id),
    KEY forward_log_device_idx (device_id, created_at),
    CONSTRAINT forward_log_device_fk FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS device_accounts (
    device_id CHAR(36)    NOT NULL,
    user_id   CHAR(36)    NOT NULL,
    linked_at DATETIME(6) NOT NULL,
    PRIMARY KEY (device_id, user_id),
    KEY device_accounts_user_idx (user_id),
    CONSTRAINT device_accounts_device_fk FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE,
    CONSTRAINT device_accounts_user_fk FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Rate limiting lives in the database so counters survive across PHP processes.
CREATE TABLE IF NOT EXISTS rate_limits (
    bucket       CHAR(64)    NOT NULL,
    hits         INT         NOT NULL DEFAULT 0,
    window_start DATETIME(6) NOT NULL,
    PRIMARY KEY (bucket),
    KEY rate_limits_window_idx (window_start)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Audit of deletions. Holds no personal data, only the former account id.
CREATE TABLE IF NOT EXISTS deletion_log (
    id         CHAR(36)    NOT NULL,
    user_id    CHAR(36)    NOT NULL,
    deleted_at DATETIME(6) NOT NULL,
    purge_at   DATETIME(6) NOT NULL,
    PRIMARY KEY (id),
    KEY deletion_log_purge_idx (purge_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
