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

HISTORY:
    - 06.05.2024 - Initial release

USAGE:
    Execute directly in SSMS or Azure Data Studio
    Analyzes all online databases on current SQL Server instance
    
TECHNICAL NOTE:
    Uses string concatenation over sys.databases resultset instead of CURSOR
    for dynamic SQL generation. SQL Server iterates internally row-by-row,
    concatenating each database's SQL block into @sql variable, then executes
    the complete string once via sp_executesql.    
    
DISCLAIMER:
    This script is provided "as is" without warranty of any kind.
    Use at your own risk. The author assumes no responsibility for
    any damages or issues that may arise from using this script.
================================================================================
*/

DECLARE @sql NVARCHAR(MAX) = '';

IF OBJECT_ID('tempdb..#UserPermissions') IS NOT NULL
    DROP TABLE #UserPermissions;

CREATE TABLE #UserPermissions (
    DatabaseName NVARCHAR(128),
    UserName NVARCHAR(128),
    UserType NVARCHAR(128),
    DatabaseRoles NVARCHAR(MAX),
    HasObjectPermissions BIT,
    IsOrphaned BIT
);


SELECT @sql = @sql + '
USE [' + name + '];
INSERT INTO #UserPermissions (DatabaseName, UserName, UserType, DatabaseRoles, HasObjectPermissions, IsOrphaned)
SELECT 
    ''' + name + ''' AS DatabaseName,
    dp.name AS UserName,
    dp.type_desc AS UserType,
    STUFF((
        SELECT '', '' + r.name
        FROM sys.database_role_members drm
        INNER JOIN sys.database_principals r ON drm.role_principal_id = r.principal_id
        WHERE drm.member_principal_id = dp.principal_id
        FOR XML PATH(''''), TYPE
    ).value(''.'', ''NVARCHAR(MAX)''), 1, 2, '''') AS DatabaseRoles,
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM sys.database_permissions dbp 
            WHERE dbp.grantee_principal_id = dp.principal_id 
            AND dbp.class > 0
        ) THEN 1 
        ELSE 0 
    END AS HasObjectPermissions,
    CASE 
        WHEN dp.type IN (''S'', ''U'') AND dp.sid IS NOT NULL AND dp.sid NOT IN (0x00, 0x01) 
             AND NOT EXISTS (SELECT 1 FROM sys.server_principals sp WHERE sp.sid = dp.sid)
        THEN 1
        ELSE 0
    END AS IsOrphaned
FROM 
    sys.database_principals dp
WHERE
        dp.type IN (''S'', ''U'', ''G'', ''A'') -- S=SQL User, U=Windows User, G=Windows Group, A=Application Role
    AND dp.principal_id > 4
    AND dp.is_fixed_role = 0;
'
FROM 
    sys.databases
WHERE
        state_desc = 'ONLINE'
    AND name NOT IN ('tempdb'); -- tempdb mostly not relevant

EXEC sp_executesql @sql;

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

-- Cleanup
DROP TABLE #UserPermissions;