# SQL Server Disk Latency Monitoring Scripts

## Overview

This package contains two stored procedures for monitoring and analyzing disk I/O latency statistics in SQL Server environments.

## Author

Gabriel Köhl  
Site: https://dbavonnebenan.de  
Repository: https://github.com/gabrielkoehl/DBAScriptBox

## Scripts

### usp_snapCollectDiskLatencyStats.sql

Collects disk I/O latency statistics from SQL Server and stores them in a permanent table for analysis. Designed to be run as part of an Agent Job for regular monitoring of disk performance.

**Key Features:**
- Collects data from sys.dm_io_virtual_file_stats
- Stores historical snapshots in a permanent table
- Automatically creates required table and indexes
- Excludes system databases (master, model, msdb)

**Recommended Usage:**
- Execute at intervals of at least 1 hour for meaningful statistics
- Shorter intervals may result in unreliable delta calculations
- Best suited for SQL Server Agent Job scheduling

### usp_snapReportDiskLatencyStats.sql

Analyzes disk I/O latency data and provides statistics for performance analysis. Supports both historical analysis from stored snapshots and current state analysis directly from DMVs.

**Key Features:**
- Historical analysis from stored data with delta calculations
- Current state analysis from sys.dm_io_virtual_file_stats
- Calculates average latencies per I/O operation
- Provides read/write operation counts and data transfer statistics
- File count aggregation by database and file type

**Analysis Modes:**
- Historical: Analyzes stored snapshots with configurable time ranges
- Current State: Direct analysis from DMVs without historical data

## Parameters

### usp_snapCollectDiskLatencyStats

- `@ArchiveDatabase` (NVARCHAR(128), required): Database for storing latency data
- `@SchemaName` (NVARCHAR(128), default: 'dbo'): Schema for the latency table
- `@TableName` (NVARCHAR(128), default: 'reportDiskLatency'): Table name for storing statistics

### usp_snapReportDiskLatencyStats

- `@ArchiveDatabase` (NVARCHAR(128), required for historical analysis): Database containing historical data
- `@SchemaName` (NVARCHAR(128), default: 'dbo'): Schema containing the latency table
- `@TableName` (NVARCHAR(128), default: 'reportDiskLatency'): Table containing historical data
- `@HoursBack` (INT, default: 24): Hours to look back for historical analysis
- `@DatabaseName` (NVARCHAR(128), default: NULL): Filter results for specific database (optional)
- `@FileType` (NVARCHAR(20), default: NULL): Filter results for specific file type ('DATA', 'LOG', or NULL for all)
- `@fromDM` (BIT, default: 0): Analysis mode (0 = historical, 1 = current state)

## Usage Examples

### Data Collection

```sql
-- Basic collection
EXEC usp_snapCollectDiskLatencyStats
    @ArchiveDatabase = 'SqlDba';

-- Custom schema and table
EXEC usp_snapCollectDiskLatencyStats 
    @ArchiveDatabase = 'SqlDba', 
    @SchemaName      = 'monitoring', 
    @TableName       = 'disk_latency_stats';
```

### Data Analysis

```sql
-- Historical analysis (last 24 hours)
EXEC usp_snapReportDiskLatencyStats
    @ArchiveDatabase = 'SqlDba';

-- Historical analysis (last 48 hours)
EXEC usp_snapReportDiskLatencyStats
    @ArchiveDatabase = 'SqlDba',
    @HoursBack       = 48;

-- Current state analysis
EXEC usp_snapReportDiskLatencyStats 
    @fromDM = 1;

-- Filter by specific database and file type
EXEC usp_snapReportDiskLatencyStats 
    @ArchiveDatabase = 'SqlDba', 
    @DatabaseName    = 'MyDatabase',
    @FileType        = 'DATA';

-- Filter by log files only
EXEC usp_snapReportDiskLatencyStats 
    @ArchiveDatabase = 'SqlDba', 
    @FileType        = 'LOG';

-- Custom table analysis with filters
EXEC usp_snapReportDiskLatencyStats 
    @ArchiveDatabase = 'SqlDba', 
    @SchemaName      = 'monitoring', 
    @TableName       = 'disk_latency_stats', 
    @DatabaseName    = 'MyDatabase',
    @HoursBack       = 12;
```

