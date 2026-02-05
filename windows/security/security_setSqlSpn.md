# security_setSqlSpn.ps1

## Description

This script registers Service Principal Names (SPNs) for SQL Server service accounts and configures the required AD permissions. SPNs are required for Kerberos authentication, which is best practice for SQL Server.

## What Gets Configured?

### Service Principal Names (SPNs)
- **Purpose**: Enable Kerberos authentication for SQL Server connections
- **Format**: `MSSQLSvc/<FQDN>:<Instance>` and `MSSQLSvc/<FQDN>:<Port>`
- **Best Practice**:
  - Register both instance name and port
  - Register SPNs for all cluster nodes
- **Cmdlet**: `setspn.exe -S`

### AD Permissions on Computer Objects
- **Purpose**: Allows the service account to dynamically register/update SPNs
- **Permissions**:
  - Read servicePrincipalName
  - Write servicePrincipalName
  - Validated write to servicePrincipalName
- **Best Practice**: Automatic configuration with `-SetADPermissions` recommended

## Parameter Format

| Parameter | Format | Example |
|-----------|--------|---------|
| ServiceAccount | DOMAIN\account (without $) | `"LAB\g-LAB22A-oltp"` |
| InstanceName | String | `"LAB22A"` or `"MSSQLSERVER"` |
| Port | Integer | `51101` |
| Hostnames | Array of hostnames | `"LAB-NODE01","LAB-NODE02"` |
| Domain | DNS domain | `"lab.local"` |
| IsGMSA | Switch | `-IsGMSA` (adds $ automatically) |

## Registered SPNs (Example)

For an AlwaysOn configuration with 2 nodes, the following SPNs are registered:

```
MSSQLSvc/LAB-NODE01.lab.local:LAB22A
MSSQLSvc/LAB-NODE01.lab.local:51101
MSSQLSvc/LAB-NODE02.lab.local:LAB22A
MSSQLSvc/LAB-NODE02.lab.local:51101
```

## Kerberos Validation

After SPN registration and SQL Server restart:

```sql
SELECT auth_scheme
FROM sys.dm_exec_connections
WHERE session_id = @@SPID
-- Expected result: KERBEROS
```

## Important Notes

1. **SQL Server restart**: Required after SPN changes
2. **Uniqueness**: SPNs must be unique across the domain
3. **Permissions**: Domain Admin or delegated SPN permissions required

## Reference

- [Microsoft Docs: Register a SPN for Kerberos](https://docs.microsoft.com/en-us/sql/database-engine/configure-windows/register-a-service-principal-name-for-kerberos-connections)
