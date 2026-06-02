-- Migration: convert transaction money to DECIMAL(15,0)
ALTER TABLE transactions
  MODIFY COLUMN amount DECIMAL(15,0) NOT NULL DEFAULT 0;
