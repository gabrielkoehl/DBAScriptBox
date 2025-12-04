/*
   File Name      : usp_snapReportDiskLatencyStats.sql
   Author         : Gabriel Köhl
   Site           : https://dbavonnebenan.de
   Repository     : https://github.com/gabrielkoehl/DBAScriptBox
   Date           : July 2025

   Summary        : This stored procedure analyzes disk I/O latency data and provides I/O statistics

   Description    : This stored procedure analyzes disk I/O latency data collected by usp_snapCollectDiskLatencyStats.sql and generates
                    reports for disk performance analysis. It calculates latency differences between
                    snapshots and provides aggregated statistics including:
                    - Average read/write latencies per I/O operation
                    - Total read/write operations count
                    - Cumulative data transferred in KB (read/write)
                    - Cumulative pages transferred (read/write, based on 8KB page size)
                    - File count per database and file type
                    
                    The report supports both historical analysis from stored snapshots and current state analysis
                    directly from sys.dm_io_virtual_file_stats DMV.

                    Use usp_snapCollectDiskLatencyStats.sql to collect the data that this stored procedure analyzes.

   Parameters     : @ArchiveDatabase (NVARCHAR(128), required for @fromDM = 0, ignored for @fromDM = 1)
                    - Database name where the historical latency data table is stored
                    
                    @SchemaName    (NVARCHAR(128), default: 'dbo')
                    - Schema name where the historical latency data table is located
                    
                    @TableName     (NVARCHAR(128), default: 'reportDiskLatency')
                    - Table name containing the historical latency data collected by usp_snapCollectDiskLatencyStats.sql
                    
                    @HoursBack     (INT, default: 24)
                    - Number of hours to look back for historical analysis (only used when @fromDM = 0)
                    
                    @DatabaseName  (NVARCHAR(128), default: NULL)
                    - Filter results for specific database (optional, applies to both analysis modes)
                    
                    @FileType      (NVARCHAR(20), default: NULL)
                    - Filter results for specific file type: 'DATA', 'LOG', or NULL for all types
                    
                    @fromDM        (BIT, default: 0)
                    - Switch between analysis modes:
                      0 = Historical analysis from stored data (uses @ArchiveDatabase, @SchemaName, @TableName, @HoursBack)
                      1 = Current state analysis directly from sys.dm_io_virtual_file_stats (ignores archive parameters)

   Usage          : EXEC usp_snapReportDiskLatencyStats @ArchiveDatabase = 'SqlDba';
                    EXEC usp_snapReportDiskLatencyStats @ArchiveDatabase = 'SqlDba', @HoursBack = 48;
                    EXEC usp_snapReportDiskLatencyStats @fromDM = 1;
                    EXEC usp_snapReportDiskLatencyStats @ArchiveDatabase = 'SqlDba', @DatabaseName = 'MyDB', @FileType = 'DATA';
                    EXEC usp_snapReportDiskLatencyStats @ArchiveDatabase = 'SqlDba', @SchemaName = 'monitoring', @TableName = 'disk_latency_stats', @HoursBack = 12;

   Compatibility  : SQL Server 2019 and later

   This script is provided "as is" without warranty of any kind.
   You are free to use, modify, and distribute this script as you wish.
   No liability is assumed for any damages resulting from its use.
*/

