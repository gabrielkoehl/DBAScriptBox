/*
================================================================================
SCRIPT:  backup_list_all_backupsets.sql
AUTHOR:  Gabriel Köhl
WEBSITE: https://dbavonnebenan.de
GITHUB:  https://github.com/gabrielkoehl/DBAScriptBox

DESCRIPTION:
    Backup monitoring overview showing last Full and TLog backup per database.
    - Overdue detection with configurable thresholds (NULL = show all)
    - HADR role, recovery model, read-only and DB state at a glance
    - Copy-only awareness, device type and backup sizes
    - Sorted by most critical (overdue first)

PARAMETERS:
    @FullBackupThresholdHours  - Max age for FULL backups (NULL = no filter)
    @TLogBackupThresholdHours  - Max age for TLOG backups (NULL = no filter)
    @DeviceType                - Filter by device type (NULL = all)
    @DatabaseName              - Filter single database (NULL = all)

HISTORY:
    - 16.03.2026 - Initial release

DISCLAIMER:
    This script is provided "as is" without warranty of any kind.
    Use at your own risk. The author assumes no responsibility for
    any damages or issues that may arise from using this script.
================================================================================
*/

DECLARE @FullBackupThresholdHours  INT     = NULL;   -- Max age for FULL backups (NULL = show all, no overdue calc)
DECLARE @DiffBackupThresholdHours  INT     = NULL;   -- Max age for DIFF backups (NULL = skip diff check)
DECLARE @TLogBackupThresholdHours  DECIMAL = NULL;   -- Max age for TLOG backups (NULL = show all, no overdue calc)
DECLARE @DeviceType                INT     = NULL;   -- 2 = DISK, 7 = Virtual Device, 9 = URL (NULL = all)
DECLARE @DatabaseName              SYSNAME = NULL;   -- Filter single DB (NULL = all)

;WITH backup_full AS (

    SELECT
            bs.database_name
        ,bs.backup_finish_date
        ,bs.is_copy_only
        ,bs.backup_size
        ,bs.compressed_backup_size
        ,bm.device_type
        ,bm.physical_device_name
        ,ROW_NUMBER() OVER (
            PARTITION BY bs.database_name
            ORDER BY bs.backup_finish_date DESC
            ) AS rn
    FROM
        msdb.dbo.backupset AS bs
    INNER JOIN (
        SELECT
             MAX(device_type)          AS device_type
            ,MAX(physical_device_name) AS physical_device_name
            ,media_set_id
        FROM
            msdb.dbo.backupmediafamily
        GROUP BY
            media_set_id
    ) bm ON bs.media_set_id = bm.media_set_id
    WHERE
            bs.type = 'D'
        AND (@DeviceType    IS NULL OR bm.device_type    = @DeviceType)
        AND (@DatabaseName  IS NULL OR bs.database_name  = @DatabaseName)

    ),

backup_diff AS (

    SELECT
         bs.database_name
        ,bs.backup_finish_date
        ,bs.is_copy_only
        ,bs.backup_size
        ,bs.compressed_backup_size
        ,bm.device_type
        ,bm.physical_device_name
        ,ROW_NUMBER() OVER (
            PARTITION BY bs.database_name
            ORDER BY bs.backup_finish_date DESC
            ) AS rn
    FROM
        msdb.dbo.backupset AS bs
    INNER JOIN (
        SELECT
                MAX(device_type)          AS device_type
            ,MAX(physical_device_name) AS physical_device_name
            ,media_set_id
        FROM
            msdb.dbo.backupmediafamily
        GROUP BY
            media_set_id
    ) bm ON bs.media_set_id = bm.media_set_id
    WHERE
            bs.type = 'I'
        AND (@DeviceType    IS NULL OR bm.device_type    = @DeviceType)
        AND (@DatabaseName  IS NULL OR bs.database_name  = @DatabaseName)

    ),

backup_tlog AS (

    SELECT
         bs.database_name
        ,bs.backup_finish_date
        ,bs.backup_size
        ,bs.compressed_backup_size
        ,bm.device_type
        ,bm.physical_device_name
        ,ROW_NUMBER() OVER (
            PARTITION BY bs.database_name
            ORDER BY bs.backup_finish_date DESC
            ) AS rn
    FROM
        msdb.dbo.backupset AS bs
    INNER JOIN (
        SELECT
                MAX(device_type)          AS device_type
            ,MAX(physical_device_name) AS physical_device_name
            ,media_set_id
        FROM
            msdb.dbo.backupmediafamily
        GROUP BY
            media_set_id
    ) bm ON bs.media_set_id = bm.media_set_id
    WHERE
            bs.type = 'L'
        AND (@DeviceType    IS NULL OR bm.device_type    = @DeviceType)
        AND (@DatabaseName  IS NULL OR bs.database_name  = @DatabaseName)

    ),

