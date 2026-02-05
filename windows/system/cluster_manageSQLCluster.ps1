<#
.SYNOPSIS
    Creates and configures Windows Failover Cluster with automated DNS and OU permissions

.DESCRIPTION
    Automates the complete lifecycle of a Windows Failover Cluster including:
    - Installing Failover Clustering feature on all nodes
    - Creating the cluster with specified nodes and static IP
    - Configuring file share witness for quorum
    - Setting cluster DNS permissions for SQL Availability Group Listeners
    - Setting cluster OU permissions for creating Virtual Computer Objects (VCOs)
    - Validating cluster configuration
    - Removing clusters

    The script operates in stages using Parameter Sets to ensure proper workflow:
    1. InstallFeature: Installs clustering on nodes
    2. CreateCluster: Creates cluster (optionally with AS / DNS permissions)
    3. SetDNSPermissions: Sets DNS permissions separately
    4. SetOUPermissions: Sets OU permissions for VCO creation separately
    5. SetWitness: Configures file share witness (separate from creation)
    6. ValidateCluster: Runs validation tests
    7. RemoveCluster: Removes cluster from AD

    IMPORTANT: Witness configuration is separate from cluster creation to allow
    proper permissions setup on the file share between these operations.

.PARAMETER Operation
    Specifies the operation to perform using Parameter Sets:
    - InstallFeature: Installs Failover Clustering feature on all nodes
    - CreateCluster: Creates cluster
    - SetDNSPermissions: Configures DNS permissions
    - SetOUPermissions: Configures OU permissions for VCO creation
    - SetWitness: Configures file share witness for quorum
    - ValidateCluster: Runs cluster validation tests
    - RemoveCluster: Removes cluster from Active Directory

.PARAMETER ClusterName
    Name of the failover cluster
    This becomes the Computer Name Object (CNO) in Active Directory

.PARAMETER Nodes
    Array of node names that will be part of the cluster
    Format: Computer names without domain suffix (e.g., "LAB-NODE01","LAB-NODE02")

.PARAMETER StaticIP
    Static IP address for the cluster name resource
    Required for CreateCluster operation
    Example: "192.168.1.100"

.PARAMETER WitnessShare
    UNC path to the file share witness
    Required for SetWitness operation
    Format: \\FileServer\ShareName
    Example: "\\FS01\ClusterWitness$"

.PARAMETER DnsDomain
    DNS domain name for Listener name registration
    If specified, grants CreateChild permission in DNS for cluster to create A records
    Example: "contoso.com"
    Required for SQL Availability Group Listeners to register DNS names automatically

.PARAMETER TargetOU
    Distinguished Name of the OU where cluster should create Virtual Computer Objects
    Required for SetOUPermissions operation
    Example: "OU=SQL Clusters,OU=Servers,DC=contoso,DC=com"
    Grants CreateChild permission for Computer objects in this OU

.PARAMETER SkipValidation
    Skip cluster validation tests during CreateCluster operation
    Not recommended for production environments

.PARAMETER LogPath
    Optional path to log file for detailed operation logging
    If not specified, only console output is generated
    Example: "C:\Temp\Cluster_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

.EXAMPLE
    .\cluster_manageSQLCluster.ps1 -Operation InstallFeature -Nodes "LAB-NODE01","LAB-NODE02" -LogPath "C:\Temp\cluster_install.log"
    Installs Failover Clustering feature on specified nodes with logging

.EXAMPLE
    .\cluster_manageSQLCluster.ps1 -Operation CreateCluster -ClusterName "MSSQL-CL-01" -Nodes "LAB-NODE01","LAB-NODE02" -StaticIP "192.168.1.100"
    Creates cluster without DNS permissions

.EXAMPLE
    .\cluster_manageSQLCluster.ps1 -Operation CreateCluster -ClusterName "MSSQL-CL-01" -Nodes "LAB-NODE01","LAB-NODE02" -StaticIP "192.168.1.100" -DnsDomain "corp.local"
    Creates cluster with DNS permissions during creation

.EXAMPLE
    .\cluster_manageSQLCluster.ps1 -Operation SetDNSPermissions -ClusterName "MSSQL-CL-01" -DnsDomain "corp.local"
    Sets DNS permissions on existing cluster (run separately after cluster creation)

.EXAMPLE
    .\cluster_manageSQLCluster.ps1 -Operation SetOUPermissions -ClusterName "MSSQL-CL-01" -TargetOU "OU=SQL Clusters,OU=Servers,DC=corp,DC=local"
    Sets OU permissions for cluster to create Virtual Computer Objects

.EXAMPLE
    .\cluster_manageSQLCluster.ps1 -Operation SetWitness -ClusterName "MSSQL-CL-01" -WitnessShare "\\FS01\ClusterWitness"
    Configures file share witness (run after granting permissions on share)

.EXAMPLE
    .\cluster_manageSQLCluster.ps1 -Operation ValidateCluster -Nodes "LAB-NODE01","LAB-NODE02" -LogPath "C:\Temp\validation.log"
    Runs validation tests with logging

