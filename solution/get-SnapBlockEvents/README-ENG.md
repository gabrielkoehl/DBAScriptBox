# SQL Server Block Event Reporter

A PowerShell-based tool for analyzing SQL Server blocking events and deadlocks using Extended Events.

## Overview

**This solution enables:**
- Automatic capture of blocking events and deadlocks
- Detailed text reports for individual events
- Aggregated Excel reports with graphical analysis
- Flexible time period analysis
- Automatic report archiving

## Prerequisites

- Windows PowerShell 5.1 or higher
- SQL Server 2016 or higher
- PowerShell modules:
  - dbatools
  - ImportExcel

Installation of required modules:
```powershell
Install-Module dbatools
Install-Module ImportExcel
```

## Permissions

The user running the script needs the following permissions ([microsoft.com](https://learn.microsoft.com/en-us/sql/relational-databases/system-functions/sys-fn-xe-file-target-read-file-transact-sql?view=sql-server-ver16)):

- SQL 2019 and older: VIEW SERVER STATE
- SQL 2022 and newer: VIEW SERVER PERFORMANCE STATE
- Read access to the path containing the XEL files

## Installation

1. Clone the repository or extract all files into a directory
2. Use the "create_XE.sql" file to create the Extended Event session on the appropriate SQL Server (adjust parameters first!)

### Extended Events Session (create_XE.sql)

Main parameters of the XE session:

```sql
DECLARE @session_name NVARCHAR(128)     = N'blocked_process'
DECLARE @file_path NVARCHAR(260)        = N'D:\USERDATA\extendedEvents'
DECLARE @max_file_size INT              = 1024
DECLARE @max_rollover_files INT         = 1
DECLARE @startup_state BIT              = 0  -- 0 = OFF, 1 = ON
```

The SQL script outputs the following in the message blog:

```
Path for report generation
--------------------------
 
	D:\USERDATA\extendedEvents\blocked_process*.xel
	D:\USERDATA\extendedEvents\blocked_process*.xem
 
--------------------------
```

These are the paths needed for the PowerShell script. Either they can be set as defaults in the script parameters when monitoring only one instance, or they must be provided when calling the script.

## Usage

### Parameters

| Parameter | Type | Mandatory | Default | Description |
|-----------|------|-----------|---------|-------------|
| `-eventFilePath` | String | Yes | - | Path to the XE files (*.xel) |
| `-metaFilePath` | String | Yes | - | Path to the XE metadata (*.xem) |
| `-SqlInstance` | String | Yes | - | SQL Server instance name with configured Extended Events |
| `-reportRoot` | String | No | "$(Join-Path $(Split-Path -Parent $MyInvocation.MyCommand.Path) "_report")" | Path to the report directory |
| `-StartTime` | DateTime | No | (Get-Date).AddHours(-24) | Start time of analysis |
| `-EndTime` | DateTime | No | $(Get-Date) | End time of analysis |
| `-hoursBack` | Int | No | 2 | Alternative time span (Start: Now-hoursBack, End: Now) |
| `-ChartIntervalMinutes` | Int | No | 60 | Interval for Excel chart in minutes |
| `-returnSummary` | Switch | No | $false | Returns a table with the number of events per database |
| `-excel` | Switch | No | $false | Creates Excel summary |
| `-cleanUp` | Switch | No | $false | Cleans up report files older than cleanUpDays |
| `-cleanUpDays` | Int | No | 30 | Number of days for cleanup |

### Basic Call

```powershell
.\Run-BlockEventReport.ps1 -eventFilePath 'D:\USERDATA\extendedEvents\blocked_process*.xel' -metaFilePath 'D:\USERDATA\extendedEvents\blocked_process*.xem' -SqlInstance 'DEV-NODE1\DEV22A'
```

### Examples

```powershell
# With ISO date format
.\Run-BlockEventReport.ps1 -SqlInstance 'DEV-NODE1\DEV22A' -StartTime "2025-04-25 08:00" -EndTime "2025-04-25 18:00" -eventFilePath 'D:\USERDATA\extendedEvents\blocked_process*.xel' -metaFilePath 'D:\USERDATA\extendedEvents\blocked_process*.xem'

# Date only (sets time to 00:00)
.\Run-BlockEventReport.ps1 -SqlInstance 'DEV-NODE1\DEV22A' -StartTime "2023-11-20" -EndTime "2023-11-21" -eventFilePath 'D:\USERDATA\extendedEvents\blocked_process*.xel' -metaFilePath 'D:\USERDATA\extendedEvents\blocked_process*.xem'

# With Excel creation and cleanup
.\Run-BlockEventReport.ps1 -SqlInstance 'DEV-NODE1\DEV22A' -hoursBack 24 -eventFilePath 'D:\USERDATA\extendedEvents\blocked_process*.xel' -metaFilePath 'D:\USERDATA\extendedEvents\blocked_process*.xem' -excel -cleanUp -cleanUpDays 14
```

## Report Structure

```
_report/
├── text_reports/
│   └── YYYY/
│       └── MM/
│           └── DD/
│               ├── 20231120_123456_dbname_blocked.txt
│               ├── 20231120_123456_dbname_blocked.xml
│               ├── 20231120_123456_dbname_deadlock.txt
│               └── 20231120_123456_dbname_deadlock.xml
└── excel_reports/
    └── BlockReport_20231120_123456.xlsx
```

### Text Reports
- Detailed analysis of individual block or deadlock events
- Contains SQL statements, process details, and resource information
- Timestamp in filename for easy reference

### Excel Report
- Overview chart of events per time interval
- "Overview" tab with aggregated data
- "BlockedDetails" and "DeadlockDetails" tabs with individual events

## Troubleshooting

1. **No events found**
   - Check if the Extended Event session is running
   - Verify file paths to the XEL/XEM files
   - Check the time period
   - Directly check the event file in SQL Server Management Studio

2. **Access problems**
   - The executing user needs:
     - Appropriate permissions on the SQL Server instance
     - Read permissions for the XEL/XEM files
     - Write permissions in the report directory

## Notes

- Text reports are archived in a date-structured hierarchy
- Excel reports contain a visual analysis of events
- Deadlocks and blocking events are evaluated separately
- When using the `-returnSummary` parameter, the output can be stored in a PowerShell variable

## License

GNU GPL - See LICENSE file