CREATE OR ALTER PROCEDURE usp_snapReportDiskLatencyStats
    @ArchiveDatabase NVARCHAR(128) = NULL,
    @SchemaName      NVARCHAR(128) = N'dbo',
    @TableName       NVARCHAR(128) = N'reportDiskLatency',
    @HoursBack       INT = 24,
    @DatabaseName    NVARCHAR(128) = NULL,
    @FileType        NVARCHAR(20) = NULL,
    @fromDM          BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    -- Validate @FileType parameter
    IF @FileType IS NOT NULL
    BEGIN
        SET @FileType = UPPER(LTRIM(RTRIM(@FileType)));
        IF @FileType NOT IN ('DATA', 'LOG')
        BEGIN
            THROW 50003, N'@FileType parameter must be ''DATA'', ''LOG'', or NULL. Invalid value provided.', 1;
            RETURN;
        END;
    END;

    -- Check if archive database exists (only needed for historical analysis)
    IF @fromDM = 0
    BEGIN
        IF @ArchiveDatabase IS NULL
        BEGIN
            THROW 50002, N'@ArchiveDatabase parameter is required when @fromDM = 0 (historical analysis mode).', 1;
            RETURN;
        END;

        IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = @ArchiveDatabase)
        BEGIN
            DECLARE @ErrorMsg NVARCHAR(200) = N'Database ''' + @ArchiveDatabase + N''' does not exist.';
            THROW 50001, @ErrorMsg, 1;
            RETURN;
        END;
    END;

    -- Variables for analysis period
    DECLARE @StartDate DATETIME2            = DATEADD(HOUR, -@HoursBack, GETDATE());
    DECLARE @EndDate DATETIME2              = GETDATE();

    -- Build full table name (only needed for historical analysis)
    DECLARE @FullTableName NVARCHAR(400);
    IF @fromDM = 0
    BEGIN
        SET @FullTableName = QUOTENAME(@ArchiveDatabase) + '.' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    END;

    -- Build dynamic SQL for the analysis query
    DECLARE @SQL NVARCHAR(MAX);

    IF @fromDM = 1
    BEGIN
        -- Query directly from sys.dm_io_virtual_file_stats without time span
        SET @SQL = N'
        SELECT 
            FORMAT(GETDATE(), ''yyyy-MM-dd HH:mm'')                          AS [DateTime],
            DB_NAME([vfs].[database_id])                                     AS [Database],
            CASE 
                WHEN [mf].[type_desc] = ''LOG'' THEN ''Transaction Log''
                WHEN [mf].[type_desc] = ''ROWS'' THEN ''Data File''
                ELSE [mf].[type_desc]
             END                                                            AS [FileType],
            -- Calculate average latencies per I/O operation (rounded to whole numbers)
            CASE 
                WHEN [vfs].[num_of_reads] = 0 THEN 0
                ELSE CAST(ROUND([vfs].[io_stall_read_ms] * 1.0 / [vfs].[num_of_reads], 0) AS INT)
             END                                                            AS [AvgReadLatency_ms],
            CASE 
                WHEN [vfs].[num_of_writes] = 0 THEN 0
                ELSE CAST(ROUND([vfs].[io_stall_write_ms] * 1.0 / [vfs].[num_of_writes], 0) AS INT)
             END                                                            AS [AvgWriteLatency_ms],
            CASE 
                WHEN ([vfs].[num_of_reads] + [vfs].[num_of_writes]) = 0 THEN 0
                ELSE CAST(ROUND([vfs].[io_stall] * 1.0 / ([vfs].[num_of_reads] + [vfs].[num_of_writes]), 0) AS INT)
             END                                                            AS [AvgTotalLatency_ms],
            [vfs].[num_of_reads]                                            AS [TotalReads],
            [vfs].[num_of_writes]                                           AS [TotalWrites],
            -- Add cumulative bytes and pages
            CAST(ROUND([vfs].[num_of_bytes_read] / 1024.0, 0) AS BIGINT)    AS [TotalReadKB],
            CAST(ROUND([vfs].[num_of_bytes_written] / 1024.0, 0) AS BIGINT) AS [TotalWriteKB],
            CAST(ROUND([vfs].[num_of_bytes_read] / 8192.0, 0) AS BIGINT)    AS [TotalReadPages],
            CAST(ROUND([vfs].[num_of_bytes_written] / 8192.0, 0) AS BIGINT) AS [TotalWritePages],
            COUNT(*)                                                        AS [FileCount]
        FROM
            sys.dm_io_virtual_file_stats(NULL, NULL) AS [vfs]
        INNER JOIN 
            sys.master_files AS [mf] ON [vfs].[database_id] = [mf].[database_id]
                                    AND [vfs].[file_id]     = [mf].[file_id]
        WHERE
                ([vfs].[database_id] = 2 or [vfs].[database_id] > 4)
            AND DB_NAME([vfs].[database_id]) IS NOT NULL
            AND (@DatabaseName IS NULL OR DB_NAME([vfs].[database_id]) = @DatabaseName)
            AND (    @FileType IS NULL 
                 OR (@FileType = ''DATA'' AND [mf].[type_desc] = ''ROWS'') 
                 OR (@FileType = ''LOG'' AND [mf].[type_desc] = ''LOG''))
        GROUP BY 
            [vfs].[database_id],
            DB_NAME([vfs].[database_id]),
            CASE 
                WHEN [mf].[type_desc] = ''LOG''    THEN ''Transaction Log''
                WHEN [mf].[type_desc] = ''ROWS''   THEN ''Data File''
                ELSE [mf].[type_desc]
             END,
            [vfs].[num_of_reads],
            [vfs].[num_of_writes],
            [vfs].[io_stall_read_ms],
            [vfs].[io_stall_write_ms],
            [vfs].[io_stall],
            [vfs].[num_of_bytes_read],
            [vfs].[num_of_bytes_written]
        ORDER BY
            [Database],
            [FileType];';
        
        EXEC sp_executesql @SQL, N'@DatabaseName NVARCHAR(128), @FileType NVARCHAR(20)', @DatabaseName, @FileType;
    END

    ELSE

    BEGIN

        -- Original historical analysis from stored data
        SET @SQL = N'USE ' + QUOTENAME(@ArchiveDatabase) + ';' + CHAR(13) + CHAR(10);

        SET @SQL = @SQL + N'
        WITH [TimeSeries] AS (
            -- Generate complete time series from available snapshots
            SELECT DISTINCT [snapshot_time]
            FROM ' + @FullTableName + '
            WHERE [snapshot_time] BETWEEN @StartDate AND @EndDate
        ),

        [DatabaseFileTypes] AS (
            -- Get all unique database/filetype combinations that exist in the period
            SELECT DISTINCT 
                [database_name],
                CASE 
                    WHEN [file_type] = ''LOG''  THEN ''Transaction Log''
                    WHEN [file_type] = ''ROWS'' THEN ''Data File''
                    ELSE [file_type]
                END AS [FileType]
            FROM ' + @FullTableName + '
            WHERE [snapshot_time] BETWEEN @StartDate AND @EndDate
        ),

        [CompleteMatrix] AS (
            -- Cross join to ensure every time point has every database/filetype combination
            SELECT 
                ts.[snapshot_time],
                df.[database_name],
                df.[FileType]
            FROM [TimeSeries] ts
            CROSS JOIN [DatabaseFileTypes] df
        ),

        [SnapshotDiffs] AS (
            SELECT 
                [curr].[snapshot_time],
                [prev].[snapshot_time] AS [previous_snapshot_time],
                [curr].[database_name],
                [curr].[file_type],
                [curr].[drive],
                
                -- Calculate differences from previous snapshot (delta values)
                [curr].[num_of_reads]         - ISNULL([prev].[num_of_reads], 0)            AS [reads_diff],
                [curr].[num_of_writes]        - ISNULL([prev].[num_of_writes], 0)           AS [writes_diff],
                [curr].[io_stall_read_ms]     - ISNULL([prev].[io_stall_read_ms], 0)        AS [read_stall_diff],
                [curr].[io_stall_write_ms]    - ISNULL([prev].[io_stall_write_ms], 0)       AS [write_stall_diff],
                [curr].[io_stall_total_ms]    - ISNULL([prev].[io_stall_total_ms], 0)       AS [total_stall_diff],
                [curr].[num_of_bytes_read]    - ISNULL([prev].[num_of_bytes_read], 0)       AS [bytes_read_diff],
                [curr].[num_of_bytes_written] - ISNULL([prev].[num_of_bytes_written], 0)    AS [bytes_written_diff]
                
            FROM
                ' + @FullTableName + ' AS [curr]

            LEFT JOIN 
                ' + @FullTableName + ' AS [prev] ON [curr].[database_id]    = [prev].[database_id]
                                                            AND [curr].[file_id]        = [prev].[file_id]
                                                            AND [prev].[snapshot_time]  = (
                                                                        SELECT
                                                                            MAX([snapshot_time]) 
                                                                        FROM
                                                                            ' + @FullTableName + ' AS [p2]
                                                                        WHERE 
                                                                                [p2].[database_id] = [curr].[database_id]
                                                                            AND [p2].[file_id] = [curr].[file_id]
                                                                            AND [p2].[snapshot_time] < [curr].[snapshot_time]
                                                            )
            WHERE 
                    [curr].[snapshot_time] BETWEEN @StartDate AND @EndDate
                AND [prev].[snapshot_time] IS NOT NULL -- Only records with previous snapshot
        ),

        [AggregatedData] AS (
            -- Aggregate data from snapshot differences
            SELECT 
                [snapshot_time],
                [database_name],
                CASE 
                    WHEN [file_type] = ''LOG'' THEN ''Transaction Log''
                    WHEN [file_type] = ''ROWS'' THEN ''Data File''
                    ELSE [file_type]
                 END                        AS [FileType],';

        -- split because of 4000 character limit
        SET @SQL = @SQL + N'
                -- Calculate average latencies per I/O operation (rounded to whole numbers)
                CASE 
                    WHEN SUM([reads_diff]) = 0 THEN 0
                    ELSE CAST(ROUND(SUM([read_stall_diff]) * 1.0 / SUM([reads_diff]), 0) AS INT)
                 END                        AS [AvgReadLatency_ms],
                CASE 
                    WHEN SUM([writes_diff]) = 0 THEN 0
                    ELSE CAST(ROUND(SUM([write_stall_diff]) * 1.0 / SUM([writes_diff]), 0) AS INT)
                 END                        AS [AvgWriteLatency_ms],
                CASE 
                    WHEN (SUM([reads_diff]) + SUM([writes_diff])) = 0 THEN 0
                    ELSE CAST(ROUND(SUM([total_stall_diff]) * 1.0 / (SUM([reads_diff]) + SUM([writes_diff])), 0) AS INT)
                 END                        AS [AvgTotalLatency_ms],
                SUM([reads_diff])           AS [TotalReads],
                SUM([writes_diff])          AS [TotalWrites],
                -- Add cumulative bytes and pages for historical analysis
                CAST(ROUND(SUM([bytes_read_diff]) / 1024.0, 0) AS BIGINT) 
                                            AS [TotalReadKB],
                CAST(ROUND(SUM([bytes_written_diff]) / 1024.0, 0) AS BIGINT) 
                                            AS [TotalWriteKB],
                CAST(ROUND(SUM([bytes_read_diff]) / 8192.0, 0) AS BIGINT) 
                                            AS [TotalReadPages],
                CAST(ROUND(SUM([bytes_written_diff]) / 8192.0, 0) AS BIGINT) 
                                            AS [TotalWritePages],
                COUNT(*)                    AS [FileCount]
                
            FROM
                [SnapshotDiffs]

            WHERE 
                    [reads_diff]        >= 0
                AND [writes_diff]       >= 0
                AND [read_stall_diff]   >= 0
                AND [write_stall_diff]  >= 0

            GROUP BY 
                [snapshot_time],
                [database_name],
                CASE 
                    WHEN [file_type] = ''LOG'' THEN ''Transaction Log''
                    WHEN [file_type] = ''ROWS'' THEN ''Data File''
                    ELSE [file_type]
                END
        )

        SELECT 
            FORMAT(cm.[snapshot_time], ''yyyy-MM-dd HH:mm'')    AS [DateTime],
            cm.[database_name]                                  AS [Database],
            cm.[FileType],
            
            -- Use ISNULL to show 0 for missing data instead of NULL
            ISNULL(ad.[AvgReadLatency_ms], 0)                   AS [AvgReadLatency_ms],
            ISNULL(ad.[AvgWriteLatency_ms], 0)                  AS [AvgWriteLatency_ms],
            ISNULL(ad.[AvgTotalLatency_ms], 0)                  AS [AvgTotalLatency_ms],
            ISNULL(ad.[TotalReads], 0)                          AS [TotalReads],
            ISNULL(ad.[TotalWrites], 0)                         AS [TotalWrites],
            ISNULL(ad.[TotalReadKB], 0)                         AS [TotalReadKB],
            ISNULL(ad.[TotalWriteKB], 0)                        AS [TotalWriteKB],
            ISNULL(ad.[TotalReadPages], 0)                      AS [TotalReadPages],
            ISNULL(ad.[TotalWritePages], 0)                     AS [TotalWritePages],
            ISNULL(ad.[FileCount], 0)                           AS [FileCount]
            
        FROM
            [CompleteMatrix] cm

        LEFT JOIN 
            [AggregatedData] ad ON cm.[snapshot_time] = ad.[snapshot_time]
                               AND cm.[database_name] = ad.[database_name]
                               AND cm.[FileType]      = ad.[FileType]

        WHERE 
                (@DatabaseName IS NULL OR cm.[database_name] = @DatabaseName)
            AND (        @FileType IS NULL 
                    OR  (@FileType = ''DATA'' AND cm.[FileType] = ''Data File'')
                    OR  (@FileType = ''LOG'' AND cm.[FileType] = ''Transaction Log'')
                )

        ORDER BY
            cm.[snapshot_time],
            cm.[database_name],
            cm.[FileType];';

        EXEC sp_executesql @SQL, N'@StartDate DATETIME2, @EndDate DATETIME2, @DatabaseName NVARCHAR(128), @FileType NVARCHAR(20)', @StartDate, @EndDate, @DatabaseName, @FileType;
    END

END;
GO