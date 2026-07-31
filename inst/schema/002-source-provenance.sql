ALTER TABLE source_snapshot
    ADD COLUMN IF NOT EXISTS source_relative_path VARCHAR;

CREATE TABLE IF NOT EXISTS source_import_summary (
    summary_id UUID PRIMARY KEY,
    snapshot_id UUID NOT NULL REFERENCES source_snapshot(snapshot_id),
    summary_code VARCHAR NOT NULL,
    message VARCHAR NOT NULL,
    item_count INTEGER NOT NULL
);
