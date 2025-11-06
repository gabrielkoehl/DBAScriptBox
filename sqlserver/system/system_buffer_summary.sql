/*
================================================================================
SCRIPT:  system_buffer_summary.sql
AUTHOR:  Gabriel Köhl
WEBSITE: https://dbavonnebenan.de
GITHUB:  https://github.com/gabrielkoehl/DBAScriptBox

DESCRIPTION:
    Memory analysis for SQL Server instances showing:
    - Physical RAM and SQL Server memory allocation
    - Buffer Pool metrics (Target, Database Pages, PLE)
    - Buffer Cache Hit Ratio
    - OS Available Commit Limit
    - Min/Max Server Memory configuration
    - Top 5 Memory Clerks by allocated memory
    
    Helps identify memory pressure, configuration issues, and memory distribution
    across different SQL Server components.

HISTORY:
    - 06.02.2023 - Initial release

USAGE:
    Execute directly in SSMS or Azure Data Studio
    Works on SQL Server 2012+ (all editions)
    No parameters required
    
DISCLAIMER:
    This script is provided "as is" without warranty of any kind.
    Use at your own risk. The author assumes no responsibility for
    any damages or issues that may arise from using this script.
================================================================================
*/

SELECT
    [Total_Physical_RAM_MB] = osm.total_physical_memory_kb / 1024,
    -- SQL Server memory metrics
    [SQL_Server_Allocated_RAM_MB] = opm.physical_memory_in_use_kb / 1024,
    -- Buffer Pool metrics
    [Buffer_Pool_Target_MB] = pc_target.cntr_value,
    -- Database pages usage
    [Used_By_Database_Pages_MB] = pc_db.cntr_value / 128,
    -- OS memory metrics
    [OS_Available_Commit_Limit_MB] = opm.available_commit_limit_kb / 1024,
    -- Performance indicators
    [PLE_Value] = pc_ple.cntr_value,
    [Buffer_Cache_Hit_Ratio] = CAST((pc_hit.cntr_value * 1.0 /
                               NULLIF(pc_base.cntr_value, 0)) * 100.0 AS DECIMAL(10,2)),
    -- Configuration values
    [Min_Server_Memory_MB] = c_min.value_in_use,
    [Max_Server_Memory_MB] = c_max.value_in_use
FROM
    sys.dm_os_sys_memory osm
CROSS JOIN
    sys.dm_os_process_memory opm
CROSS JOIN
    (SELECT committed_target_kb / 1024 AS cntr_value 
     FROM sys.dm_os_sys_info) pc_target
CROSS JOIN
    (SELECT cntr_value FROM sys.dm_os_performance_counters
     WHERE counter_name = 'Database pages'
     AND object_name LIKE '%Buffer Manager%') pc_db
CROSS JOIN
    (SELECT cntr_value FROM sys.dm_os_performance_counters
     WHERE counter_name = 'Page life expectancy'
     AND object_name LIKE '%Buffer Manager%') pc_ple
CROSS JOIN
    (SELECT cntr_value FROM sys.dm_os_performance_counters
     WHERE counter_name = 'Buffer cache hit ratio'
     AND object_name LIKE '%Buffer Manager%') pc_hit
CROSS JOIN
    (SELECT cntr_value FROM sys.dm_os_performance_counters
     WHERE counter_name = 'Buffer cache hit ratio base'
     AND object_name LIKE '%Buffer Manager%') pc_base
CROSS JOIN
    (SELECT value_in_use FROM sys.configurations
     WHERE name = 'min server memory (MB)') c_min
CROSS JOIN
    (SELECT value_in_use FROM sys.configurations
     WHERE name = 'max server memory (MB)') c_max;

--------

SELECT TOP(5) [type] AS [ClerkType],
SUM(pages_kb) / 1024 AS [SizeMb]
FROM sys.dm_os_memory_clerks WITH (NOLOCK)
GROUP BY [type]
ORDER BY SUM(pages_kb) DESC