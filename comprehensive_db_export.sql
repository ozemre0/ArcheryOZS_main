-- KAPSAMLI VERİTABANI ŞEMA ANALİZİ
-- Bu sorgu tüm tabloları, sütunları, ilişkileri, kısıtlamaları, indeksleri ve daha fazlasını içerir
-- Daha küçük parçalara bölünmüş ve optimize edilmiş

-- 1. TABLOLARI LİSTELE
SELECT 
    table_name,
    'TABLE' as object_type,
    '' as column_name,
    '' as data_type,
    '' as constraints,
    '' as references
FROM 
    information_schema.tables
WHERE 
    table_schema = 'public'
    AND table_type = 'BASE TABLE'
ORDER BY 
    table_name;

-- 2. SÜTUNLARI VE TİPLERİNİ LİSTELE
SELECT 
    t.table_name,
    'COLUMN' as object_type,
    c.column_name,
    c.data_type,
    c.is_nullable || 
    CASE WHEN c.column_default IS NOT NULL THEN ', DEFAULT: ' || c.column_default ELSE '' END as constraints,
    '' as references
FROM 
    information_schema.tables t
JOIN 
    information_schema.columns c ON t.table_name = c.table_name AND t.table_schema = c.table_schema
WHERE 
    t.table_schema = 'public'
    AND t.table_type = 'BASE TABLE'
ORDER BY 
    t.table_name, 
    c.ordinal_position;

-- 3. PRIMARY KEY KISITLAMALARINI LİSTELE
SELECT 
    tc.table_name,
    'PRIMARY KEY' as object_type,
    string_agg(kcu.column_name, ', ') as column_name,
    '' as data_type,
    tc.constraint_name as constraints,
    '' as references
FROM 
    information_schema.table_constraints tc
JOIN 
    information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
    AND tc.table_schema = kcu.table_schema
WHERE 
    tc.constraint_type = 'PRIMARY KEY'
    AND tc.table_schema = 'public'
GROUP BY
    tc.table_name, tc.constraint_name
ORDER BY 
    tc.table_name;

-- 4. FOREIGN KEY KISITLAMALARINI LİSTELE
SELECT 
    tc.table_name,
    'FOREIGN KEY' as object_type,
    kcu.column_name,
    '' as data_type,
    tc.constraint_name as constraints,
    ccu.table_name || '(' || ccu.column_name || ')' as references
FROM 
    information_schema.table_constraints tc
JOIN 
    information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name 
    AND tc.table_schema = kcu.table_schema
JOIN 
    information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name
    AND tc.table_schema = ccu.table_schema
WHERE 
    tc.constraint_type = 'FOREIGN KEY'
    AND tc.table_schema = 'public'
ORDER BY 
    tc.table_name,
    kcu.column_name;

-- 5. UNIQUE KISITLAMALARINI LİSTELE
SELECT 
    tc.table_name,
    'UNIQUE' as object_type,
    string_agg(kcu.column_name, ', ') as column_name,
    '' as data_type,
    tc.constraint_name as constraints,
    '' as references
FROM 
    information_schema.table_constraints tc
JOIN 
    information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
    AND tc.table_schema = kcu.table_schema
WHERE 
    tc.constraint_type = 'UNIQUE'
    AND tc.table_schema = 'public'
GROUP BY
    tc.table_name, tc.constraint_name
ORDER BY 
    tc.table_name;

-- 6. CHECK KISITLAMALARINI LİSTELE
SELECT 
    tc.table_name,
    'CHECK' as object_type,
    '' as column_name,
    '' as data_type,
    tc.constraint_name as constraints,
    pg_get_constraintdef(con.oid) as references
FROM 
    information_schema.table_constraints tc
JOIN 
    pg_constraint con ON con.conname = tc.constraint_name
JOIN 
    pg_class c ON c.oid = con.conrelid
JOIN 
    pg_namespace n ON n.oid = c.relnamespace AND n.nspname = tc.table_schema
WHERE 
    tc.constraint_type = 'CHECK'
    AND tc.table_schema = 'public'
    AND tc.constraint_name NOT LIKE '%_not_null'
ORDER BY 
    tc.table_name;

-- 7. İNDEKSLERİ LİSTELE (PRIMARY VE UNIQUE INDEXLER HARİÇ)
SELECT 
    tablename as table_name,
    'INDEX' as object_type,
    indexname as column_name,
    '' as data_type,
    indexdef as constraints,
    '' as references
