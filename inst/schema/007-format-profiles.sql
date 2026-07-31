ALTER TABLE policy_profile ADD COLUMN IF NOT EXISTS publisher VARCHAR;
ALTER TABLE policy_profile ADD COLUMN IF NOT EXISTS publication_date DATE;
ALTER TABLE policy_profile ADD COLUMN IF NOT EXISTS source_name VARCHAR;
ALTER TABLE policy_profile ADD COLUMN IF NOT EXISTS source_url VARCHAR;
ALTER TABLE policy_profile ADD COLUMN IF NOT EXISTS source_snapshot_id UUID;

ALTER TABLE policy_entry ADD COLUMN IF NOT EXISTS source_sheet VARCHAR;
ALTER TABLE policy_entry ADD COLUMN IF NOT EXISTS source_row INTEGER;
ALTER TABLE policy_entry ADD COLUMN IF NOT EXISTS information_subtype VARCHAR;
ALTER TABLE policy_entry ADD COLUMN IF NOT EXISTS extension_label VARCHAR;
ALTER TABLE policy_entry ADD COLUMN IF NOT EXISTS version_label VARCHAR;
ALTER TABLE policy_entry ADD COLUMN IF NOT EXISTS source_status VARCHAR;
ALTER TABLE policy_entry ADD COLUMN IF NOT EXISTS rationale VARCHAR;
ALTER TABLE policy_entry ADD COLUMN IF NOT EXISTS raw_source_data VARCHAR;
ALTER TABLE policy_entry ADD COLUMN IF NOT EXISTS mapping_status VARCHAR;

ALTER TABLE policy_entry_puid ADD COLUMN IF NOT EXISTS raw_puid VARCHAR;
ALTER TABLE policy_entry_puid ADD COLUMN IF NOT EXISTS mapping_status VARCHAR;

CREATE TABLE IF NOT EXISTS profile_rationale (
    profile_rationale_id UUID PRIMARY KEY,
    profile_id UUID NOT NULL REFERENCES policy_profile(profile_id),
    source_sheet VARCHAR NOT NULL,
    source_row INTEGER NOT NULL,
    information_category VARCHAR,
    information_subtype VARCHAR,
    format_label VARCHAR,
    open_standard VARCHAR,
    adoption_support VARCHAR,
    independence_interoperability VARCHAR,
    transparency VARCHAR,
    self_documenting VARCHAR,
    patents_licences VARCHAR,
    rationale VARCHAR,
    raw_source_data VARCHAR NOT NULL,
    UNIQUE (profile_id, source_sheet, source_row)
);

CREATE TABLE IF NOT EXISTS profile_entry_rationale (
    profile_entry_id UUID NOT NULL REFERENCES policy_entry(entry_id),
    profile_rationale_id UUID NOT NULL REFERENCES profile_rationale(profile_rationale_id),
    link_method VARCHAR NOT NULL,
    PRIMARY KEY (profile_entry_id, profile_rationale_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS policy_profile_source_snapshot_index
    ON policy_profile (source_snapshot_id);
CREATE INDEX IF NOT EXISTS policy_entry_profile_source_row_index
    ON policy_entry (profile_id, source_row);
CREATE INDEX IF NOT EXISTS policy_entry_puid_value_index
    ON policy_entry_puid (puid);
