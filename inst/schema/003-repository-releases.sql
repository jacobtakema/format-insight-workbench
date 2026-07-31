CREATE TABLE IF NOT EXISTS registry (
    registry_id UUID PRIMARY KEY,
    registry_code VARCHAR NOT NULL UNIQUE,
    name VARCHAR NOT NULL,
    identifier_namespace VARCHAR NOT NULL,
    repository_url VARCHAR
);

CREATE TABLE IF NOT EXISTS registry_release (
    registry_release_id UUID PRIMARY KEY,
    registry_id UUID NOT NULL REFERENCES registry(registry_id),
    release_kind VARCHAR NOT NULL,
    requested_reference VARCHAR,
    resolved_reference VARCHAR NOT NULL,
    released_at TIMESTAMP,
    archive_checksum_sha256 VARCHAR NOT NULL,
    UNIQUE (registry_id, resolved_reference, archive_checksum_sha256)
);

CREATE TABLE IF NOT EXISTS import_run (
    import_run_id UUID PRIMARY KEY,
    registry_id UUID REFERENCES registry(registry_id),
    source_type VARCHAR NOT NULL,
    repository_url VARCHAR,
    requested_reference VARCHAR,
    resolved_commit VARCHAR,
    resolved_commit_at TIMESTAMP,
    archive_checksum_sha256 VARCHAR,
    status VARCHAR NOT NULL CHECK (status IN ('running', 'succeeded', 'failed')),
    discovered_count INTEGER NOT NULL DEFAULT 0,
    parsed_count INTEGER NOT NULL DEFAULT 0,
    rejected_count INTEGER NOT NULL DEFAULT 0,
    warning_count INTEGER NOT NULL DEFAULT 0,
    error_count INTEGER NOT NULL DEFAULT 0,
    summary_message VARCHAR,
    started_at TIMESTAMP NOT NULL,
    completed_at TIMESTAMP
);

ALTER TABLE source_snapshot ADD COLUMN IF NOT EXISTS registry_release_id UUID;
ALTER TABLE source_snapshot ADD COLUMN IF NOT EXISTS import_run_id UUID;

CREATE TABLE IF NOT EXISTS source_record (
    source_record_uuid UUID PRIMARY KEY,
    snapshot_id UUID NOT NULL REFERENCES source_snapshot(snapshot_id),
    source_relative_path VARCHAR NOT NULL,
    source_filename VARCHAR NOT NULL,
    source_record_identifier VARCHAR,
    checksum_sha256 VARCHAR NOT NULL,
    raw_content BLOB NOT NULL,
    parse_status VARCHAR NOT NULL CHECK (parse_status IN ('parsed', 'rejected')),
    UNIQUE (snapshot_id, source_relative_path)
);

CREATE TABLE IF NOT EXISTS source_record_issue (
    record_issue_id UUID PRIMARY KEY,
    source_record_uuid UUID NOT NULL REFERENCES source_record(source_record_uuid),
    severity VARCHAR NOT NULL,
    issue_code VARCHAR NOT NULL,
    message VARCHAR NOT NULL,
    raw_value VARCHAR
);

CREATE TABLE IF NOT EXISTS format_identity (
    format_identity_id UUID PRIMARY KEY,
    registry_id UUID NOT NULL REFERENCES registry(registry_id),
    identifier_namespace VARCHAR NOT NULL,
    identifier VARCHAR NOT NULL,
    UNIQUE (registry_id, identifier_namespace, identifier)
);

ALTER TABLE source_format ADD COLUMN IF NOT EXISTS source_record_uuid UUID;
ALTER TABLE source_format ADD COLUMN IF NOT EXISTS format_identity_id UUID;

CREATE TABLE IF NOT EXISTS signature_set (
    signature_set_id UUID PRIMARY KEY,
    snapshot_id UUID NOT NULL REFERENCES source_snapshot(snapshot_id),
    signature_set_type VARCHAR NOT NULL CHECK (
        signature_set_type IN ('droid_binary', 'droid_container')
    ),
    signature_version VARCHAR,
    released_at TIMESTAMP,
    checksum_sha256 VARCHAR NOT NULL,
    UNIQUE (snapshot_id)
);

INSERT INTO signature_set
SELECT
    uuid(),
    snapshot.snapshot_id,
    'droid_binary',
    snapshot.source_version,
    snapshot.source_created_at,
    snapshot.checksum_sha256
FROM source_snapshot AS snapshot
WHERE snapshot.source_type = 'droid_binary_signature'
  AND NOT EXISTS (
      SELECT 1
      FROM signature_set
      WHERE signature_set.snapshot_id = snapshot.snapshot_id
  );

CREATE TABLE IF NOT EXISTS release_bundle (
    release_bundle_id UUID PRIMARY KEY,
    name VARCHAR NOT NULL,
    description VARCHAR,
    created_at TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS release_bundle_member (
    release_bundle_member_id UUID PRIMARY KEY,
    release_bundle_id UUID NOT NULL REFERENCES release_bundle(release_bundle_id),
    member_role VARCHAR NOT NULL CHECK (
        member_role IN ('pronom_repository', 'droid_binary', 'droid_container')
    ),
    snapshot_id UUID NOT NULL REFERENCES source_snapshot(snapshot_id),
    UNIQUE (release_bundle_id, member_role)
);