.EXAMPLE
    .\cluster_manageSQLCluster.ps1 -Operation RemoveCluster -ClusterName "MSSQL-CL-01"
    Removes cluster from Active Directory

.NOTES
    File Name  : cluster_manageSQLCluster.ps1
    Author     : Gabriel Köhl
    Website    : https://dbavonnebenan.de
    GitHub     : https://github.com/gabrielkoehl/DBAScriptBox
    HISTORY
    - 05.02.2026 - Init

    Disclaimer: This script is provided "as is" without warranty of any kind.
                Use at your own risk. The author assumes no responsibility for
                any damages or issues that may arise from using this script.

    REQUIREMENTS (mostly handled by script):
    - PowerShell 5.1 (FailoverClusters is a native 5.1 Module)
    - EXECUTING SERVER: FailoverClusters PowerShell module (auto-installed by script)
      * Alternative: Execute this script directly on one of the cluster nodes
    - Domain Administrator rights or delegated permissions
    - Local Administrator rights on all cluster nodes
    - ActiveDirectory PowerShell module (auto-installed when needed)
    - All nodes must be domain-joined
    - Network connectivity between all nodes
    - WinRM must be active
    - File share for witness must exist before SetWitness operation
    - For SQL Listeners creation
        * DnsDomain parameter required for DNS permissions
        * TargetOU parameter required for VCO creation

    ADMIN RIGHTS:
    - Domain admin or delegated permissions for:
      * Cluster creation in AD
      * DNS permission modification (if using -DnsDomain)
      * OU permission modification (if using -TargetOU)
    - Local administrator on all nodes for feature installation
    - Full Control on witness share for cluster computer object (ClusterName$)

    WORKFLOW FOR SQL SERVER CLUSTERS:
    1. Run: -Operation InstallFeature
    2. Run: -Operation CreateCluster (with or without -DnsDomain)
    3. Optional: -Operation SetDNSPermissions (if not set during CreateCluster)
    4. Optional: -Operation SetOUPermissions (for VCO creation in specific OU)
    5. Grant Full Control to ClusterName$ on witness share
    6. Run: -Operation SetWitness
    7. Optional: -Operation ValidateCluster

    SQL AVAILABILITY GROUP LISTENER REQUIREMENTS:
    - Cluster CNO automatically creates Listener computer objects (VCOs)
    - DNS permissions required (via -DnsDomain) for automatic DNS registration
    - OU permissions required (via -TargetOU) for automatic VCO creation in specific OU
    - DNS zone must be AD-integrated for automatic permissions
#>

[CmdletBinding(DefaultParameterSetName='InstallFeature')]
param (
    [Parameter(Mandatory=$true, ParameterSetName='InstallFeature')]
    [Parameter(Mandatory=$true, ParameterSetName='CreateCluster')]
    [Parameter(Mandatory=$true, ParameterSetName='SetDNSPermissions')]
    [Parameter(Mandatory=$true, ParameterSetName='SetOUPermissions')]
    [Parameter(Mandatory=$true, ParameterSetName='SetWitness')]
    [Parameter(Mandatory=$true, ParameterSetName='ValidateCluster')]
    [Parameter(Mandatory=$true, ParameterSetName='RemoveCluster')]
    [ValidateSet('InstallFeature','CreateCluster','SetDNSPermissions','SetOUPermissions','SetWitness','ValidateCluster','RemoveCluster')]
    [string]    $Operation,

    [Parameter(Mandatory=$true, ParameterSetName='CreateCluster')]
    [Parameter(Mandatory=$true, ParameterSetName='SetDNSPermissions')]
    [Parameter(Mandatory=$true, ParameterSetName='SetOUPermissions')]
    [Parameter(ParameterSetName='SetWitness')]
    [Parameter(ParameterSetName='RemoveCluster')]
    [string]    $ClusterName,

    [Parameter(Mandatory=$true, ParameterSetName='InstallFeature')]
    [Parameter(Mandatory=$true, ParameterSetName='CreateCluster')]
    [Parameter(Mandatory=$true, ParameterSetName='ValidateCluster')]
    [string[]]  $Nodes,

    [Parameter(Mandatory=$true, ParameterSetName='CreateCluster')]
    [string]    $StaticIP,

    [Parameter(Mandatory=$true, ParameterSetName='SetWitness')]
    [string]    $WitnessShare,

    [Parameter(ParameterSetName='CreateCluster')]
    [Parameter(Mandatory=$true, ParameterSetName='SetDNSPermissions')]
    [string]    $DnsDomain,

    [Parameter(ParameterSetName='CreateCluster')]
    [Parameter(Mandatory=$true, ParameterSetName='SetOUPermissions')]
    [string]    $TargetOU,

    [Parameter(ParameterSetName='CreateCluster')]
    [switch]    $SkipValidation,

    [Parameter(ParameterSetName='InstallFeature')]
    [Parameter(ParameterSetName='CreateCluster')]
    [Parameter(ParameterSetName='SetDNSPermissions')]
    [Parameter(ParameterSetName='SetOUPermissions')]
    [Parameter(ParameterSetName='SetWitness')]
    [Parameter(ParameterSetName='ValidateCluster')]
    [Parameter(ParameterSetName='RemoveCluster')]
    [string]    $LogPath
)

