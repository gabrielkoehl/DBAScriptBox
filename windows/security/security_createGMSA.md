# security_createGMSA.ps1

## Description

This script creates and manages Group Managed Service Accounts (gMSA) in Active Directory. gMSA is the recommended method for SQL Server service accounts as they provide automatic password management and eliminate the need for manual password changes.

## What Gets Configured?

### KDS Root Key (once per Forest)
- **Purpose**: Key Distribution Service Root Key for automatic password generation
- **Best Practice**: Must be initialized once per AD forest before gMSA accounts can be created
- **Cmdlet**: `Add-KdsRootKey`

### Security Group
- **Purpose**: AD security group that defines which servers are allowed to retrieve the gMSA password
- **Best Practice**: Create a dedicated group per cluster/server group
- **Contains**: Computer objects of the servers (with `$` suffix)

### gMSA Account
- **Purpose**: Managed Service Account with automatic password rotation
- **Best Practice**:
  - Separate accounts for Engine and Agent
  - Naming convention: `g-<Instance>-<Service>` (e.g., `g-LAB22A-oltp`, `g-LAB22A-agnt`)
  - Password interval: 30-90 days (default: 30)
- **Properties**:
  - `PrincipalsAllowedToRetrieveManagedPassword`: Security Group
  - `DNSHostName`: FQDN for Kerberos
  - `ManagedPasswordIntervalInDays`: Password rotation interval

## Parameter Format

| Parameter | Format | Example |
|-----------|--------|---------|
| AccountName | String or Array with [Name, Description] | `@("g-LAB22A-oltp", "SQL Engine Account")` |
| SecurityGroupName | String (without $) | `"SQL_LAB_CL01"` |
| ServerNames | Array of hostnames (without $) | `"LAB-NODE01","LAB-NODE02"` |
| SecurityGroupOU | Distinguished Name | `"OU=lab_secgrp,DC=lab,DC=local"` |

## Important Notes

1. **Server restart required**: After assigning a server to the Security Group, the server must be restarted
2. **Separate execution**: Account creation (Domain Admin) and local installation (Local Admin) must be executed separately
3. **Permissions**:
   - Account creation: Domain Admin or delegated AD permissions
   - Local installation: Local Administrator rights

## Reference

- [Microsoft Docs: gMSA Overview](https://docs.microsoft.com/en-us/windows-server/security/group-managed-service-accounts/group-managed-service-accounts-overview)
- [SQL Server gMSA Configuration](https://docs.microsoft.com/en-us/sql/database-engine/configure-windows/configure-windows-service-accounts-and-permissions)
