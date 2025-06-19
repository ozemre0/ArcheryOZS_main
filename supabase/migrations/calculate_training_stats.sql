CREATE OR REPLACE FUNCTION calculate_training_stats(training_id_param UUID)
RETURNS TABLE (
    total_arrows INTEGER,
    total_score INTEGER,
    average NUMERIC,
    x_count INTEGER
) LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COALESCE(SUM(array_length(arrows, 1)), 0)::INTEGER as total_arrows,
        COALESCE(SUM(total_score), 0)::INTEGER as total_score,
        CASE 
            WHEN SUM(array_length(arrows, 1)) > 0 
            THEN (SUM(total_score)::NUMERIC / SUM(array_length(arrows, 1)))::NUMERIC 
            ELSE 0 
        END as average,
        COALESCE(SUM(x_count), 0)::INTEGER as x_count
    FROM training_series
    WHERE training_id = training_id_param;
END;
$$;