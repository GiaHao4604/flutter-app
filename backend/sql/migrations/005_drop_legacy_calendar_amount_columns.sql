-- Migration: drop legacy money columns from calendar_entries after backfill
ALTER TABLE calendar_entries
  DROP COLUMN amount,
  DROP COLUMN is_expense;