FROM 
    pg_indexes
WHERE 
    schemaname = 'public'
    AND indexname NOT IN (
        SELECT constraint_name 
        FROM information_schema.table_constraints 
        WHERE constraint_type IN ('PRIMARY KEY', 'UNIQUE') 
        AND table_schema = 'public'
    )
ORDER BY 
    tablename, indexname;

-- 8. GÖRÜNÜMLERİ (VIEW) LİSTELE
SELECT 
    table_name,
    'VIEW' as object_type,
    '' as column_name,
    '' as data_type,
    '' as constraints,
    view_definition as references
FROM 
    information_schema.views
WHERE 
    table_schema = 'public'
ORDER BY 
    table_name;

-- 9. TETİKLEYİCİLERİ (TRIGGER) LİSTELE
SELECT 
    event_object_table as table_name,
    'TRIGGER' as object_type,
    trigger_name as column_name,
    '' as data_type,
    action_timing || ' ' || event_manipulation as constraints,
    action_statement as references
FROM 
    information_schema.triggers
WHERE 
    trigger_schema = 'public'
ORDER BY 
    event_object_table, trigger_name;

-- 10. TABLO İSTATİSTİKLERİ - SATIR SAYISI TAHMİNLERİ (DÜZELTİLMİŞ)
SELECT
    relname as table_name,
    'STATISTICS' as object_type,
    'row_count_estimate' as column_name,
    '' as data_type,
    pg_stat_get_live_tuples(c.oid)::text as constraints, -- n_live_tup yerine pg_stat_get_live_tuples() kullanıldı
    pg_size_pretty(pg_total_relation_size(c.oid)) as references
FROM
    pg_class c
JOIN
    pg_namespace n ON n.oid = c.relnamespace
WHERE
    relkind = 'r'
    AND n.nspname = 'public'
ORDER BY
    c.relname;

-- 11. BİRLEŞTİRİLMİŞ KAPSAMLI ANALİZ (TÜM TABLO VE İLİŞKİLERİN CSV'Sİ)
WITH table_columns AS (
    SELECT
        t.table_name,
        c.column_name,
        c.data_type,
        c.is_nullable,
        c.column_default,
        CASE WHEN EXISTS (
            SELECT 1 FROM information_schema.table_constraints tc
            JOIN information_schema.constraint_column_usage ccu 
            ON tc.constraint_name = ccu.constraint_name
            WHERE tc.table_schema = 'public'
            AND tc.constraint_type = 'PRIMARY KEY'
            AND ccu.table_name = c.table_name
            AND ccu.column_name = c.column_name
        ) THEN 'PK' ELSE '' END as is_primary_key
    FROM
        information_schema.tables t
    JOIN
        information_schema.columns c ON t.table_name = c.table_name AND t.table_schema = c.table_schema
    WHERE
        t.table_schema = 'public'
        AND t.table_type = 'BASE TABLE'
),
foreign_keys AS (
    SELECT
        kcu.table_name,
        kcu.column_name,
        ccu.table_name AS referenced_table,
        ccu.column_name AS referenced_column
    FROM
        information_schema.table_constraints tc
    JOIN
        information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
    JOIN
        information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name AND tc.table_schema = ccu.table_schema
    WHERE
        tc.constraint_type = 'FOREIGN KEY'
        AND tc.table_schema = 'public'
),
unique_keys AS (
    SELECT
        tc.table_name,
        kcu.column_name,
        'UNIQUE' as constraint_type
    FROM
        information_schema.table_constraints tc
    JOIN
        information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
    WHERE
        tc.constraint_type = 'UNIQUE'
        AND tc.table_schema = 'public'
)
SELECT
    tc.table_name,
    tc.column_name,
    tc.data_type,
    tc.is_nullable,
    COALESCE(tc.column_default, 'NULL') as column_default,
    tc.is_primary_key,
    CASE WHEN uk.constraint_type IS NOT NULL THEN 'UNIQUE' ELSE '' END as is_unique,
    fk.referenced_table,
    fk.referenced_column
FROM
    table_columns tc
LEFT JOIN
    foreign_keys fk ON tc.table_name = fk.table_name AND tc.column_name = fk.column_name
LEFT JOIN
    unique_keys uk ON tc.table_name = uk.table_name AND tc.column_name = uk.column_name
ORDER BY
    tc.table_name,
    CASE WHEN tc.is_primary_key = 'PK' THEN 0 ELSE 1 END,
    tc.column_name;