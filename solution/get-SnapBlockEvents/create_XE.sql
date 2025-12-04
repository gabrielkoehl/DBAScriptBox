-- CUSTOM PARAM
---------------------------------------------------------------------------------

	DECLARE @session_name NVARCHAR(128)			= N'blocked_process'
	DECLARE @file_path NVARCHAR(260)			= N'<<PATH TO EVENT FOLDER>>' -- e.g. N'C:\Temp\SQL\XE'
	DECLARE @file_name NVARCHAR(260)			= @session_name + '.xel'
	DECLARE @metadata_file_path NVARCHAR(260)	= @file_path
	DECLARE @metadata_file_name NVARCHAR(260)	= @session_name + '.xem'
	DECLARE @max_file_size INT					= 10240
	DECLARE @max_rollover_files INT				= 1
	DECLARE @max_memory INT						= 4096
	DECLARE @max_dispatch_latency INT			= 5
	DECLARE @startup_state BIT					= 0 -- 0 = OFF, 1 = ON

---------------------------------------------------------------------------------


DECLARE @full_file_path NVARCHAR(520) = @file_path + N'\' + @file_name
DECLARE @full_metadata_file_path NVARCHAR(520) = @metadata_file_path + N'\' + @metadata_file_name
DECLARE @sql NVARCHAR(MAX)


IF EXISTS (SELECT * FROM sys.server_event_sessions WHERE name = @session_name)
BEGIN
    SET @sql = N'DROP EVENT SESSION [' + @session_name + N'] ON SERVER;'
    EXEC sp_executesql @sql
END


SET @sql = N'
CREATE EVENT SESSION [' + @session_name + N'] ON SERVER
ADD EVENT sqlserver.blocked_process_report(
    ACTION(sqlserver.client_app_name,
           sqlserver.client_hostname,
           sqlserver.database_name)
),
ADD EVENT sqlserver.xml_deadlock_report(
    ACTION(sqlserver.client_app_name,
           sqlserver.client_hostname,
           sqlserver.database_name)
)
ADD TARGET package0.event_file(
    SET filename        = N''' + @full_file_path + N''',
    max_file_size       = (' + CAST(@max_file_size AS NVARCHAR(10)) + N'),
    max_rollover_files  = (' + CAST(@max_rollover_files AS NVARCHAR(10)) + N'),
    metadatafile        = N''' + @full_metadata_file_path + N'''
)
WITH (
    MAX_MEMORY = ' + CAST(@max_memory AS NVARCHAR(10)) + N' KB,
    EVENT_RETENTION_MODE    = ALLOW_SINGLE_EVENT_LOSS,
    MAX_DISPATCH_LATENCY    = ' + CAST(@max_dispatch_latency AS NVARCHAR(10)) + N' SECONDS,
    MAX_EVENT_SIZE          = 0 KB,
    MEMORY_PARTITION_MODE   = NONE,
    TRACK_CAUSALITY         = OFF,
    STARTUP_STATE           = ' + CASE WHEN @startup_state = 1 THEN N'ON' ELSE N'OFF' END + N'
)'


EXEC sp_executesql @sql

SET @full_file_path			 = (select REPLACE(@full_file_path,'.xel','*.xel'))
SET @full_metadata_file_path = (select REPLACE(@full_metadata_file_path,'.xem','*.xem'))

PRINT 'Path for report generation'
PRINT '--------------------------'
PRINT ''
PRINT '	' + @full_file_path
PRINT '	' + @full_metadata_file_path
PRINT ''
PRINT '--------------------------'