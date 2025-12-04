/*
================================================================================
SCRIPT:  security_list_orphaned_users_and_server_roles.sql
AUTHOR:  Gabriel Köhl
WEBSITE: https://dbavonnebenan.de
GITHUB:  https://github.com/gabrielkoehl/DBAScriptBox

DESCRIPTION:
    Lists orphaned database users and server role memberships across all databases.
    Only processes PRIMARY or standalone databases in HA scenarios.
    Includes error handling for inaccessible databases.

HISTORY:
    - 12.02.2024 - INIT
	- 12.02.2024 - Added HA primary check, error handling, removed cursors
================================================================================
*/

USE tempdb;
GO

-- Drop temp tables if exist
IF OBJECT_ID('tempdb..#OrphanedUsers')	IS NOT NULL DROP TABLE #OrphanedUsers;
IF OBJECT_ID('tempdb..#ServerRoles')	IS NOT NULL DROP TABLE #ServerRoles;
IF OBJECT_ID('tempdb..#ErrorLog')		IS NOT NULL DROP TABLE #ErrorLog;

-- Create temp tables
CREATE TABLE #OrphanedUsers (
    DatabaseName	NVARCHAR(255),
    UserName		NVARCHAR(255),
    UserType		NVARCHAR(60),
    UserSID			VARBINARY(85)
);

CREATE TABLE #ServerRoles (
    LoginName		NVARCHAR(255),
    sysadmin		NCHAR(1),
    serveradmin		NCHAR(1),
    securityadmin	NCHAR(1),
    processadmin	NCHAR(1),
    setupadmin		NCHAR(1),
    bulkadmin		NCHAR(1),
    diskadmin		NCHAR(1),
    dbcreator		NCHAR(1),
    create_date		DATETIME,
    modify_date		DATETIME
);

CREATE TABLE #ErrorLog (
    DatabaseName	NVARCHAR(255),
    ErrorMessage	NVARCHAR(MAX)
);

-- Collect orphaned users from all databases (only PRIMARY or standalone)
DECLARE @SQL NVARCHAR(MAX) = '';

SELECT @SQL = @SQL + '
BEGIN TRY
    USE [' + name + '];
    INSERT INTO tempdb.dbo.#OrphanedUsers (DatabaseName, UserName, UserType, UserSID)
    SELECT
        ''' + name + ''',
        dp.name,
        dp.type_desc,
        dp.sid
    FROM
		sys.database_principals dp
    LEFT JOIN
		sys.server_principals sp ON dp.sid = sp.sid
    WHERE
			dp.type IN (''S'', ''U'')
        AND dp.principal_id > 4
        AND sp.sid IS NULL;
END TRY

BEGIN CATCH
    INSERT INTO tempdb.dbo.#ErrorLog (DatabaseName, ErrorMessage)
    VALUES (''' + name + ''', ERROR_MESSAGE());
END CATCH;
'
FROM
	sys.databases d
WHERE
		d.state_desc = 'ONLINE'
    AND d.database_id > 4
    AND (
        -- Include if NOT in availability group
        NOT EXISTS (
            SELECT
				1
            FROM
				sys.dm_hadr_database_replica_states drs
            WHERE
				drs.database_id = d.database_id
        )
        OR
        -- Include if in availability group AND is primary
        EXISTS (
            SELECT
				1
            FROM
				sys.dm_hadr_database_replica_states drs
            INNER JOIN
				sys.dm_hadr_availability_replica_states ars ON drs.replica_id = ars.replica_id
            WHERE
					drs.database_id = d.database_id
                AND ars.is_local = 1
                AND ars.role_desc = 'PRIMARY'
        )
    );

-- Execute dynamic SQL
EXEC sp_executesql @SQL;

-- Collect server role memberships for all logins
INSERT INTO #ServerRoles (
    LoginName,
    sysadmin,
    serveradmin,
    securityadmin,
    processadmin,
    setupadmin,
    bulkadmin,
    diskadmin,
    dbcreator,
    create_date,
    modify_date
)
SELECT
    name,
    CASE WHEN IS_SRVROLEMEMBER('sysadmin',		name) = 1 THEN 'x' ELSE NULL END,
    CASE WHEN IS_SRVROLEMEMBER('serveradmin',	name) = 1 THEN 'x' ELSE NULL END,
    CASE WHEN IS_SRVROLEMEMBER('securityadmin', name) = 1 THEN 'x' ELSE NULL END,
    CASE WHEN IS_SRVROLEMEMBER('processadmin',	name) = 1 THEN 'x' ELSE NULL END,
    CASE WHEN IS_SRVROLEMEMBER('setupadmin',	name) = 1 THEN 'x' ELSE NULL END,
    CASE WHEN IS_SRVROLEMEMBER('bulkadmin',		name) = 1 THEN 'x' ELSE NULL END,
    CASE WHEN IS_SRVROLEMEMBER('diskadmin',		name) = 1 THEN 'x' ELSE NULL END,
    CASE WHEN IS_SRVROLEMEMBER('dbcreator',		name) = 1 THEN 'x' ELSE NULL END,
    create_date,
    modify_date
FROM
	sys.server_principals
WHERE
		type IN ('S', 'U', 'G')
    AND name NOT LIKE '##%'
    AND name NOT LIKE 'NT %';

-- Output orphaned users
SELECT
	*
FROM
	#OrphanedUsers
ORDER BY
	DatabaseName,
	UserName;

-- Output server role memberships
SELECT
	*
FROM
	#ServerRoles
ORDER BY
	LoginName;

-- Show errors if any occurred
IF EXISTS (SELECT 1 FROM #ErrorLog)
BEGIN
    PRINT '';
    PRINT 'Errors occurred during execution:';
    PRINT '==================================';
    SELECT DatabaseName, ErrorMessage FROM #ErrorLog;
END;

-- Show excluded secondary databases
SELECT
    d.name				AS ExcludedDatabase,
    'SECONDARY REPLICA' AS Reason
FROM
	sys.databases d
INNER JOIN
	sys.dm_hadr_database_replica_states drs ON drs.database_id = d.database_id
INNER JOIN
	sys.dm_hadr_availability_replica_states ars ON drs.replica_id = ars.replica_id
WHERE
		d.state_desc = 'ONLINE'
    AND ars.is_local = 1
    AND ars.role_desc = 'SECONDARY';

-- Cleanup
DROP TABLE #OrphanedUsers;
DROP TABLE #ServerRoles;
DROP TABLE #ErrorLog;