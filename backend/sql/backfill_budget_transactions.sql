-- Backfill transactions from calendar entries so budget aggregation can work
-- safely for historical records.

-- 1) Align transaction_date with the canonical date_key saved in calendar_entries.
UPDATE transactions t
JOIN calendar_entries ce
  ON ce.id = t.calendar_entry_id
 AND ce.user_id = t.user_id
SET t.transaction_date = ce.date_key
WHERE ce.date_key IS NOT NULL
  AND ce.date_key <> ''
  AND (t.transaction_date IS NULL OR t.transaction_date <> ce.date_key);

-- 2) Fill missing category_id from calendar_entries.category_key using categories.slug
--    or numeric id string fallback.
UPDATE transactions t
JOIN calendar_entries ce
  ON ce.id = t.calendar_entry_id
 AND ce.user_id = t.user_id
SET t.category_id = (
  SELECT c.id
  FROM categories c
  WHERE (c.user_id = t.user_id OR c.user_id IS NULL)
    AND (
      c.slug = ce.category_key
      OR CAST(c.id AS CHAR) = ce.category_key
    )
  ORDER BY c.user_id IS NULL ASC, c.id ASC
  LIMIT 1
)
WHERE (t.category_id IS NULL OR t.category_id = 0)
  AND ce.category_key IS NOT NULL
  AND ce.category_key <> '';

-- 3) Optional diagnostics after backfill.
-- SELECT COUNT(*) AS missing_category_after_backfill
-- FROM transactions
-- WHERE category_id IS NULL;
