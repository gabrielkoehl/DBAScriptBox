# cluster_manageSQLCluster.ps1

## Description

This script manages the complete lifecycle of a Windows Failover Cluster for SQL Server AlwaysOn Availability Groups. It automates feature installation, cluster creation, and configuration of DNS and OU permissions.

## What Gets Configured?

### Failover Clustering Feature
- **Purpose**: Windows feature for high availability
- **Cmdlet**: `Install-WindowsFeature -Name Failover-Clustering`
- **Best Practice**: Install on all nodes before cluster creation

### Windows Failover Cluster
- **Purpose**: Cluster infrastructure for AlwaysOn AG
- **Components**:
  - Cluster Name Object (CNO): Computer object in AD
  - Cluster IP: Static IP for cluster management
  - Quorum: Voting mechanism for cluster decisions
- **Cmdlet**: `New-Cluster`

### DNS Permissions
- **Purpose**: Allows the cluster to create DNS records for AG Listeners
- **Permission**: CreateChild on DNS zone
- **Best Practice**: Required for automatic listener registration
- **Prerequisite**: AD-integrated DNS zone

### OU Permissions (VCO Creation)
- **Purpose**: Allows the cluster to create Virtual Computer Objects for AG Listeners
- **Permissions**:
  - CreateChild (create computer objects)
  - ReadProperty (read properties)
- **Best Practice**: Create VCOs in dedicated OU

### File Share Witness
- **Purpose**: Third vote for quorum in 2-node cluster
- **Best Practice**: On separate server, not on cluster nodes
- **Permission**: Full Control for ClusterName$ on share and NTFS

## Parameter Format

| Parameter | Format | Example |
|-----------|--------|---------|
| Operation | Enum | `"InstallFeature"`, `"CreateCluster"`, `"SetWitness"`, etc. |
| ClusterName | String | `"MSSQL-CL-01"` |
| Nodes | Array | `"LAB-NODE01","LAB-NODE02"` |
| StaticIP | IP address | `"192.168.100.14"` |
| DnsDomain | DNS domain | `"lab.local"` |
| TargetOU | Distinguished Name | `"OU=lab_computer,DC=lab,DC=local"` |
| WitnessShare | UNC path | `"\\LAB-DC\quorum$"` |

## Workflow for AlwaysOn

```
1. InstallFeature    -> Failover Clustering on all nodes
2. CreateCluster     -> Create cluster with DNS permissions
3. SetOUPermissions  -> OU permissions for Listener VCOs
4. [Manual]          -> Set Full Control on witness share
5. SetWitness        -> Configure file share witness
6. [SQL Server]      -> Configure AlwaysOn AG
```

## Quorum Configuration

For 2-node clusters (typical for AlwaysOn AG):
- **Recommendation**: Node and File Share Majority
- **Reason**: Cluster remains functional if one node fails

## Important Notes

1. **Restart after feature installation**: Nodes may need to be restarted
2. **AD replication**: Wait briefly after cluster creation before setting DNS/OU permissions
3. **Witness permissions**: Set manually before running SetWitness
4. **Validation**: Always run cluster validation (except in lab environments)

## Reference

- [Microsoft Docs: Failover Clustering](https://docs.microsoft.com/en-us/windows-server/failover-clustering/failover-clustering-overview)
- [Microsoft Docs: AlwaysOn Prerequisites](https://docs.microsoft.com/en-us/sql/database-engine/availability-groups/windows/prereqs-restrictions-recommendations-always-on-availability)
