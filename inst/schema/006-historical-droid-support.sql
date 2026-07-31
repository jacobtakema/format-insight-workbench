CREATE TABLE IF NOT EXISTS droid_snapshot_profile (
    snapshot_id UUID PRIMARY KEY REFERENCES source_snapshot(snapshot_id),
    support_mode VARCHAR NOT NULL CHECK (
        support_mode IN ('puid_comparison', 'partial_historical', 'snapshot_only')
    ),
    xml_dialect VARCHAR NOT NULL,
    format_count INTEGER NOT NULL,
    valid_puid_count INTEGER NOT NULL,
    placeholder_puid_count INTEGER NOT NULL,
    missing_puid_count INTEGER NOT NULL,
    invalid_puid_count INTEGER NOT NULL,
    CHECK (
        format_count >= 0
        AND valid_puid_count >= 0
        AND placeholder_puid_count >= 0
        AND missing_puid_count >= 0
        AND invalid_puid_count >= 0
        AND valid_puid_count + placeholder_puid_count
            + missing_puid_count + invalid_puid_count = format_count
    )
);

INSERT INTO droid_snapshot_profile
SELECT
    snapshot.snapshot_id,
    'puid_comparison',
    'pronom_signature_namespace',
    count(format.source_format_id),
    count(format.source_format_id),
    0,
    0,
    0
FROM source_snapshot AS snapshot
JOIN source_format AS format ON format.snapshot_id = snapshot.snapshot_id
WHERE snapshot.source_type = 'droid_binary_signature'
  AND NOT EXISTS (
      SELECT 1 FROM droid_snapshot_profile AS profile
      WHERE profile.snapshot_id = snapshot.snapshot_id
  )
GROUP BY snapshot.snapshot_id;
