CREATE TABLE system_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at_ms INTEGER NOT NULL,
    unix_timestamp INTEGER NOT NULL,
    host_version TEXT NOT NULL,
    remote_version TEXT,
    source TEXT NOT NULL DEFAULT 'host' CHECK(source IN ('host', 'remote')),
    action TEXT NOT NULL,
    level TEXT NOT NULL CHECK(level IN ('debug', 'info', 'warning', 'error')),
    category TEXT NOT NULL,
    message TEXT NOT NULL,
    metadata_json TEXT
);
CREATE INDEX system_logs_created_idx ON system_logs(created_at_ms);
CREATE INDEX system_logs_action_time_idx ON system_logs(action, unix_timestamp DESC);
CREATE INDEX system_logs_remote_time_idx ON system_logs(remote_version, unix_timestamp DESC);
CREATE INDEX system_logs_host_time_idx ON system_logs(host_version, unix_timestamp DESC);
CREATE INDEX system_logs_source_time_idx ON system_logs(source, unix_timestamp DESC);
PRAGMA user_version=1;
