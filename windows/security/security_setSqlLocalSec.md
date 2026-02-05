# security_setSqlLocalSec.ps1

## Description

This script configures the required local security policies (User Rights Assignment) for SQL Server service accounts. These permissions are required for proper SQL Server operation.

## What Gets Configured?

### User Rights Assignment (Local Security Policies)

The following permissions are set depending on the service type:

#### SQL Server Engine (`-ServiceType engine`)
| Right | Technical Name | Purpose |
|-------|----------------|---------|
| Log on as a batch job | SeBatchLogonRight | Batch execution |
| Log on as a service | SeServiceLogonRight | Start as service |
| Lock pages in memory | SeLockMemoryPrivilege | Performance optimization |
| Perform volume maintenance tasks | SeManageVolumePrivilege | Instant File Initialization |
| Replace a process-level token | SeAssignPrimaryTokenPrivilege | Process token |
| Adjust memory quotas | SeIncreaseQuotaPrivilege | Memory quotas |
| Bypass traverse checking | SeChangeNotifyPrivilege | Directory access |

#### SQL Server Agent (`-ServiceType agent`)
| Right | Technical Name | Purpose |
|-------|----------------|---------|
| Log on as a batch job | SeBatchLogonRight | Job execution |
| Log on as a service | SeServiceLogonRight | Start as service |
| Replace a process-level token | SeAssignPrimaryTokenPrivilege | Job steps |
| Adjust memory quotas | SeIncreaseQuotaPrivilege | Memory quotas |
| Bypass traverse checking | SeChangeNotifyPrivilege | Directory access |

#### SSIS (`-ServiceType ssis`)
| Right | Technical Name | Purpose |
|-------|----------------|---------|
| Log on as a batch job | SeBatchLogonRight | Package execution |
| Log on as a service | SeServiceLogonRight | Start as service |
| Impersonate a client | SeImpersonatePrivilege | Impersonation |
| Bypass traverse checking | SeChangeNotifyPrivilege | Directory access |

#### SSIS Proxy (`-ServiceType ssis_pxy`)
| Right | Technical Name | Purpose |
|-------|----------------|---------|
| Access this computer from network | SeNetworkLogonRight | Network access |

## Parameter Format

| Parameter | Format | Example |
|-----------|--------|---------|
| ServiceAccount | Account name with $ (without Domain) | `"g-LAB22A-oltp$"` |
| ServiceType | Enum | `"engine"`, `"agent"`, `"ssis"`, `"ssis_pxy"`, `"ssas"` |
| IsGMSA | Switch | `-IsGMSA` |

**Note**: Unlike `security_setSqlSpn.ps1`, only the account name (without domain prefix) is used here, as `Get-ADServiceAccount` expects this format.

## Best Practices

1. **Lock Pages in Memory**: Recommended for SQL Server Engine, reduces paging
2. **Instant File Initialization**: `SeManageVolumePrivilege` significantly speeds up database file creation
3. **Dedicated Accounts**: Use separate accounts for Engine and Agent

## Important Notes

1. **Local Administrator required**: Script must be run as admin
2. **Execute on each node**: For clusters, run separately on all nodes
3. **Restart optional**: Changes take effect on next service start

## Reference

- [Microsoft Docs: Configure Windows Service Accounts](https://docs.microsoft.com/en-us/sql/database-engine/configure-windows/configure-windows-service-accounts-and-permissions)
