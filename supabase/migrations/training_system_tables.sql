-- Antrenman oturumu tablosu
CREATE TABLE IF NOT EXISTS training_sessions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  distance INTEGER NOT NULL,
  bow_type TEXT NOT NULL,
  is_indoor BOOLEAN NOT NULL DEFAULT true,
  notes TEXT,
  total_arrows INTEGER NOT NULL DEFAULT 0,
  total_score INTEGER NOT NULL DEFAULT 0,
  average NUMERIC(5,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Antrenman serisi tablosu
CREATE TABLE IF NOT EXISTS training_series (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  training_id UUID NOT NULL REFERENCES training_sessions(id) ON DELETE CASCADE,
  series_number INTEGER NOT NULL,
  arrows INTEGER[] NOT NULL,
  total_score INTEGER NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- İndeksler
CREATE INDEX IF NOT EXISTS idx_training_sessions_user ON training_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_training_sessions_date ON training_sessions(date);
CREATE INDEX IF NOT EXISTS idx_training_series_training ON training_series(training_id);

-- RLS (Row Level Security) politikaları

-- 1. training_sessions tablosu için RLS
ALTER TABLE training_sessions ENABLE ROW LEVEL SECURITY;

-- Kendi antrenmanlarını okuma politikası
CREATE POLICY read_own_trainings ON training_sessions 
  FOR SELECT USING (auth.uid() = user_id);

-- Kendi antrenmanlarını ekleme politikası
CREATE POLICY insert_own_trainings ON training_sessions 
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Kendi antrenmanlarını güncelleme politikası
CREATE POLICY update_own_trainings ON training_sessions 
  FOR UPDATE USING (auth.uid() = user_id);

-- Kendi antrenmanlarını silme politikası
CREATE POLICY delete_own_trainings ON training_sessions 
  FOR DELETE USING (auth.uid() = user_id);

-- Antrenörlerin sporcuların antrenmanlarını okuma politikası (Atlet-Antrenör ilişkisi üzerinden)
CREATE POLICY read_athletes_trainings ON training_sessions 
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM athlete_coach ac
      WHERE ac.athlete_id = training_sessions.user_id
      AND ac.coach_id = auth.uid()
    )
  );

-- 2. training_series tablosu için RLS
ALTER TABLE training_series ENABLE ROW LEVEL SECURITY;

-- Kendi antrenman serilerini okuma politikası
CREATE POLICY read_own_series ON training_series 
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM training_sessions ts
      WHERE ts.id = training_series.training_id
      AND ts.user_id = auth.uid()
    )
  );

-- Kendi antrenman serilerini ekleme politikası
CREATE POLICY insert_own_series ON training_series 
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM training_sessions ts
      WHERE ts.id = training_series.training_id
      AND ts.user_id = auth.uid()
    )
  );

-- Kendi antrenman serilerini güncelleme politikası
CREATE POLICY update_own_series ON training_series 
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM training_sessions ts
      WHERE ts.id = training_series.training_id
      AND ts.user_id = auth.uid()
    )
  );

-- Kendi antrenman serilerini silme politikası
CREATE POLICY delete_own_series ON training_series 
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM training_sessions ts
      WHERE ts.id = training_series.training_id
      AND ts.user_id = auth.uid()
    )
  );

-- Antrenörlerin sporcuların antrenman serilerini okuma politikası
CREATE POLICY read_athletes_series ON training_series 
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM training_sessions ts
      JOIN athlete_coach ac ON ac.athlete_id = ts.user_id
      WHERE ts.id = training_series.training_id
      AND ac.coach_id = auth.uid()
    )
  );

-- Bildirim fonksiyonları (updated_at alanını otomatik güncellemek için)
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger'lar
CREATE TRIGGER update_training_sessions_updated_at
BEFORE UPDATE ON training_sessions
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_training_series_updated_at
BEFORE UPDATE ON training_series
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

-- Antrenman oturumu istatistiklerini güncellemek için fonksiyon
CREATE OR REPLACE FUNCTION update_training_session_stats()
RETURNS TRIGGER AS $$
DECLARE
    arrows_count INTEGER := 0;
    total_score INTEGER := 0;
    avg_score NUMERIC(5,2) := 0;
BEGIN
    -- Tüm serilerdeki ok sayısını ve toplam puanı hesapla
    SELECT 
        COALESCE(SUM(ARRAY_LENGTH(arrows, 1)), 0),
        COALESCE(SUM(total_score), 0)
    INTO 
        arrows_count,
        total_score
    FROM 
        training_series
    WHERE 
        training_id = NEW.training_id;
    
    -- Ortalamayı hesapla
    IF arrows_count > 0 THEN
        avg_score := total_score::NUMERIC / arrows_count;
    END IF;
    
    -- Antrenman oturumunu güncelle
    UPDATE training_sessions
    SET 
        total_arrows = arrows_count,
        total_score = total_score,
        average = avg_score,
        updated_at = now()
    WHERE 
        id = NEW.training_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Yeni seri eklendiğinde veya güncellendiğinde antrenman oturumu istatistiklerini güncelle
CREATE TRIGGER update_session_after_series_change
AFTER INSERT OR UPDATE OR DELETE ON training_series
FOR EACH ROW
EXECUTE FUNCTION update_training_session_stats();

-- Add arrows_per_series column
ALTER TABLE training_sessions
ADD COLUMN IF NOT EXISTS arrows_per_series INTEGER NOT NULL DEFAULT 6;

-- Update existing records to use 6 arrows per series
UPDATE training_sessions
SET arrows_per_series = 6
WHERE arrows_per_series = 3 OR arrows_per_series IS NULL;