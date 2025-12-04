WITH events_cte AS (
  SELECT
    xevents.event_data,
    DATEADD(mi, DATEDIFF(mi, GETUTCDATE(), CURRENT_TIMESTAMP),
    xevents.event_data.value(
      '(event/@timestamp)[1]', 'datetime2')) AS [event_time],
    xevents.event_data.value(
      '(event/action[@name="client_app_name"]/value)[1]', 'nvarchar(128)')
      AS [client_app_name],
    xevents.event_data.value(
      '(event/action[@name="client_hostname"]/value)[1]', 'nvarchar(max)')
      AS [client_hostname],
    xevents.event_data.value(
      '(event[@name="blocked_process_report"]/data[@name="database_name"]/value)[1]', 'nvarchar(max)')
      AS [database_name],
    xevents.event_data.value(
      '(event[@name="blocked_process_report"]/data[@name="database_id"]/value)[1]', 'int')
      AS [database_id],
    xevents.event_data.value(
      '(event[@name="blocked_process_report"]/data[@name="object_id"]/value)[1]', 'int')
      AS [object_id],
    xevents.event_data.value(
      '(event[@name="blocked_process_report"]/data[@name="index_id"]/value)[1]', 'int')
      AS [index_id],
    xevents.event_data.value(
      '(event[@name="blocked_process_report"]/data[@name="duration"]/value)[1]', 'bigint') / 1000
      AS [duration_ms],
    xevents.event_data.value(
      '(event[@name="blocked_process_report"]/data[@name="lock_mode"]/text)[1]', 'varchar')
      AS [lock_mode],
    xevents.event_data.value(
      '(event[@name="blocked_process_report"]/data[@name="login_sid"]/value)[1]', 'int')
      AS [login_sid],
    xevents.event_data.query(
      '(event[@name="blocked_process_report"]/data[@name="blocked_process"]/value/blocked-process-report)[1]')
      AS blocked_process_report,
    xevents.event_data.query(
      '(event/data[@name="xml_report"]/value/deadlock)[1]')
      AS deadlock_graph
  FROM sys.fn_xe_file_target_read_file
    ('##XEL_PATH##',
     '##XEM_PATH##',
     null, null)
    CROSS APPLY (SELECT CAST(event_data AS XML) AS event_data) as xevents
  WHERE DATEADD(mi, DATEDIFF(mi, GETUTCDATE(), CURRENT_TIMESTAMP),
        xevents.event_data.value('(event/@timestamp)[1]', 'datetime2'))
        BETWEEN '##START_TIME##' AND ISNULL('##END_TIME##', CURRENT_TIMESTAMP)
)
SELECT
  CASE WHEN blocked_process_report.value('(blocked-process-report[@monitorLoop])[1]', 'nvarchar(max)') IS NULL
       THEN 'deadlock'
       ELSE 'blocked'
       END AS report_type,
  event_time,
  CASE client_app_name WHEN '' THEN '-- N/A --'
                       ELSE client_app_name
                       END AS client_app_name,
  CASE client_hostname WHEN '' THEN '-- N/A --'
                      ELSE client_hostname
                      END AS client_hostname,
  database_name,
  COALESCE(OBJECT_SCHEMA_NAME(object_id, database_id), '-- N/A --') AS schema_name,
  COALESCE(OBJECT_NAME(object_id, database_id), '-- N/A --') AS table_name,
  index_id,
  duration_ms,
  lock_mode,
  COALESCE(SUSER_NAME(login_sid), '-- N/A --') AS username,
  CASE WHEN blocked_process_report.value('(blocked-process-report[@monitorLoop])[1]', 'nvarchar(max)') IS NULL
       THEN deadlock_graph
       ELSE blocked_process_report
       END AS report_xml
FROM events_cte
ORDER BY event_time DESC;