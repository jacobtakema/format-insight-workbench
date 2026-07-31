CREATE TABLE IF NOT EXISTS source_snapshot (
    snapshot_id UUID PRIMARY KEY,
    source_type VARCHAR NOT NULL,
    source_version VARCHAR,
    source_filename VARCHAR NOT NULL,
    source_relative_path VARCHAR,
    source_created_at TIMESTAMP,
    checksum_sha256 VARCHAR NOT NULL,
    imported_at TIMESTAMP NOT NULL,
    import_status VARCHAR NOT NULL CHECK (import_status IN ('succeeded')),
    raw_content BLOB NOT NULL,
    UNIQUE (source_type, checksum_sha256)
);

CREATE TABLE IF NOT EXISTS source_format (
    source_format_id UUID PRIMARY KEY,
    snapshot_id UUID NOT NULL REFERENCES source_snapshot(snapshot_id),
    source_record_id VARCHAR NOT NULL,
    puid VARCHAR NOT NULL,
    format_name VARCHAR NOT NULL,
    format_version VARCHAR,
    raw_record VARCHAR,
    UNIQUE (snapshot_id, source_record_id),
    UNIQUE (snapshot_id, puid)
);

CREATE TABLE IF NOT EXISTS source_format_identifier (
    source_format_id UUID NOT NULL REFERENCES source_format(source_format_id),
    identifier_type VARCHAR NOT NULL,
    identifier_value VARCHAR NOT NULL,
    original_value VARCHAR,
    ordinal INTEGER NOT NULL,
    UNIQUE (source_format_id, identifier_type, identifier_value)
);

CREATE TABLE IF NOT EXISTS source_format_extension (
    source_format_id UUID NOT NULL REFERENCES source_format(source_format_id),
    extension VARCHAR NOT NULL,
    original_value VARCHAR,
    ordinal INTEGER NOT NULL,
    UNIQUE (source_format_id, extension)
);

CREATE TABLE IF NOT EXISTS source_format_signature (
    source_format_id UUID NOT NULL REFERENCES source_format(source_format_id),
    signature_kind VARCHAR NOT NULL,
    source_signature_id VARCHAR NOT NULL,
    raw_signature VARCHAR,
    UNIQUE (source_format_id, signature_kind, source_signature_id)
);

CREATE TABLE IF NOT EXISTS source_format_relationship (
    snapshot_id UUID NOT NULL REFERENCES source_snapshot(snapshot_id),
    subject_source_record_id VARCHAR NOT NULL,
    relationship_type VARCHAR NOT NULL,
    object_source_record_id VARCHAR,
    object_puid VARCHAR,
    original_relationship_type VARCHAR,
    CHECK (object_source_record_id IS NOT NULL OR object_puid IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS source_import_issue (
    issue_id UUID PRIMARY KEY,
    snapshot_id UUID NOT NULL REFERENCES source_snapshot(snapshot_id),
    severity VARCHAR NOT NULL,
    issue_code VARCHAR NOT NULL,
    record_locator VARCHAR,
    message VARCHAR NOT NULL,
    raw_value VARCHAR
);

CREATE TABLE IF NOT EXISTS source_import_summary (
    summary_id UUID PRIMARY KEY,
    snapshot_id UUID NOT NULL REFERENCES source_snapshot(snapshot_id),
    summary_code VARCHAR NOT NULL,
    message VARCHAR NOT NULL,
    item_count INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS policy_profile (
    profile_id UUID PRIMARY KEY,
    name VARCHAR NOT NULL,
    description VARCHAR,
    version VARCHAR,
    created_at TIMESTAMP NOT NULL,
    modified_at TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS policy_entry (
    entry_id UUID PRIMARY KEY,
    profile_id UUID NOT NULL REFERENCES policy_profile(profile_id),
    information_category VARCHAR,
    display_name VARCHAR NOT NULL,
    preferred_status VARCHAR NOT NULL CHECK (
        preferred_status IN ('preferred', 'acceptable', 'under_review', 'prohibited')
    ),
    notes VARCHAR,
    condition VARCHAR,
    valid_from DATE,
    valid_to DATE,
    CHECK (valid_from IS NULL OR valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS policy_entry_puid (
    mapping_id UUID PRIMARY KEY,
    entry_id UUID NOT NULL REFERENCES policy_entry(entry_id),
    puid VARCHAR NOT NULL,
    relationship_type VARCHAR,
    required BOOLEAN NOT NULL DEFAULT FALSE,
    UNIQUE (entry_id, puid, relationship_type)
);

CREATE TABLE IF NOT EXISTS validation_result (
    validation_id UUID PRIMARY KEY,
    profile_id UUID NOT NULL REFERENCES policy_profile(profile_id),
    snapshot_id UUID NOT NULL REFERENCES source_snapshot(snapshot_id),
    rule_code VARCHAR NOT NULL,
    severity VARCHAR NOT NULL,
    message VARCHAR NOT NULL,
    entry_id UUID REFERENCES policy_entry(entry_id),
    puid VARCHAR,
    created_at TIMESTAMP NOT NULL
);
