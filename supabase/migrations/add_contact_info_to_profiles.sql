-- Add address and phone_number columns to profiles table if they don't exist
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS address text;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS phone_number text;