## Implementation Steps

1. Deploy both stored procedures to your SQL Server instance
2. Create a SQL Server Agent Job to execute `usp_snapCollectDiskLatencyStats` hourly (see example script below)
3. Use `usp_snapReportDiskLatencyStats` for analysis and reporting
4. Monitor results and adjust collection intervals as needed

## SQL Server Agent Job Example

The following script creates a SQL Server Agent Job that executes the collection procedure hourly:

```sql
-- Create SQL Server Agent Job for disk latency data collection
USE msdb;
GO

-- Create the job
EXEC dbo.sp_add_job
    @job_name               = N'adm_collectDiskLatency',
    @enabled                = 1,
    @description            = N'Collects disk I/O latency statistics hourly for performance monitoring',
    @start_step_id          = 1,
    @category_name          = N'[Uncategorized (Local)]',
    @owner_login_name       = N'sa';

-- Create the job step
EXEC dbo.sp_add_jobstep
    @job_name               = N'adm_collectDiskLatency',
    @step_name              = N'Collect Latency Stats',
    @step_id                = 1,
    @cmdexec_success_code   = 0,
    @on_success_action      = 1,
    @on_fail_action         = 2,
    @retry_attempts         = 0,
    @retry_interval         = 0,
    @os_run_priority        = 0,
    @subsystem              = N'TSQL',
    @command                = N'EXEC usp_snapCollectDiskLatencyStats @ArchiveDatabase = ''SqlDba'';',
    @database_name          = N'master',
    @flags                  = 0;

-- Create the schedule (runs every hour)
EXEC dbo.sp_add_schedule
    @schedule_name          = N'Hourly Collection',
    @enabled                = 1,
    @freq_type              = 4,
    @freq_interval          = 1,
    @freq_subday_type       = 8,
    @freq_subday_interval   = 1,
    @freq_relative_interval = 0,
    @freq_recurrence_factor = 0,
    @active_start_date      = 20250101,
    @active_end_date        = 99991231,
    @active_start_time      = 0,
    @active_end_time        = 235959;

-- Attach the schedule to the job
EXEC dbo.sp_attach_schedule
    @job_name               = N'adm_collectDiskLatency',
    @schedule_name          = N'Hourly Collection';

-- Add the job to the target server
EXEC dbo.sp_add_jobserver
    @job_name               = N'adm_collectDiskLatency',
    @server_name            = N'(local)';

-- Optional: Start the job immediately
-- EXEC dbo.sp_start_job @job_name = N'adm_collectDiskLatency';
```

**Note:** Adjust the `@ArchiveDatabase` parameter in the job step command to match your target database name.

## Output Columns

The report procedure returns the following columns:

- `DateTime`: Timestamp of the analysis
- `Period`: Time period description
- `Database`: Database name
- `FileType`: File type (Data File, Transaction Log)
- `AvgReadLatency_ms`: Average read latency per I/O operation
- `AvgWriteLatency_ms`: Average write latency per I/O operation
- `AvgTotalLatency_ms`: Average total latency per I/O operation
- `TotalReads`: Total read operations
- `TotalWrites`: Total write operations
- `TotalReadKB`: Total data read in KB
- `TotalWriteKB`: Total data written in KB
- `TotalReadPages`: Total pages read (8KB pages)
- `TotalWritePages`: Total pages written (8KB pages)
- `FileCount`: Number of files per database and file type

## Compatibility

SQL Server 2019 and later tested

## License

This script is provided "as is" without warranty of any kind. You are free to use, modify, and distribute this script as you wish. No liability is assumed for any damages resulting from its use.

Attribution is appreciated but not required.
