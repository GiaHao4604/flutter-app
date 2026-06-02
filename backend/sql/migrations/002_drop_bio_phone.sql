-- Migration: remove unused profile fields from users table
ALTER TABLE users
  DROP COLUMN bio,
  DROP COLUMN phone;
