/*
   File Name      : IO_DATABASE_FILES.sql
   Author         : Gabriel Köhl
   Site           : https://dbavonnebenan.de
   Date           : July 2025

   Summary        : SQL Server IO Performance Analysis

   Description    : This script analyzes the IO performance of SQL Server database files.
                    It retrieves statistics on read and write operations, average IO sizes,

   Usage          : RUN

   This script is provided "as is" without warranty of any kind.
   You are free to use, modify, and distribute this script as you wish.
   No liability is assumed for any damages resulting from its use.
*/


WITH IO_Analysis AS (
    SELECT
        DB_NAME(vfs.database_id)    as DatabaseName,
        mf.name                     as LogicalFileName,
        mf.physical_name            as PhysicalFileName,
        mf.type_desc                as FileType,
        -- IO Statistics (GB)
        CAST(CAST(vfs.num_of_bytes_read AS DECIMAL(38,0)) / 1073741824.0 as DECIMAL(12,0))
                                    as ReadIO_GB,
		CAST(CASE
             WHEN vfs.num_of_reads + vfs.num_of_writes > 0
             THEN vfs.num_of_reads * 100.0 / NULLIF(vfs.num_of_reads + vfs.num_of_writes, 0)
             ELSE 0
             END as DECIMAL(5,0))
                                    as ReadPercentage,
        CAST(CAST(vfs.num_of_bytes_written AS DECIMAL(38,0)) / 1073741824.0 as DECIMAL(12,0))
                                    as WriteIO_GB,
        CAST(CASE
             WHEN vfs.num_of_reads + vfs.num_of_writes > 0
             THEN vfs.num_of_writes * 100.0 / NULLIF(vfs.num_of_reads + vfs.num_of_writes, 0)
             ELSE 0
             END as DECIMAL(5,0))
                                    as WritePercentage,
        vfs.num_of_reads            as ReadCount,
        vfs.num_of_writes           as WriteCount,
        -- Average IO Sizes (KB)
        CAST(CASE
             WHEN vfs.num_of_reads = 0 THEN 0
             ELSE CAST(vfs.num_of_bytes_read AS DECIMAL(38,2)) / NULLIF(vfs.num_of_reads, 0) / 1024.0
             END as DECIMAL(12,2))
                                    as AvgReadSize_KB,
        CAST(CASE
             WHEN vfs.num_of_writes = 0 THEN 0
             ELSE CAST(vfs.num_of_bytes_written AS DECIMAL(38,2)) / NULLIF(vfs.num_of_writes, 0) / 1024.0
             END as DECIMAL(12,2))
                                    as AvgWriteSize_KB,
        -- Latency Statistics (milliseconds)
        CAST(CAST(vfs.io_stall_read_ms AS DECIMAL(38,2)) / NULLIF(vfs.num_of_reads, 0) as DECIMAL(10,2))
                                    as AvgReadLatency_ms,
        CAST(CAST(vfs.io_stall_write_ms AS DECIMAL(38,2)) / NULLIF(vfs.num_of_writes, 0) as DECIMAL(10,2))
                                    as AvgWriteLatency_ms,
        CAST(CAST(vfs.io_stall AS DECIMAL(38,2)) / NULLIF(vfs.num_of_reads + vfs.num_of_writes, 0) as DECIMAL(10,2))
                                    as AvgIOLatency_ms,
        -- Total IO Stalls (milliseconds)
        vfs.io_stall_read_ms        as TotalReadStall_ms,
        vfs.io_stall_write_ms       as TotalWriteStall_ms,
        vfs.io_stall                as TotalIOStall_ms
    FROM
        sys.dm_io_virtual_file_stats(NULL, NULL) vfs
    JOIN
        sys.master_files mf ON vfs.database_id = mf.database_id  AND vfs.file_id = mf.file_id
)

SELECT
    DatabaseName,
    LogicalFileName,
    PhysicalFileName,
    FileType,
    ReadIO_GB,
    ReadPercentage,
    WriteIO_GB,
    WritePercentage,
    ReadCount,
    WriteCount,
    AvgReadSize_KB,
    AvgWriteSize_KB,
    AvgReadLatency_ms,
    AvgWriteLatency_ms,
    AvgIOLatency_ms,
    TotalReadStall_ms,
    TotalWriteStall_ms,
    TotalIOStall_ms,
    -- IOPS Analysis (operations per second)
    CAST(CAST(ReadCount + WriteCount AS DECIMAL(38,2)) /
         NULLIF(DATEDIFF(SECOND, (SELECT sqlserver_start_time FROM sys.dm_os_sys_info), GETDATE()), 0)
         as DECIMAL(10,2))
                            as Avg_IOPS,
    CAST(CAST(ReadCount + WriteCount AS DECIMAL(38,2)) * 3.0 /
         NULLIF(DATEDIFF(SECOND, (SELECT sqlserver_start_time FROM sys.dm_os_sys_info), GETDATE()), 0)
         as DECIMAL(10,2))
                            as Estimated_Peak_IOPS,
    -- Performance Status
    CASE
        WHEN FileType = 'ROWS' AND AvgReadLatency_ms    > 20 THEN 'High Read Latency'
        WHEN FileType = 'ROWS' AND AvgWriteLatency_ms   > 10 THEN 'High Write Latency'
        WHEN FileType = 'LOG' AND AvgWriteLatency_ms    > 5  THEN 'High Log Write Latency'
        ELSE 'OK'
    END as PerformanceStatus,
    CURRENT_TIMESTAMP
                            as [report_date]
FROM
    IO_Analysis
WHERE
    ReadCount + WriteCount > 0
