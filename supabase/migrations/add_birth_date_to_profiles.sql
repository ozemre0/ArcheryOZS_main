ALTER TABLE profiles ADD COLUMN birth_date timestamp with time zone;

-- Varolan kayıtlar için varsayılan bir değer atayalım
UPDATE profiles SET birth_date = created_at WHERE birth_date IS NULL;