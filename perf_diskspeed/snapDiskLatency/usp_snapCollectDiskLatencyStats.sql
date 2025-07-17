/*
   File Name      : usp_snapCollectDiskLatencyStats.sql
   Author         : Gabriel Köhl
   Site           : https://dbavonnebenan.de
   Repository     : https://github.com/gabrielkoehl/DBAScriptBox
   Date           : July 2025

   Summary        : This stored procedure collects disk I/O latency statistics from SQL Server

   Description    : This stored procedure collects disk I/O latency statistics from SQL Server and stores them in a permanent table for analysis. 
                    It is designed to be run as part of an Agent Job, allowing for regular monitoring of disk performance.

                    For meaningful latency statistics, the procedure should be executed at intervals of at least 1 hour.
                    Shorter intervals may result in unreliable delta calculations due to insufficient I/O activity
                    between snapshots, leading to statistically insignificant values.

                    Use usp_snapReportDiskLatencyStats.sql to analyze the collected data and generate reports.

   Parameters     : @ArchiveDatabase (NVARCHAR(128), required)
                    - Database name where the latency data table will be created and data will be stored
                    
                    @SchemaName    (NVARCHAR(128), default: 'dbo')
                    - Schema name where the latency data table will be created
                    
                    @TableName     (NVARCHAR(128), default: 'reportDiskLatency')
                    - Table name for storing the collected disk I/O latency statistics
                      Table will be created automatically if it doesn't exist

   Usage          : EXEC usp_snapCollectDiskLatencyStats @ArchiveDatabase = 'SqlDba';
                    EXEC usp_snapCollectDiskLatencyStats @ArchiveDatabase = 'SqlDba', @TableName  = 'reportDiskLatency'
                    EXEC usp_snapCollectDiskLatencyStats @ArchiveDatabase = 'SqlDba', @SchemaName = 'monitoring', @TableName = 'disk_latency_stats';

   Compatibility  : SQL Server 2019 and later

   This script is provided "as is" without warranty of any kind.
   You are free to use, modify, and distribute this script as you wish.
   No liability is assumed for any damages resulting from its use.
*/

CREATE OR ALTER PROCEDURE usp_snapCollectDiskLatencyStats
    @ArchiveDatabase NVARCHAR(128),
    @SchemaName      NVARCHAR(128) = N'dbo',
    @TableName       NVARCHAR(128) = N'reportDiskLatency'
AS
BEGIN
    SET NOCOUNT ON;

    -- Check if database exists
    IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = @ArchiveDatabase)
    BEGIN
        DECLARE @ErrorMsg NVARCHAR(200) = N'Database ''' + @ArchiveDatabase + N''' does not exist.';
        THROW 50001, @ErrorMsg, 1;
        RETURN;
    END;

    -- Create table if not exists
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullTableName NVARCHAR(400)    = QUOTENAME(@ArchiveDatabase) + '.' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    DECLARE @TableExists BIT                = 0;

    SET @SQL = N'
    USE ' + QUOTENAME(@ArchiveDatabase) + ';
    IF EXISTS (
        SELECT
            * 
        FROM
            sys.tables t
        INNER JOIN 
            sys.schemas s ON t.schema_id = s.schema_id
        WHERE 
                t.name = ''' + @TableName + ''' 
            AND s.name = ''' + @SchemaName + '''
    )
        SELECT @TableExists = 1
    ELSE
        SELECT @TableExists = 0';

    EXEC sp_executesql @SQL, N'@TableExists BIT OUTPUT', @TableExists OUTPUT;

    IF @TableExists = 0
    BEGIN
        SET @SQL = N'
        USE ' + QUOTENAME(@ArchiveDatabase) + ';
        CREATE TABLE ' + @FullTableName + ' (
            [snapshot_time] DATETIME2(3) NOT NULL,
            [database_id] INT NOT NULL,
            [database_name] NVARCHAR(128) NOT NULL,
            [file_id] INT NOT NULL,
            [drive] NCHAR(2) NOT NULL,
            [file_type] NVARCHAR(60) NOT NULL,
            [physical_name] NVARCHAR(260) NOT NULL,
            [num_of_reads] BIGINT NOT NULL,
            [num_of_writes] BIGINT NOT NULL,
            [io_stall_read_ms] BIGINT NOT NULL,
            [io_stall_write_ms] BIGINT NOT NULL,
            [io_stall_total_ms] BIGINT NOT NULL,
            [num_of_bytes_read] BIGINT NOT NULL,
            [num_of_bytes_written] BIGINT NOT NULL,
            [file_handle] VARBINARY(8) NOT NULL,
            CONSTRAINT [PK_' + @TableName + '] PRIMARY KEY CLUSTERED 
            ([snapshot_time], [database_id], [file_id])
        );';
        
        EXEC sp_executesql @SQL;
        
        -- Create index for efficient querying
        SET @SQL = N'
        USE ' + QUOTENAME(@ArchiveDatabase) + ';
        CREATE NONCLUSTERED INDEX [IX_' + @TableName + '_Database_Type_Time] 
        ON ' + @FullTableName + ' ([database_name], [file_type], [snapshot_time]);';
        
        EXEC sp_executesql @SQL;

        PRINT 'Table ' + @FullTableName + ' created successfully.';
    END;

    -- Insert current snapshot
    SET @SQL = N'
    USE ' + QUOTENAME(@ArchiveDatabase) + ';
    INSERT INTO ' + @FullTableName + ' (
        [snapshot_time],
        [database_id],
        [database_name],
        [file_id],
        [drive],
        [file_type],
        [physical_name],
        [num_of_reads],
        [num_of_writes],
        [io_stall_read_ms],
        [io_stall_write_ms],
        [io_stall_total_ms],
        [num_of_bytes_read],
        [num_of_bytes_written],
        [file_handle]
    )
    SELECT 
        GETDATE() AS [snapshot_time],
        [vfs].[database_id],
        DB_NAME([vfs].[database_id])    AS [database_name],
        [vfs].[file_id],
        LEFT([mf].[physical_name], 2)   AS [drive],
        [mf].[type_desc]                AS [file_type],
        [mf].[physical_name],
        [vfs].[num_of_reads],
        [vfs].[num_of_writes],
        [vfs].[io_stall_read_ms],
        [vfs].[io_stall_write_ms],
        [vfs].[io_stall]                AS [io_stall_total_ms],
        [vfs].[num_of_bytes_read],
        [vfs].[num_of_bytes_written],
        [vfs].[file_handle]
    FROM
        sys.dm_io_virtual_file_stats(NULL, NULL) AS [vfs]
    INNER JOIN 
        sys.master_files AS [mf] ON [vfs].[database_id] = [mf].[database_id]
                                AND [vfs].[file_id]     = [mf].[file_id]
    WHERE
            ([vfs].[database_id] = 2 or [vfs].[database_id] > 4)
        AND DB_NAME([vfs].[database_id]) IS NOT NULL;';

    EXEC sp_executesql @SQL;

    -- Show inserted records count
    SET @SQL = N'
    USE ' + QUOTENAME(@ArchiveDatabase) + ';
    SELECT 
        FORMAT(COUNT(*), ''N0'') AS [Records_Inserted],
        FORMAT(MAX([snapshot_time]), ''yyyy-MM-dd HH:mm:ss'') AS [Latest_Snapshot]
    FROM
        ' + @FullTableName + ' 
    WHERE
        [snapshot_time] >= DATEADD(SECOND, -1, GETDATE());';

    EXEC sp_executesql @SQL;

END;
GO