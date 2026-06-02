-- Migration: add entry_ts DATETIME to calendar_entries
ALTER TABLE calendar_entries
  ADD COLUMN entry_ts DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
  AFTER entry_date;

-- Optional: backfill entry_ts from existing date_key (sets time to 00:00:00)
-- UPDATE calendar_entries
-- SET entry_ts = STR_TO_DATE(CONCAT(date_key, ' 00:00:00'), '%Y-%m-%d %H:%i:%s')
-- WHERE entry_ts IS NULL;
