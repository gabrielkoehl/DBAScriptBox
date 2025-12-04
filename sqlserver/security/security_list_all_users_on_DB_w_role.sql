/*
================================================================================
SCRIPT:  security_list_all_users_on_DB_w_role.sql
AUTHOR:  Gabriel Köhl
WEBSITE: https://dbavonnebenan.de
GITHUB:  https://github.com/gabrielkoehl/DBAScriptBox

DESCRIPTION:
    Analyzes all database users across all online databases on a SQL Server
    instance. Shows assigned database roles, object-level permissions, user
    types, and identifies orphaned users.
    Excludes system users (NT%, ##%, MS_%) and tempdb by default.
    Only includes PRIMARY databases in High Availability scenarios.

    Sql 2017+

HISTORY:
    - 06.05.2024 - Initial release
    - 04.12.2025 - Added HA primary check, error handling, STRING_AGG

DISCLAIMER:
    This script is provided "as is" without warranty of any kind.
    Use at your own risk. The author assumes no responsibility for
    any damages or issues that may arise from using this script.
================================================================================
*/

DECLARE @sql NVARCHAR(MAX) = '';

-- Temp tables
IF OBJECT_ID('tempdb..#UserPermissions') IS NOT NULL
    DROP TABLE #UserPermissions;

IF OBJECT_ID('tempdb..#ErrorLog') IS NOT NULL
    DROP TABLE #ErrorLog;

CREATE TABLE #UserPermissions (
    DatabaseName			NVARCHAR(128),
    UserName				NVARCHAR(128),
    UserType				NVARCHAR(128),
    DatabaseRoles			NVARCHAR(MAX),
    HasObjectPermissions	BIT,
    IsOrphaned				BIT
);

CREATE TABLE #ErrorLog (
    DatabaseName NVARCHAR(128),
    ErrorMessage NVARCHAR(MAX)
);

-- Build dynamic SQL only for primary or standalone databases
SELECT @sql = @sql + '
BEGIN TRY
    USE [' + name + '];
    INSERT INTO #UserPermissions (DatabaseName, UserName, UserType, DatabaseRoles, HasObjectPermissions, IsOrphaned)
    SELECT
        ''' + name + ''' AS DatabaseName,
        dp.name AS UserName,
        dp.type_desc AS UserType,
        (
            SELECT
				STRING_AGG(r.name, '', '')
            FROM
				sys.database_role_members drm
            INNER JOIN
				sys.database_principals r ON drm.role_principal_id = r.principal_id
            WHERE
				drm.member_principal_id = dp.principal_id
        ) AS DatabaseRoles,
        CASE
            WHEN EXISTS (
                SELECT
					1
                FROM
					sys.database_permissions dbp
                WHERE
						dbp.grantee_principal_id = dp.principal_id
					AND dbp.class > 0
            ) THEN 1
            ELSE 0
         END					AS HasObjectPermissions,
        CASE
            WHEN dp.type IN (''S'', ''U'')
                 AND dp.sid IS NOT NULL
                 AND dp.sid NOT IN (0x00, 0x01)
                 AND NOT EXISTS (
                     SELECT 1
                     FROM sys.server_principals sp
                     WHERE sp.sid = dp.sid
                 )
            THEN 1
            ELSE 0
         END					AS IsOrphaned
    FROM
        sys.database_principals dp
    WHERE
            dp.type IN (''S'', ''U'', ''G'', ''A'')
        AND dp.principal_id > 4
        AND dp.is_fixed_role = 0;
END TRY

BEGIN CATCH
    INSERT INTO #ErrorLog (DatabaseName, ErrorMessage)
    VALUES (''' + name + ''', ERROR_MESSAGE());
END CATCH;
'
FROM
    sys.databases d
WHERE
        d.state_desc = 'ONLINE'
    AND d.name NOT IN ('tempdb')
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
EXEC sp_executesql @sql;

-- Show results
SELECT
    DatabaseName,
    UserName,
    UserType,
    ISNULL(DatabaseRoles, 'No roles assigned') AS DatabaseRoles,
    CASE WHEN HasObjectPermissions = 1 THEN 'Yes' ELSE 'No' END AS HasObjectPermissions,
    CASE WHEN IsOrphaned = 1 THEN 'ORPHANED' ELSE 'OK' END AS OrphanedStatus
FROM
    #UserPermissions
WHERE
        UserName NOT LIKE 'NT%'
    AND UserName NOT LIKE '##%'
    AND UserName NOT LIKE 'MS_%'
ORDER BY
    DatabaseName,
    UserName;

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
		d.state_desc	= 'ONLINE'
    AND ars.is_local	= 1
    AND ars.role_desc	= 'SECONDARY';

-- Cleanup
DROP TABLE #UserPermissions;
DROP TABLE #ErrorLog;