#Requires -RunAsAdministrator

if ($PSVersionTable.PSVersion.Major -ne 5) {
    throw "This script requires PowerShell 5.1"
}

#region Helper Functions

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $timestamp  = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    if ($LogPath) {
        Add-Content -Path $LogPath -Value $logMessage
    }
}

function Test-AdminRights {

    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

}

function Install-RequiredModules {

    Write-Host "Checking required PowerShell modules..." -ForegroundColor Cyan
    Write-Log "Checking required PowerShell modules"

    # FailoverClusters module - check if module file exists ( Get-Module -ListAvailable not working with this)
    $clusterModulePath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\Modules\FailoverClusters\FailoverClusters.psd1"

    if (Test-Path $clusterModulePath) {

        Write-Host "  FailoverClusters module already installed" -ForegroundColor Green
        Write-Log "FailoverClusters module already available at $clusterModulePath"

        # Import if not loaded
        if (-not (Get-Module -Name FailoverClusters)) {
            Import-Module FailoverClusters -ErrorAction SilentlyContinue
        }

    } else {

        Write-Host "  Installing FailoverClusters module..." -ForegroundColor Yellow
        Write-Log "Installing FailoverClusters module"

        try {

            Install-WindowsFeature -Name RSAT-Clustering-PowerShell -ErrorAction Stop | Out-Null
            Import-Module FailoverClusters -ErrorAction Stop
            Write-Host "  FailoverClusters module installed" -ForegroundColor Green
            Write-Log "FailoverClusters module installed successfully"

        } catch {

            Write-Host "  Error installing module: $($_.Exception.Message)" -ForegroundColor Red
            Write-Log "Error installing FailoverClusters module: $($_.Exception.Message)" -Level "ERROR"
            return $false

        }
    }

    # ActiveDirectory module (only if DNS or OU permissions needed)
    if ($DnsDomain -or $TargetOU) {

        $adModulePath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\Modules\ActiveDirectory\ActiveDirectory.psd1"

        if (Test-Path $adModulePath) {
            Write-Host "  ActiveDirectory module already installed" -ForegroundColor Green
            Write-Log "ActiveDirectory module already available at $adModulePath"

            # Import if not loaded
            if (-not (Get-Module -Name ActiveDirectory)) {
                Import-Module ActiveDirectory -ErrorAction SilentlyContinue
            }
        } else {
            Write-Host "  Installing ActiveDirectory module..." -ForegroundColor Yellow
            Write-Log "Installing ActiveDirectory module"

            try {
                Install-WindowsFeature -Name RSAT-AD-PowerShell -ErrorAction Stop | Out-Null
                Import-Module ActiveDirectory -ErrorAction Stop
                Write-Host "  ActiveDirectory module installed" -ForegroundColor Green
                Write-Log "ActiveDirectory module installed successfully"
            } catch {
                Write-Host "  Error installing module: $($_.Exception.Message)" -ForegroundColor Red
                Write-Log "Error installing ActiveDirectory module: $($_.Exception.Message)" -Level "ERROR"
                return $false
            }
        }
    }

    return $true
}

