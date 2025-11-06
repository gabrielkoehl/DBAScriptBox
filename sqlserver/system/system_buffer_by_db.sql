/*
================================================================================
SCRIPT:  system_buffer_by_db.sql
AUTHOR:  Gabriel Köhl
WEBSITE: https://dbavonnebenan.de
GITHUB:  https://github.com/gabrielkoehl/DBAScriptBox

DESCRIPTION:
    Buffer Cache analysis showing:
    - Overall Buffer Cache Hit Ratio and Page Life Expectancy
    - Per-database buffer cache usage and distribution
    - Dirty pages (modified but not yet written to disk)
    - Cache percentage per database
    - Health status indicators for cache performance
    
    Helps identify:
    - Memory pressure situations (low PLE)
    - Inefficient cache usage (low hit ratio)
    - Databases consuming most buffer pool memory
    - Excessive dirty pages indicating I/O bottlenecks

HISTORY:
    - 06.02.2023 - Initial release
    
DISCLAIMER:
    This script is provided "as is" without warranty of any kind.
    Use at your own risk. The author assumes no responsibility for
    any damages or issues that may arise from using this script.
================================================================================
*/

WITH PageLifeExpectancy AS (
    SELECT
        CAST(cntr_value AS DECIMAL(10,2)) as PageLifeExpectancy
    FROM sys.dm_os_performance_counters
    WHERE counter_name = 'Page life expectancy'
        AND object_name LIKE '%Buffer Manager%'
),
BufferCacheHitRatio AS (
    SELECT
        CAST((a.cntr_value * 1.0 / NULLIF(b.cntr_value, 0)) * 100.0 AS DECIMAL(5,2)) as BufferCacheHitRatio
    FROM sys.dm_os_performance_counters a
    JOIN sys.dm_os_performance_counters b
        ON b.object_name = a.object_name
    WHERE a.counter_name = 'Buffer cache hit ratio'
        AND b.counter_name = 'Buffer cache hit ratio base'
),
DB_Buffer_Stats AS (
    SELECT
        DB_NAME(database_id) as DatabaseName,
        CAST(COUNT(*) * 8.0/1024 AS DECIMAL(10,2)) as CachedSizeMB,
        CAST(SUM(CASE WHEN is_modified = 1 THEN 1 ELSE 0 END) * 8.0/1024 AS DECIMAL(10,2)) as DirtyCacheMB,
        CAST(COUNT(*) * 100.0 / NULLIF((SELECT COUNT(*) FROM sys.dm_os_buffer_descriptors), 0) AS DECIMAL(5,2)) as CachePercentage
    FROM sys.dm_os_buffer_descriptors
    GROUP BY database_id
)
SELECT
    '--- General Statistics ---' as Category,
    NULL as DatabaseName,
    NULL as CachedSizeMB,
    NULL as DirtyCacheMB,
    NULL as CachePercentage,
    BufferCacheHitRatio as OverallBufferCacheHitRatio,
    ple.PageLifeExpectancy as PageLifeExpectancySec,
    CASE
        WHEN BufferCacheHitRatio < 90.0 THEN 'Low Hit Ratio'
        WHEN ple.PageLifeExpectancy < 300.0 THEN 'Low Page Life Expectancy'
        ELSE 'OK'
    END as CacheStatus,
    CURRENT_TIMESTAMP				as [report_date]
FROM BufferCacheHitRatio
CROSS JOIN PageLifeExpectancy ple

UNION ALL

SELECT
    '--- Database Specific ---' as Category,
    bs.DatabaseName,
    bs.CachedSizeMB,
    bs.DirtyCacheMB,
    bs.CachePercentage,
    NULL as OverallBufferCacheHitRatio,
    NULL as PageLifeExpectancySec,
    CASE
        WHEN bs.DirtyCacheMB > bs.CachedSizeMB * 0.2 THEN 'High Dirty Pages'
        ELSE 'OK'
    END as CacheStatus,
    CURRENT_TIMESTAMP				as [report_date]
FROM DB_Buffer_Stats bs
ORDER BY
    Category DESC,
    CachedSizeMB DESC;
