-- Add gender column to profiles table if it doesn't exist
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS gender text;