function Install-ClusterFeature {
    param(
        [string[]]  $NodeList
    )

    Write-Host "`n=== Installing Failover Clustering Feature ===" -ForegroundColor Cyan
    Write-Log "=== Installing Failover Clustering Feature ==="

    $installResults = @()

    foreach ($node in $NodeList) {

        Write-Host "  Processing node: $node" -ForegroundColor Yellow
        Write-Log "Processing node: $node"

        try {

            # Check connectivity
            Write-Host "    Testing connectivity..." -NoNewline
            if (-not (Test-WSMan -ComputerName $node -ErrorAction SilentlyContinue)) {
                Write-Host " Failed" -ForegroundColor Red
                Write-Log "Cannot reach node: $node (WinRM not available)" -Level "ERROR"
                $installResults += [PSCustomObject]@{
                    Node   = $node
                    Status = "Unreachable"
                }
                continue
            }
            Write-Host " OK" -ForegroundColor Green

            # Check if feature is already installed
            Write-Host "    Checking feature status..." -NoNewline
            $featureStatus = Invoke-Command -ComputerName $node -ScriptBlock {
                Get-WindowsFeature -Name Failover-Clustering
            } -ErrorAction Stop

            if ($featureStatus.Installed) {
                Write-Host " Already installed" -ForegroundColor Green
                Write-Log "Feature already installed on $node"

                $installResults += [PSCustomObject]@{
                    Node          = $node
                    Status        = "AlreadyInstalled"
                    RestartNeeded = "No"
                }
                continue
            }
            Write-Host " Not installed" -ForegroundColor Yellow

            # Install feature
            Write-Host "    Installing feature..." -NoNewline
            $result = Invoke-Command -ComputerName $node -ScriptBlock {
                Install-WindowsFeature -Name Failover-Clustering -IncludeManagementTools
            } -ErrorAction Stop

            if ($result.Success) {

                Write-Host " OK" -ForegroundColor Green
                Write-Log "Feature installed successfully on $node"

                if ($result.RestartNeeded -eq 'Yes') {
                    Write-Host "    WARNING: Restart required" -ForegroundColor Yellow
                    Write-Log "Node $node requires restart" -Level "WARN"
                }

                $installResults += [PSCustomObject]@{
                    Node          = $node
                    Status        = "Success"
                    RestartNeeded = $result.RestartNeeded
                }

            } else {

                Write-Host " Failed" -ForegroundColor Red
                Write-Log "Feature installation failed on $node" -Level "ERROR"
                $installResults += [PSCustomObject]@{
                    Node   = $node
                    Status = "Failed"
                }

            }

        } catch {

            Write-Host " Error" -ForegroundColor Red
            Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
            Write-Log "Failed to install feature on ${node}: $($_.Exception.Message)" -Level "ERROR"

            $installResults += [PSCustomObject]@{
                Node   = $node
                Status = "Error"
                Error  = $_.Exception.Message
            }

        }
    }

    # Summary
    Write-Host "`n=== Installation Summary ===" -ForegroundColor Cyan
    foreach ($result in $installResults) {

        $color = switch ($result.Status) {
            "Success" { "Green" }
            "AlreadyInstalled" { "Green" }
            "Unreachable" { "Yellow" }
            default { "Red" }
        }
        Write-Host "  $($result.Node): $($result.Status)" -ForegroundColor $color
        if ($result.RestartNeeded -eq 'Yes') {
            Write-Host "    Restart required" -ForegroundColor Yellow
        }

    }

    $failedCount = ($installResults | Where-Object { $_.Status -notin @("Success", "AlreadyInstalled") }).Count

    if ($failedCount -eq 0) {

        Write-Host "`nFeature installation completed successfully" -ForegroundColor Green
        Write-Log "Feature installation completed successfully"
        return $true

    } else {

        Write-Host "`nFeature installation completed with $failedCount failure(s)" -ForegroundColor Red
        Write-Log "Feature installation completed with $failedCount failure(s)" -Level "ERROR"
        return $false

    }
}

function Set-ClusterDNSPermissions {
    param(
        [string]    $ClusterCNO,
        [string]    $Domain
    )

    Write-Host "`n  Configuring DNS permissions for SQL Listeners..." -ForegroundColor Cyan
    Write-Log "Configuring DNS permissions for cluster: $ClusterCNO in domain: $Domain"

    try {

        # Get cluster computer object
        $clusterObject = Get-ADComputer -Identity $ClusterCNO -ErrorAction Stop
        Write-Host "    Cluster object found: $($clusterObject.DistinguishedName)" -ForegroundColor Green
        Write-Log "Cluster object found for DNS permissions: $($clusterObject.DistinguishedName)"

        # Get AD Domain
        $adDomain = Get-ADDomain

        # Get DNS zone from AD (AD-integrated zones only)
        $dnsZoneDN = "DC=$Domain,CN=MicrosoftDNS,DC=DomainDnsZones,$($adDomain.DistinguishedName)"

        Write-Host "    Searching for DNS zone..." -NoNewline
        Write-Log "Searching DNS zone at: $dnsZoneDN"

        $dnsZone = Get-ADObject -Identity $dnsZoneDN -ErrorAction Stop
        Write-Host " Found" -ForegroundColor Green
        Write-Log "DNS zone found: $dnsZoneDN"

        # Get current ACL
        $acl = Get-Acl -Path "AD:$($dnsZone.DistinguishedName)"

        # Create access rule for DNS record creation (CreateChild only)
        $identity           = [System.Security.Principal.SecurityIdentifier]$clusterObject.SID
        $adRights           = [System.DirectoryServices.ActiveDirectoryRights]::CreateChild
        $type               = [System.Security.AccessControl.AccessControlType]::Allow
        $inheritanceType    = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All

        $accessRule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($identity, $adRights, $type, $inheritanceType)

        # Add rule to ACL
        $acl.AddAccessRule($accessRule)

        # Apply ACL
        Set-Acl -Path "AD:$($dnsZone.DistinguishedName)" -AclObject $acl

        Write-Host "    DNS permissions configured successfully" -ForegroundColor Green
        Write-Host "    Permission: Create DNS records" -ForegroundColor Gray
        Write-Host "    Zone DN: $($dnsZone.DistinguishedName)" -ForegroundColor Gray
        Write-Log "DNS permissions configured successfully for cluster $ClusterCNO in domain $Domain"
        return $true

    } catch {

        Write-Host "    Error configuring DNS permissions: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "    Note: DNS zone must be AD-integrated for automatic permissions" -ForegroundColor Yellow
        Write-Host "    Check: Get-DnsServerZone -Name '$Domain' | Select IsDsIntegrated" -ForegroundColor Gray
        Write-Log "Error configuring DNS permissions: $($_.Exception.Message)" -Level "ERROR"
        return $false

    }
}

