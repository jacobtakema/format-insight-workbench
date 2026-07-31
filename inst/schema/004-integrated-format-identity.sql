INSERT INTO registry
SELECT
    uuid(),
    'pronom',
    'PRONOM',
    'fmt|x-fmt',
    'https://github.com/nationalarchives/pronom'
WHERE NOT EXISTS (
    SELECT 1 FROM registry WHERE registry_code = 'pronom'
);

INSERT INTO format_identity
SELECT
    uuid(),
    registry.registry_id,
    regexp_extract(format.puid, '^([^/]+)/', 1),
    format.puid
FROM (
    SELECT DISTINCT puid
    FROM source_format
    WHERE regexp_matches(puid, '^(fmt|x-fmt)/[0-9]+$')
) AS format
CROSS JOIN registry
WHERE registry.registry_code = 'pronom'
  AND NOT EXISTS (
      SELECT 1
      FROM format_identity AS identity
      WHERE identity.registry_id = registry.registry_id
        AND identity.identifier = format.puid
  );

CREATE TABLE IF NOT EXISTS source_format_identity (
    source_format_id UUID PRIMARY KEY REFERENCES source_format(source_format_id),
    format_identity_id UUID NOT NULL REFERENCES format_identity(format_identity_id)
);

INSERT INTO source_format_identity
SELECT format.source_format_id, identity.format_identity_id
FROM source_format AS format
JOIN format_identity AS identity ON identity.identifier = format.puid
JOIN registry ON registry.registry_id = identity.registry_id
WHERE registry.registry_code = 'pronom'
  AND NOT EXISTS (
      SELECT 1
      FROM source_format_identity AS link
      WHERE link.source_format_id = format.source_format_id
  );

CREATE INDEX IF NOT EXISTS source_format_snapshot_puid_index
    ON source_format (snapshot_id, puid);

CREATE INDEX IF NOT EXISTS source_format_identity_index
    ON source_format (format_identity_id);

CREATE INDEX IF NOT EXISTS source_format_identity_identity_index
    ON source_format_identity (format_identity_id);

CREATE INDEX IF NOT EXISTS source_record_snapshot_status_index
    ON source_record (snapshot_id, parse_status);
