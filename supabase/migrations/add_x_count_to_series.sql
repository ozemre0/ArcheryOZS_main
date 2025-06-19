-- Add x_count column to training_series table
ALTER TABLE training_series 
ADD COLUMN IF NOT EXISTS x_count INTEGER NOT NULL DEFAULT 0;

-- Update the existing function to calculate x_count
CREATE OR REPLACE FUNCTION update_training_session_stats()
RETURNS TRIGGER AS $$
DECLARE
    arrows_count INTEGER := 0;
    series_total_score INTEGER := 0;
    total_x_count INTEGER := 0;
    avg_score NUMERIC(5,2) := 0;
BEGIN
    -- Calculate arrow count, total score, and X count from all series
    SELECT 
        COALESCE(SUM(ARRAY_LENGTH(ts.arrows, 1)), 0),
        COALESCE(SUM(ts.total_score), 0),
        COALESCE(SUM(ts.x_count), 0)
    INTO 
        arrows_count,
        series_total_score,
        total_x_count
    FROM 
        training_series ts
    WHERE 
        ts.training_id = NEW.training_id;
    
    -- Calculate average
    IF arrows_count > 0 THEN
        avg_score := series_total_score::NUMERIC / arrows_count;
    END IF;
    
    -- Update training session
    UPDATE training_sessions
    SET 
        total_arrows = arrows_count,
        total_score = series_total_score,
        average = avg_score,
        x_count = total_x_count,
        updated_at = now()
    WHERE 
        id = NEW.training_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Update the training_sessions table to include x_count
ALTER TABLE training_sessions
ADD COLUMN IF NOT EXISTS x_count INTEGER NOT NULL DEFAULT 0;