function Set-ClusterOUPermissions {
    param(
        [string]    $ClusterCNO,
        [string]    $OUPath
    )

    Write-Host "`n  Configuring OU permissions for VCO creation..." -ForegroundColor Cyan
    Write-Log "Configuring OU permissions for cluster: $ClusterCNO in OU: $OUPath"

    try {

        # Get cluster computer object
        $clusterObject = Get-ADComputer -Identity $ClusterCNO -ErrorAction Stop
        Write-Host "    Cluster object found: $($clusterObject.DistinguishedName)" -ForegroundColor Green
        Write-Log "Cluster object found for OU permissions: $($clusterObject.DistinguishedName)"

        # Validate OU exists
        Write-Host "    Validating OU..." -NoNewline
        Write-Log "Validating OU path: $OUPath"

        $targetOU = Get-ADOrganizationalUnit -Identity $OUPath -ErrorAction Stop
        Write-Host " Found" -ForegroundColor Green
        Write-Log "OU found: $($targetOU.DistinguishedName)"

        # Get current ACL
        $acl = Get-Acl -Path "AD:$($targetOU.DistinguishedName)"

        # Identity for all rules
        $identity           = [System.Security.Principal.SecurityIdentifier]$clusterObject.SID
        $type               = [System.Security.AccessControl.AccessControlType]::Allow
        $inheritanceType    = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All

        # Rule 1: CreateChild permission
        $createChildRights = [System.DirectoryServices.ActiveDirectoryRights]::CreateChild
        $createChildRule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
            $identity,
            $createChildRights,
            $type,
            $inheritanceType
        )

        # Rule 2: ReadProperty permission
        $readPropertyRights = [System.DirectoryServices.ActiveDirectoryRights]::ReadProperty
        $readPropertyRule   = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
            $identity,
            $readPropertyRights,
            $type,
            $inheritanceType
        )

        # Add both rules to ACL
        $acl.AddAccessRule($createChildRule)
        $acl.AddAccessRule($readPropertyRule)

        # Apply ACL
        Set-Acl -Path "AD:$($targetOU.DistinguishedName)" -AclObject $acl

        Write-Host "    OU permissions configured successfully" -ForegroundColor Green
        Write-Host "    Permissions: Create Child objects, Read Property" -ForegroundColor Gray
        Write-Host "    OU DN: $($targetOU.DistinguishedName)" -ForegroundColor Gray
        Write-Log "OU permissions configured successfully for cluster $ClusterCNO in OU $OUPath"
        return $true

    } catch {

        Write-Host "    Error configuring OU permissions: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "    Note: Verify OU Distinguished Name format" -ForegroundColor Yellow
        Write-Host "    Example: 'OU=SQL Clusters,OU=Servers,DC=contoso,DC=com'" -ForegroundColor Gray
        Write-Log "Error configuring OU permissions: $($_.Exception.Message)" -Level "ERROR"
        return $false

    }
}

function New-FailoverCluster {
    param(
        [string]    $Name,
        [string[]]  $NodeList,
        [string]    $IP,
        [string]    $DNS,
        [string]    $OU,
        [bool]      $SkipVal
    )

    Write-Host "`n=== Creating Failover Cluster ===" -ForegroundColor Cyan
    Write-Log "=== Creating Failover Cluster: $Name ==="

    # Run validation unless skipped
    if (-not $SkipVal) {

        Write-Host "  Running cluster validation tests..." -ForegroundColor Yellow
        Write-Log "Running cluster validation tests"

        try {

            $validationReport = Test-Cluster -Node $NodeList -ErrorAction Stop
            Write-Host "  Validation completed" -ForegroundColor Green
            Write-Host "  Report: $($validationReport.FullName)" -ForegroundColor Gray
            Write-Log "Validation completed successfully. Report: $($validationReport.FullName)"

        } catch {

            Write-Host "  Cluster validation failed: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "  Windows Feature Clustering installed?" -ForegroundColor Yellow
            Write-Log "Cluster validation failed: $($_.Exception.Message)" -Level "ERROR"

            return $false

        }

    } else {

        Write-Host "  Validation skipped (not recommended for production)" -ForegroundColor Yellow
        Write-Log "Cluster validation skipped" -Level "WARN"

    }

    # Create cluster
    try {

        Write-Host "`n  Creating cluster '$Name'..." -ForegroundColor Yellow
        Write-Log "Creating cluster: $Name with IP: $IP, Nodes: $($NodeList -join ', ')"

        $cluster = New-Cluster -Name $Name `
                               -Node $NodeList `
                               -StaticAddress $IP `
                               -NoStorage `
                               -ErrorAction Stop

        Write-Host "  Cluster created successfully" -ForegroundColor Green
        Write-Host "    Name: $($cluster.Name)" -ForegroundColor Cyan
        Write-Host "    Nodes: $($NodeList -join ', ')" -ForegroundColor Cyan
        Write-Host "    IP: $IP" -ForegroundColor Cyan
        Write-Log "Cluster created successfully: $Name"


        # Configure DNS permissions if specified
        if ($DNS) {

            Write-Host "`n  SQL Listener Configuration:" -ForegroundColor Yellow
            $dnsSuccess = Set-ClusterDNSPermissions -ClusterCNO $Name -Domain $DNS

            if (-not $dnsSuccess) {
                Write-Host "    Warning: DNS permissions failed. SQL Listeners may not register." -ForegroundColor Yellow
                Write-Log "DNS permissions configuration failed for cluster $Name" -Level "WARN"
            }

        }

        # Configure OU permissions if specified
        if ($OU) {
            Write-Host "`n  SQL Listener VCO Configuration:" -ForegroundColor Yellow
            $ouSuccess = Set-ClusterOUPermissions -ClusterCNO $Name -OUPath $OU

            if (-not $ouSuccess) {
                Write-Host "    Warning: OU permissions failed. VCO creation may fail." -ForegroundColor Yellow
                Write-Log "OU permissions configuration failed for cluster $Name" -Level "WARN"
            }
        }

        # Summary
        Write-Host "`n=== Cluster Creation Summary ===" -ForegroundColor Cyan
        Write-Host "  Cluster Name: $Name" -ForegroundColor Green
        Write-Host "  Nodes: $($NodeList -join ', ')" -ForegroundColor Green
        Write-Host "  IP Address: $IP" -ForegroundColor Green

        if ($DNS) {
            Write-Host "  DNS Permissions: Configured" -ForegroundColor Green
            Write-Host "    Domain: $DNS" -ForegroundColor Gray
        }

        Write-Host "`nNext steps:" -ForegroundColor Yellow
        if (-not $DNS) {
            Write-Host "   Optional: Configure DNS permissions with -Operation SetDNSPermissions" -ForegroundColor White
        }

        if (-not $OU) {
            Write-Host "   Optional: Configure OU permissions with -Operation SetOUPermissions" -ForegroundColor White
        }

        Write-Host "   Grant Full Control to '$Name`$' on witness share" -ForegroundColor White
        Write-Host "   Run: -Operation SetWitness -ClusterName '$Name' -WitnessShare '\\Server\Share'" -ForegroundColor Gray

        Write-Log "Cluster creation completed successfully"

        return $true

    } catch {

        Write-Host "  Failed to create cluster: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "Failed to create cluster: $($_.Exception.Message)" -Level "ERROR"
        return $false

    }
}

