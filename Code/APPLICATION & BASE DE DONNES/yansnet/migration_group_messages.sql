-- ─────────────────────────────────────────────────────────────────────────────
-- MIGRATION — Ajouter les colonnes manquantes à group_messages
-- À exécuter UNE SEULE FOIS dans PostgreSQL
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE group_messages
  ADD COLUMN IF NOT EXISTS file_url   TEXT,
  ADD COLUMN IF NOT EXISTS file_type  VARCHAR(20),
  ADD COLUMN IF NOT EXISTS file_name  TEXT,
  ADD COLUMN IF NOT EXISTS file_size  BIGINT,
  ADD COLUMN IF NOT EXISTS is_system  BOOLEAN DEFAULT FALSE;

-- Vérifier le résultat
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'group_messages'
ORDER BY ordinal_position;
