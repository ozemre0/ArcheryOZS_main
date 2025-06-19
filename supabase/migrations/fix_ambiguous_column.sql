-- "total_score" belirsiz sütun referansı hatasını düzeltmek için fonksiyonu güncelle
CREATE OR REPLACE FUNCTION update_training_session_stats()
RETURNS TRIGGER AS $$
DECLARE
    arrows_count INTEGER := 0;
    series_total_score INTEGER := 0;
    avg_score NUMERIC(5,2) := 0;
BEGIN
    -- Tüm serilerdeki ok sayısını ve toplam puanı hesapla
    -- Sütun adlarını tam olarak belirtmek için tablo alias kullanıyoruz
    SELECT 
        COALESCE(SUM(ARRAY_LENGTH(ts.arrows, 1)), 0),
        COALESCE(SUM(ts.total_score), 0)
    INTO 
        arrows_count,
        series_total_score
    FROM 
        training_series ts
    WHERE 
        ts.training_id = NEW.training_id;
    
    -- Ortalamayı hesapla
    IF arrows_count > 0 THEN
        avg_score := series_total_score::NUMERIC / arrows_count;
    END IF;
    
    -- Antrenman oturumunu güncelle
    UPDATE training_sessions
    SET 
        total_arrows = arrows_count,
        total_score = series_total_score,
        average = avg_score,
        updated_at = now()
    WHERE 
        id = NEW.training_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;