function Set-ClusterFileShareWitness {
    param(
        [string]    $Name,
        [string]    $SharePath
    )

    Write-Host "`n=== Configuring File Share Witness ===" -ForegroundColor Cyan
    Write-Log "=== Configuring File Share Witness for cluster: $Name ==="

    # Validate share path format
    if (-not ($SharePath -match '^\\\\[^\\]+\\[^\\]+')) {

        Write-Host "Error: WitnessShare must be UNC path format: \\Server\Share" -ForegroundColor Red
        Write-Log "Invalid WitnessShare format: $SharePath" -Level "ERROR"
        return $false

    }

    Write-Host "  Share path: $SharePath" -ForegroundColor Gray
    Write-Log "Configuring witness share: $SharePath"

    # Configure witness - must execute on cluster node
    try {

        # Get first available cluster node via New-Cluster's approach
        Write-Host "  Detecting cluster node..." -NoNewline

        # We need to get node names differently since Get-ClusterNode fails remotely
        # Use WMI/CIM as fallback
        $clusterNodes   = Get-CimInstance -Namespace root/MSCluster -ClassName MSCluster_Node -ComputerName $Name -ErrorAction Stop
        $clusterNode    = $clusterNodes[0].Name

        Write-Host " $clusterNode" -ForegroundColor Green
        Write-Log "Using cluster node: $clusterNode for witness configuration"

        Write-Host "  Setting file share witness..." -NoNewline
        Write-Log "Setting file share witness: $SharePath for cluster: $Name"

        # Execute on cluster node
        $result = Invoke-Command -ComputerName $clusterNode -ScriptBlock {

            param($ClusterName, $Witness)

            Set-ClusterQuorum -Cluster $ClusterName -FileShareWitness $Witness -ErrorAction Stop
            Get-ClusterQuorum -Cluster $ClusterName

        } -ArgumentList $Name, $SharePath -ErrorAction Stop

        Write-Host " OK" -ForegroundColor Green

        Write-Host "`n=== Witness Configuration Summary ===" -ForegroundColor Cyan
        Write-Host "  Cluster: $Name" -ForegroundColor Green
        Write-Host "  Quorum Type: $($result.QuorumType)" -ForegroundColor Green
        Write-Host "  Resource: $($result.QuorumResource.Name)" -ForegroundColor Green
        Write-Host "  Path: $SharePath" -ForegroundColor Green

        Write-Log "Witness configured successfully for cluster $Name"
        return $true

    } catch {

        Write-Host " Failed" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "`nTroubleshooting:" -ForegroundColor Yellow
        Write-Host "  - Verify '$Name`$' has Full Control on share: $SharePath" -ForegroundColor White
        Write-Host "  - Check both share permissions AND NTFS permissions" -ForegroundColor White
        Write-Host "  - Ensure cluster can resolve share server name" -ForegroundColor White
        Write-Host "  - Verify share exists and is accessible from cluster nodes" -ForegroundColor White
        Write-Log "Failed to configure witness: $($_.Exception.Message)" -Level "ERROR"
        return $false

    }
}