db_property AS (

    SELECT
         db.name
        ,CASE db.recovery_model
            WHEN 1 THEN 'FULL'
            WHEN 2 THEN 'BULK_LOGGED'
            WHEN 3 THEN 'SIMPLE'
            END                              AS recovery_model
        ,ISNULL(ha.role, 0)               AS role
        ,ISNULL(ha.role_desc, 'NONE')     AS role_desc
        ,db.state_desc                    AS db_state
        ,db.is_read_only
    FROM
        sys.databases db
    LEFT JOIN
        sys.dm_hadr_availability_replica_states ha ON db.replica_id = ha.replica_id
    WHERE
            db.name  != 'tempdb'
        AND db.state  = 0
        AND (@DatabaseName IS NULL OR db.name = @DatabaseName)

    )

-- Result

SELECT
     dbp.name                              AS database_name
    ,dbp.recovery_model
    ,dbp.role_desc                         AS ha_role
    ,dbp.db_state
    ,dbp.is_read_only

    -- Last FULL backup
    ,f.backup_finish_date                                                                   AS full_last_backup
    ,f.is_copy_only                                                                         AS full_is_copy_only
    ,CASE f.device_type
        WHEN 2 THEN 'DISK' WHEN 5 THEN 'TAPE' WHEN 7 THEN 'VIRTUAL' WHEN 9 THEN 'URL'
        ELSE CAST(f.device_type AS VARCHAR)
        END                                                                                 AS full_device
    ,CAST(ROUND(f.backup_size / 1048576.0, 1) AS DECIMAL(18,1))                             AS full_size_mb
    ,CAST(ROUND(f.compressed_backup_size / 1048576.0, 1) AS DECIMAL(18,1))                  AS full_compressed_mb
    ,CASE
        WHEN @FullBackupThresholdHours IS NULL THEN NULL
        WHEN f.backup_finish_date IS NULL THEN -1
        WHEN f.backup_finish_date < DATEADD(HOUR, -@FullBackupThresholdHours, GETDATE())
             THEN DATEDIFF(HOUR, f.backup_finish_date, GETDATE()) - @FullBackupThresholdHours
        ELSE 0
        END                                                                                 AS full_overdue_hours

    -- Last DIFF backup
    ,d.backup_finish_date                                                                   AS diff_last_backup
    ,d.is_copy_only                                                                         AS diff_is_copy_only
    ,CASE d.device_type
        WHEN 2 THEN 'DISK' WHEN 5 THEN 'TAPE' WHEN 7 THEN 'VIRTUAL' WHEN 9 THEN 'URL'
        ELSE CAST(d.device_type AS VARCHAR)
        END                                                                                 AS diff_device
    ,CAST(ROUND(d.backup_size / 1048576.0, 1) AS DECIMAL(18,1))                             AS diff_size_mb
    ,CAST(ROUND(d.compressed_backup_size / 1048576.0, 1) AS DECIMAL(18,1))                  AS diff_compressed_mb
    ,CASE
        WHEN @DiffBackupThresholdHours IS NULL THEN NULL
        WHEN d.backup_finish_date IS NULL THEN -1
        WHEN d.backup_finish_date < DATEADD(HOUR, -@DiffBackupThresholdHours, GETDATE())
             THEN DATEDIFF(HOUR, d.backup_finish_date, GETDATE()) - @DiffBackupThresholdHours
        ELSE 0
        END                                                                                 AS diff_overdue_hours

    -- Last TLOG backup
    ,l.backup_finish_date                                                                   AS tlog_last_backup
    ,CASE l.device_type
        WHEN 2 THEN 'DISK' WHEN 5 THEN 'TAPE' WHEN 7 THEN 'VIRTUAL' WHEN 9 THEN 'URL'
        ELSE CAST(l.device_type AS VARCHAR)
        END                                                                                 AS tlog_device
    ,CAST(ROUND(l.backup_size / 1048576.0, 1) AS DECIMAL(18,1))                             AS tlog_size_mb
    ,CAST(ROUND(l.compressed_backup_size / 1048576.0, 1) AS DECIMAL(18,1))                  AS tlog_compressed_mb
    ,CASE
        WHEN dbp.recovery_model = 'SIMPLE' THEN NULL
        WHEN @TLogBackupThresholdHours IS NULL THEN NULL
        WHEN l.backup_finish_date IS NULL THEN -1
        WHEN l.backup_finish_date < DATEADD(MINUTE, -CAST(@TLogBackupThresholdHours * 60 AS INT), GETDATE())
             THEN DATEDIFF(HOUR, l.backup_finish_date, GETDATE()) - CAST(@TLogBackupThresholdHours AS INT)
        ELSE 0
        END                                                                                 AS tlog_overdue_hours

FROM
    db_property AS dbp
LEFT JOIN
    backup_full AS f ON dbp.name = f.database_name AND f.rn = 1
LEFT JOIN
    backup_diff AS d ON dbp.name = d.database_name AND d.rn = 1
LEFT JOIN
    backup_tlog AS l ON dbp.name = l.database_name AND l.rn = 1

ORDER BY
    ISNULL(f.backup_finish_date, '19000101'),
    dbp.name;