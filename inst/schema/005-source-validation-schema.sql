CREATE TABLE IF NOT EXISTS source_validation_schema (
    validation_schema_id UUID PRIMARY KEY,
    source_type VARCHAR NOT NULL,
    schema_identifier VARCHAR NOT NULL,
    schema_dialect VARCHAR NOT NULL,
    schema_checksum_sha256 VARCHAR NOT NULL,
    compatibility_id VARCHAR,
    compatibility_checksum_sha256 VARCHAR,
    effective_schema_checksum_sha256 VARCHAR NOT NULL,
    raw_schema BLOB NOT NULL,
    raw_compatibility BLOB,
    UNIQUE (
        source_type,
        schema_checksum_sha256,
        effective_schema_checksum_sha256
    )
);

ALTER TABLE source_snapshot
    ADD COLUMN IF NOT EXISTS validation_schema_id UUID;

ALTER TABLE source_import_issue
    ADD COLUMN IF NOT EXISTS validation_layer VARCHAR;

ALTER TABLE source_record_issue
    ADD COLUMN IF NOT EXISTS validation_layer VARCHAR;