function Remove-FailoverCluster {
    param(
        [string]    $Name
    )

    Write-Host "`n=== Removing Failover Cluster ===" -ForegroundColor Cyan
    Write-Log "=== Attempting to remove cluster: $Name ==="

    Write-Host "WARNING: This will destroy the cluster '$Name'" -ForegroundColor Red
    Write-Host "         All cluster resources will be removed" -ForegroundColor Red
    Write-Host "         Cluster object will be removed from AD" -ForegroundColor Red
    Write-Log "User prompted for cluster removal confirmation" -Level "WARN"

    Write-Host "`nType cluster name to confirm removal: " -NoNewline -ForegroundColor Yellow
    $confirmation = Read-Host

    if ($confirmation -ne $Name) {

        Write-Host "`nOperation cancelled" -ForegroundColor Yellow
        Write-Log "Cluster removal cancelled by user"
        return $false

    }

    # Get cluster SID before removal
    $clusterSID = $null

    try {

        $clusterObject = Get-ADComputer -Identity $Name -ErrorAction SilentlyContinue

        if ($clusterObject) {
            $clusterSID = $clusterObject.SID
            Write-Log "Cluster SID: $clusterSID"
        }

    } catch {

        Write-Log "Could not retrieve cluster SID: $($_.Exception.Message)" -Level "WARN"

    }

    try {

        Write-Host "`n  Removing cluster..." -ForegroundColor Yellow
        Write-Log "Attempting to remove cluster $Name"

        # Remove cluster
        Remove-Cluster -Cluster $Name -Force -CleanupAD -ErrorAction Stop

        Write-Host "    Cluster removed" -ForegroundColor Green
        Write-Log "Cluster $Name removed successfully"

        Write-Host "`n=== Removal Summary ===" -ForegroundColor Cyan
        Write-Host "  Cluster '$Name' removed successfully" -ForegroundColor Green
        Write-Host "  AD objects cleaned up" -ForegroundColor Green

        if ($clusterSID) {

            Write-Host "`n  Manual cleanup may be required:" -ForegroundColor Yellow
            Write-Host "  If DNS/OU permissions were set, remove manually" -ForegroundColor Yellow
            Write-Host "  Cluster SID was: $clusterSID" -ForegroundColor Gray
            Write-Log "Manual permission cleanup may be required for SID: $clusterSID"

        }

        Write-Log "Cluster $Name removed successfully"

        return $true

    } catch {

        Write-Host "  Execution failed" -ForegroundColor Red
        Write-Log "Cluster removal failed: $($_.Exception.Message)" -Level "ERROR"

        # Detect cluster node for manual instructions
        try {

            Write-Host "`n  Detecting cluster node..." -NoNewline
            $clusterNodes   = Get-CimInstance -Namespace root/MSCluster -ClassName MSCluster_Node -ComputerName $Name -ErrorAction Stop
            $clusterNode    = $clusterNodes[0].Name
            Write-Host " $clusterNode" -ForegroundColor Green
            Write-Log "Detected cluster node for manual execution: $clusterNode"

        } catch {

            Write-Host " Failed" -ForegroundColor Red
            $clusterNode = "<cluster-node-name>"
            Write-Log "Failed to detect cluster node: $($_.Exception.Message)" -Level "WARN"

        }

        # Show manual instructions
        Write-Host "`n=== Manual Execution if possible ===" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Execute on cluster node: $clusterNode" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "   Remove-Cluster -Cluster $Name -Force -CleanupAD" -ForegroundColor Cyan
        Write-Host ""

        return $false
    }
}


#endregion

#region Main Execution

# Initialize log file
if ($LogPath) {

    $logDir = Split-Path -Path $LogPath -Parent

    if ($logDir -and -not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    $separator = "=" * 80
    Add-Content -Path $LogPath -Value "`n$separator"
    Add-Content -Path $LogPath -Value "Execution started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Add-Content -Path $LogPath -Value "Operation: $Operation"
    Add-Content -Path $LogPath -Value "ParameterSet: $($PSCmdlet.ParameterSetName)"
    Add-Content -Path $LogPath -Value $separator

    Write-Log "Script parameters: $($PSBoundParameters | ConvertTo-Json -Compress)"

}

# Display header
Write-Host "======================================" -ForegroundColor Magenta
Write-Host "  SQL Cluster Management Script" -ForegroundColor Magenta
Write-Host "======================================" -ForegroundColor Magenta
Write-Host "Operation: $Operation" -ForegroundColor White
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host ""

# Admin rights check
if (-not (Test-AdminRights)) {

    Write-Host "ERROR: This script requires administrator rights" -ForegroundColor Red
    Write-Host "Please run PowerShell as Administrator" -ForegroundColor Yellow
    Write-Log "Script aborted: Missing administrator rights" -Level "ERROR"
    exit 1

}

Write-Log "Administrator rights verified"

# Install required modules
$modulesOk = Install-RequiredModules

if (-not $modulesOk) {

    Write-Host "`nERROR: Required modules could not be installed" -ForegroundColor Red
    Write-Log "Script aborted: Module installation failed" -Level "ERROR"
    exit 1

}

Write-Host ""

# Execute operation based on ParameterSet
$success = $false

switch ($PSCmdlet.ParameterSetName) {

    'InstallFeature' {

        $success = Install-ClusterFeature -NodeList $Nodes

    }

    'CreateCluster' {

        $success = New-FailoverCluster -Name $ClusterName `
                                       -NodeList $Nodes `
                                       -IP $StaticIP `
                                       -DNS $DnsDomain `
                                       -OU $TargetOU `
                                       -SkipVal $SkipValidation.IsPresent

    }

    'SetDNSPermissions' {

        Write-Host "`n=== Configuring DNS Permissions ===" -ForegroundColor Cyan
        Write-Log "=== Configuring DNS Permissions for cluster: $ClusterName ==="

        $success = Set-ClusterDNSPermissions -ClusterCNO $ClusterName -Domain $DnsDomain

        if ($success) {

            Write-Host "`nDNS permissions configured successfully" -ForegroundColor Green
            Write-Log "DNS permissions operation completed successfully"

        } else {

            Write-Host "`nDNS permissions configuration failed" -ForegroundColor Red
            Write-Log "DNS permissions operation failed" -Level "ERROR"

        }

    }

    'SetOUPermissions' {

        Write-Host "`n=== Configuring OU Permissions ===" -ForegroundColor Cyan
        Write-Log "=== Configuring OU Permissions for cluster: $ClusterName ==="

        $success = Set-ClusterOUPermissions -ClusterCNO $ClusterName -OUPath $TargetOU

        if ($success) {

            Write-Host "`nOU permissions configured successfully" -ForegroundColor Green
            Write-Log "OU permissions operation completed successfully"

        } else {

            Write-Host "`nOU permissions configuration failed" -ForegroundColor Red
            Write-Log "OU permissions operation failed" -Level "ERROR"

        }

    }

    'SetWitness' {

        $success = Set-ClusterFileShareWitness -Name $ClusterName `
                                               -SharePath $WitnessShare

    }

    'ValidateCluster' {

        $success = Invoke-ClusterValidation -NodeList $Nodes

    }

    'RemoveCluster' {

        $success = Remove-FailoverCluster -Name $ClusterName

    }
}

# Final summary
Write-Host "`n======================================" -ForegroundColor Magenta
if ($success) {

    Write-Host "  Operation completed successfully" -ForegroundColor Green
    Write-Log "=== Operation completed successfully ==="

} else {

    Write-Host "  Operation completed with errors" -ForegroundColor Red
    Write-Host "  Review output above for details" -ForegroundColor Yellow
    Write-Log "=== Operation completed with errors ===" -Level "ERROR"

}

Write-Host "======================================" -ForegroundColor Magenta

if ($LogPath) {

    Write-Host "`nLog file: $LogPath" -ForegroundColor Cyan
    $separator = "=" * 80
    Add-Content -Path $LogPath -Value $separator
    Add-Content -Path $LogPath -Value "Execution finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Add-Content -Path $LogPath -Value $separator

}

#endregion


<# EXAMPLES

    # ===== EXAMPLE 1: Install Failover Clustering Feature =====
    .\cluster_manageSQLCluster.ps1 `
        -Operation InstallFeature `
        -Nodes "LAB-NODE01","LAB-NODE02" `
        -LogPath "C:\Temp\Cluster_InstallFeature_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

    # ===== EXAMPLE 2: Create Cluster with DNS and AD Permissions (AlwaysOn) =====
    .\cluster_manageSQLCluster.ps1 `
        -Operation CreateCluster `
        -ClusterName "MSSQL-CL-01" `
        -Nodes "LAB-NODE01","LAB-NODE02" `
        -StaticIP "192.168.100.14" `
        -DnsDomain "lab.local" `
        -TargetOU "OU=lab_computer,DC=lab,DC=local" `
        -LogPath "C:\Temp\Cluster_Create_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

    # ===== EXAMPLE 3: Set OU Permissions for VCO Creation =====
    .\cluster_manageSQLCluster.ps1 `
        -Operation SetOUPermissions `
        -ClusterName "MSSQL-CL-01" `
        -TargetOU "OU=lab_computer,DC=lab,DC=local" `
        -LogPath "C:\Temp\Cluster_OUPermissions_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

    # ===== EXAMPLE 4: Configure File Share Witness =====
    .\cluster_manageSQLCluster.ps1 `
        -Operation SetWitness `
        -ClusterName "MSSQL-CL-01" `
        -WitnessShare "\\LAB-DC\quorum$" `
        -LogPath "C:\Temp\Cluster_Witness_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

    # ===== EXAMPLE 5: Remove Cluster =====
    .\cluster_manageSQLCluster.ps1 `
        -Operation RemoveCluster `
        -ClusterName "MSSQL-CL-01" `
        -LogPath "C:\Temp\Cluster_Remove_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

#>