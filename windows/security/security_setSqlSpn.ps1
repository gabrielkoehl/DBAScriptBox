<#
.SYNOPSIS
    Sets Service Principal Names (SPN) for SQL Server service accounts
.DESCRIPTION
    Registers SPNs for SQL Server instances to enable Kerberos authentication.
    Supports both named instances and port-based SPNs using native setspn.exe.
    Validates existing SPNs and prevents duplicates.
    Can automatically set required AD permissions on computer objects.
    Supports multiple servers for high availability scenarios (AlwaysOn, Failover Cluster).
.PARAMETER ServiceAccount
    Service account in format DOMAIN\account (without $ suffix)
.PARAMETER InstanceName
    SQL Server instance name (e.g., "DEV22A", "MSSQLSERVER" for default instance)
.PARAMETER Port
    SQL Server TCP port (e.g., 1433, 51101). Optional for named instances.
.PARAMETER Hostnames
    Array of server hostnames (e.g., "LAB-NODE01","LAB-NODE02"). Combined with Domain to build FQDN.
.PARAMETER Domain
    DNS domain suffix (e.g., "lab.local"). Combined with Hostnames to build FQDN.
.PARAMETER ServerFQDN
    Fully qualified domain name of SQL Server. Alternative to Hostnames/Domain parameters.
    If Hostnames and Domain are specified, this parameter is ignored.
.PARAMETER IsGMSA
    Switch to indicate account is a group managed service account (adds $ suffix)
.PARAMETER RemoveSPN
    Switch to remove SPNs instead of adding them
.PARAMETER ListOnly
    Switch to only list existing SPNs for the service account
.PARAMETER SetADPermissions
    Switch to automatically set required AD permissions on computer objects
.PARAMETER LogPath
    Optional path to log file for detailed operation logging
    If not specified, only console output is generated
    Example: "C:\Temp\SPN_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
.EXAMPLE
    .\security_setSqlSpn.ps1 -ServiceAccount "DEV\g-engine-dev22a" -InstanceName "DEV22A" -IsGMSA
    Sets SPN for named instance DEV22A using gMSA account
.EXAMPLE
    .\security_setSqlSpn.ps1 -ServiceAccount "DEV\g-engine-dev22a" -InstanceName "DEV22A" -Port 51101 -IsGMSA
    Sets both instance name and port SPNs for gMSA
.EXAMPLE
    .\security_setSqlSpn.ps1 -ServiceAccount "DEV\sql_service" -InstanceName "MSSQLSERVER" -Port 1433
    Sets SPNs for default instance with regular service account
.EXAMPLE
    .\security_setSqlSpn.ps1 -ServiceAccount "DEV\g-engine-dev22a" -IsGMSA -ListOnly
    Lists all SPNs registered for the gMSA account
.EXAMPLE
    .\security_setSqlSpn.ps1 -ServiceAccount "DEV\g-engine-dev22a" -InstanceName "DEV22A" -IsGMSA -RemoveSPN
    Removes SPNs for the specified instance
.EXAMPLE
    .\security_setSqlSpn.ps1 -ServiceAccount "LAB\g-LAB22A-oltp" -InstanceName "LAB22A" -IsGMSA -SetADPermissions -Hostnames "LAB-NODE01","LAB-NODE02" -Domain "lab.local"
    Sets SPNs and configures AD permissions on multiple cluster nodes
.NOTES
    File Name  : security_setSqlSpn.ps1
    Author     : Gabriel Köhl
    Website    : https://dbavonnebenan.de
    GitHub     : https://github.com/gabrielkoehl/DBAScriptBox
    HISTORY
    - 30.01.2026 - Init
    - 05.02.2026 - Added support for multiple servers via Hostnames/Domain parameters
                 - Added automatic AD permissions configuration

    Disclaimer: This script is provided "as is" without warranty of any kind.
                Use at your own risk. The author assumes no responsibility for
                any damages or issues that may arise from using this script.

    REQUIREMENTS:
    - Run with Domain Admin privileges or delegated SPN permissions
    - setspn.exe (included in Windows)
    - ActiveDirectory PowerShell module (for -SetADPermissions)

    NOTES:
    - For gMSA accounts, use -IsGMSA switch ($ suffix added automatically)
    - For default instance, use "MSSQLSERVER" as InstanceName
    - Port SPNs are optional but recommended for named instances
    - SPNs must be unique across the domain
    - Use -SetADPermissions to automatically configure required permissions
    - For high availability scenarios, use Hostnames and Domain parameters
#>

[CmdletBinding(DefaultParameterSetName='SetSPN')]
param (
    [Parameter(Mandatory=$true)]
    [string]$ServiceAccount,

    [Parameter(Mandatory=$true, ParameterSetName='SetSPN')]
    [Parameter(ParameterSetName='RemoveSPN')]
    [string]$InstanceName,

    [Parameter(ParameterSetName='SetSPN')]
    [Parameter(ParameterSetName='RemoveSPN')]
    [int]$Port,

    [Parameter(ParameterSetName='SetSPN')]
    [Parameter(ParameterSetName='RemoveSPN')]
    [string[]]$Hostnames,

    [Parameter(ParameterSetName='SetSPN')]
    [Parameter(ParameterSetName='RemoveSPN')]
    [string]$Domain,

    [Parameter(ParameterSetName='SetSPN')]
    [Parameter(ParameterSetName='RemoveSPN')]
    [string]$ServerFQDN,

    [Parameter(ParameterSetName='SetSPN')]
    [Parameter(ParameterSetName='RemoveSPN')]
    [Parameter(ParameterSetName='ListSPN')]
    [switch]$IsGMSA,

    [Parameter(Mandatory=$true, ParameterSetName='RemoveSPN')]
    [switch]$RemoveSPN,

    [Parameter(Mandatory=$true, ParameterSetName='ListSPN')]
    [switch]$ListOnly,

    [Parameter(ParameterSetName='SetSPN')]
    [switch]$SetADPermissions,

    [Parameter(ParameterSetName='SetSPN')]
    [Parameter(ParameterSetName='RemoveSPN')]
    [Parameter(ParameterSetName='ListSPN')]
    [string]$LogPath
)

#Requires -RunAsAdministrator

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

function Get-FormattedServiceAccount {
    param (
        [string]$Account,
        [switch]$GMSA
    )

    try {

        # Validate format
        if ($Account -notmatch '^[^\\]+\\[^\\]+$') {
            throw "ServiceAccount must be in format DOMAIN\account"
        }

        $parts          = $Account -split '\\'
        $domain         = $parts[0]
        $accountName    = $parts[1].TrimEnd('$')

        # Add $ suffix for gMSA
        if ($GMSA) {

            $accountName = "$accountName$"
            Write-Host "Using gMSA account: $domain\$accountName" -ForegroundColor Cyan
            Write-Log "Using gMSA account: $domain\$accountName"

        } else {

            Write-Host "Using service account: $domain\$accountName" -ForegroundColor Cyan
            Write-Log "Using service account: $domain\$accountName"

        }

        return @{
            FullName    = "$domain\$accountName"
            Domain      = $domain
            Account     = $accountName
        }

    } catch {

        Write-Log "Error processing service account: $($_.Exception.Message)" -Level "ERROR"
        throw "Error processing service account: $($_.Exception.Message)"

    }
}

function Test-ServiceAccountExists {
    param (
        [string]$ServiceAccount
    )

    try {

        Write-Host "Validating service account..." -NoNewline
        Write-Log "Validating service account: $ServiceAccount"

        # Try to query SPNs - if account doesn't exist, setspn will fail
        $result = setspn -L $ServiceAccount 2>&1

        if ($LASTEXITCODE -eq 0) {

            Write-Host " OK" -ForegroundColor Green
            Write-Log "Service account validated successfully"
            return $true

        } else {

            Write-Host " FAILED" -ForegroundColor Red
            Write-Host "Error: Account '$ServiceAccount' not found in Active Directory" -ForegroundColor Red
            Write-Host "Details: $result" -ForegroundColor Gray
            Write-Log "Account '$ServiceAccount' not found in Active Directory" -Level "ERROR"
            Write-Log "Details: $result" -Level "ERROR"
            return $false

        }

    } catch {

        Write-Host " FAILED" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "Error validating service account: $($_.Exception.Message)" -Level "ERROR"
        return $false

    }
}

function Get-ServerFQDNList {
    param (
        [string[]]$Hostnames,
        [string]$Domain,
        [string]$ServerFQDN
    )

    try {

        $fqdnList = @()

        # Priority 1: Hostnames + Domain
        if ($Hostnames -and $Hostnames.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($Domain)) {

            foreach ($hostname in $Hostnames) {
                $fqdnList += "$hostname.$Domain"
            }

            Write-Log "Using Hostnames + Domain: $($fqdnList -join ', ')"
            return $fqdnList
        }

        # Priority 2: Single ServerFQDN
        if (-not [string]::IsNullOrWhiteSpace($ServerFQDN)) {
            $fqdnList += $ServerFQDN
            Write-Log "Using ServerFQDN: $ServerFQDN"
            return $fqdnList
        }

        # Priority 3: Current computer FQDN
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
        $domain         = $computerSystem.Domain
        $hostname       = $computerSystem.Name
        $fqdnList += "$hostname.$domain"

        Write-Log "Using current computer FQDN: $($fqdnList[0])"
        return $fqdnList

    } catch {

        Write-Log "Error getting server FQDN: $($_.Exception.Message)" -Level "ERROR"
        throw "Error getting server FQDN: $($_.Exception.Message)"

    }
}

function Get-ExistingSPNs {
    param (
        [string]$ServiceAccount
    )

    try {

        Write-Host "`nQuerying existing SPNs for $ServiceAccount..." -ForegroundColor Cyan
        Write-Log "Querying existing SPNs for: $ServiceAccount"

        $result = setspn -L $ServiceAccount 2>&1

        if ($LASTEXITCODE -eq 0) {

            $spnFound = $false
            Write-Host "`nRegistered SPNs:" -ForegroundColor Green

            $result | ForEach-Object {
                if ($_ -match 'MSSQLSvc/') {
                    Write-Host "  $_" -ForegroundColor White
                    Write-Log "Found SPN: $_"
                    $spnFound = $true
                }
            }

            if (-not $spnFound) {
                Write-Host "  No MSSQLSvc SPNs found" -ForegroundColor Yellow
                Write-Log "No MSSQLSvc SPNs found for account" -Level "WARN"
            }

        } else {

            Write-Host "Error querying SPNs" -ForegroundColor Red
            Write-Host $result -ForegroundColor Gray
            Write-Log "Error querying SPNs: $result" -Level "ERROR"

        }

    } catch {

        Write-Host "Error querying SPNs: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "Error querying SPNs: $($_.Exception.Message)" -Level "ERROR"

    }
}

function Test-SPNExists {
    param (
        [string]$SPN
    )

    try {

        $result = setspn -Q $SPN 2>&1
        $exists = $result -match "Existing SPN found"

        if ($exists) {
            Write-Log "SPN already exists: $SPN"
        }

        return $exists

    } catch {

        Write-Log "Error checking SPN existence: $($_.Exception.Message)" -Level "ERROR"
        return $false

    }
}

function Set-SPNADPermissions {
    param (
        [string]$ServiceAccount,
        [string[]]$ComputerNames
    )

    try {

        # Check if ActiveDirectory module is available
        if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
            Write-Host "`nActiveDirectory module not found. Cannot set AD permissions." -ForegroundColor Red
            Write-Host "Install RSAT-AD-PowerShell feature or run on Domain Controller." -ForegroundColor Yellow
            Write-Log "ActiveDirectory module not available" -Level "ERROR"
            return $false
        }

        Import-Module ActiveDirectory -ErrorAction Stop
        Write-Log "ActiveDirectory module loaded successfully"

        Write-Host "`n=== Setting AD Permissions ===" -ForegroundColor Cyan
        Write-Host "==============================" -ForegroundColor Cyan
        Write-Log "=== Setting AD Permissions ==="

        # Get service account object and SID
        $accountName = ($ServiceAccount -split '\\')[1]
        Write-Log "Processing account: $accountName"

        try {

            $accountObj = Get-ADServiceAccount -Identity $accountName -ErrorAction Stop
            $sid = New-Object System.Security.Principal.SecurityIdentifier $accountObj.SID
            Write-Log "Found gMSA account: $accountName"

        } catch {

            try {

                $accountObj = Get-ADUser -Identity $accountName -ErrorAction Stop
                $sid = New-Object System.Security.Principal.SecurityIdentifier $accountObj.SID
                Write-Log "Found user account: $accountName"

            } catch {

                Write-Host "Error: Could not find service account '$accountName' in AD" -ForegroundColor Red
                Write-Log "Service account '$accountName' not found in AD" -Level "ERROR"
                return $false

            }

        }

        # Define the GUID for servicePrincipalName
        $guidSPN = [GUID]"f3a64788-5306-11d1-a9c5-0000f80367c1"
        Write-Log "Using SPN GUID: $guidSPN"

        $successCount = 0
        foreach ($computerName in $ComputerNames) {
            try {
                Write-Host "`nProcessing $computerName..." -ForegroundColor Cyan
                Write-Log "Processing computer: $computerName"

                # Get the computer object
                $computer = Get-ADComputer -Identity $computerName
                Write-Log "Found computer object: $($computer.DistinguishedName)"

                # Get current ACL
                $acl = Get-Acl -Path "AD:\$($computer.DistinguishedName)"

                # Create ACE for Read Property
                $aceRead = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
                    $sid,
                    [System.DirectoryServices.ActiveDirectoryRights]::ReadProperty,
                    [System.Security.AccessControl.AccessControlType]::Allow,
                    $guidSPN,
                    [System.DirectoryServices.ActiveDirectorySecurityInheritance]::None
                )

                # Create ACE for Write Property
                $aceWrite = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
                    $sid,
                    [System.DirectoryServices.ActiveDirectoryRights]::WriteProperty,
                    [System.Security.AccessControl.AccessControlType]::Allow,
                    $guidSPN,
                    [System.DirectoryServices.ActiveDirectorySecurityInheritance]::None
                )

                # Create ACE for Validated-SPN (Self permission)
                $aceValidate = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
                    $sid,
                    [System.DirectoryServices.ActiveDirectoryRights]::Self,
                    [System.Security.AccessControl.AccessControlType]::Allow,
                    $guidSPN,
                    [System.DirectoryServices.ActiveDirectorySecurityInheritance]::None
                )

                # Add the ACEs to ACL
                $acl.AddAccessRule($aceRead)
                $acl.AddAccessRule($aceWrite)
                $acl.AddAccessRule($aceValidate)

                # Apply the modified ACL
                Set-Acl -Path "AD:\$($computer.DistinguishedName)" -AclObject $acl

                Write-Host "  ✓ Permissions set successfully" -ForegroundColor Green
                Write-Log "Permissions set successfully on $computerName"

                # Verify
                $newAcl = Get-Acl -Path "AD:\$($computer.DistinguishedName)"
                $serviceAccountPermissions = $newAcl.Access | Where-Object { $_.IdentityReference -like "*$accountName*" }
                $serviceAccountPermissions | Format-Table IdentityReference, ActiveDirectoryRights, AccessControlType -AutoSize

                Write-Log "Verified permissions: $($serviceAccountPermissions.ActiveDirectoryRights)"

                $successCount++

            } catch {

                Write-Host "  ✗ Error: $_" -ForegroundColor Red
                Write-Log "Error setting permissions on ${computerName}: $($_.Exception.Message)" -Level "ERROR"

            }
        }

        Write-Host "`nSuccessfully set permissions on $successCount of $($ComputerNames.Count) computer objects" -ForegroundColor Cyan
        Write-Log "AD permissions summary: $successCount/$($ComputerNames.Count) successful"
        return ($successCount -eq $ComputerNames.Count)

    } catch {

        Write-Host "`nError setting AD permissions: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "Error in Set-SPNADPermissions: $($_.Exception.Message)" -Level "ERROR"
        return $false

    }
}

function security_setSqlSpn {
    param (
        [string]$SPN,
        [string]$ServiceAccount,
        [switch]$Remove
    )

    try {

        if ($Remove) {

            Write-Host "Removing SPN: $SPN..." -NoNewline
            Write-Log "Removing SPN: $SPN"
            $result = setspn -D $SPN $ServiceAccount 2>&1

        } else {
            # Check if SPN already exists

            if (Test-SPNExists -SPN $SPN) {

                Write-Host "SPN already exists: $SPN" -ForegroundColor Yellow
                Write-Log "SPN already exists: $SPN" -Level "WARN"

                # Show which account owns it
                $queryResult = setspn -Q $SPN 2>&1

                Write-Host "Current owner:" -ForegroundColor Yellow

                $queryResult | Where-Object { $_ -match "CN=" } | ForEach-Object {
                    Write-Host "  $_" -ForegroundColor Gray
                    Write-Log "  Current owner: $_"
                }

                return $false
            }

            Write-Host "Setting SPN: $SPN..." -NoNewline
            Write-Log "Setting SPN: $SPN"
            $result = setspn -S $SPN $ServiceAccount 2>&1

        }

        if ($LASTEXITCODE -eq 0) {

            Write-Host " OK" -ForegroundColor Green
            Write-Log "SPN operation successful: $SPN"
            return $true

        } else {

            Write-Host " FAILED" -ForegroundColor Red
            Write-Host "Error: $result" -ForegroundColor Red
            Write-Log "SPN operation failed: $result" -Level "ERROR"
            return $false

        }

    } catch {

        Write-Host " FAILED" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "Exception in security_setSqlSpn: $($_.Exception.Message)" -Level "ERROR"

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
    Add-Content -Path $LogPath -Value "ParameterSet: $($PSCmdlet.ParameterSetName)"
    Add-Content -Path $LogPath -Value $separator

    Write-Log "Script parameters: $($PSBoundParameters | ConvertTo-Json -Compress)"

}

# Display header
Write-Host "======================================" -ForegroundColor Magenta
Write-Host "  SQL Server SPN Management" -ForegroundColor Magenta
Write-Host "======================================" -ForegroundColor Magenta
Write-Host "ParameterSet: $($PSCmdlet.ParameterSetName)" -ForegroundColor White
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host ""

Write-Log "=== SQL Server SPN Management Script Started ==="

# Format service account
$accountInfo = Get-FormattedServiceAccount -Account $ServiceAccount -GMSA:$IsGMSA

# Validate service account exists
if (-not (Test-ServiceAccountExists -ServiceAccount $accountInfo.FullName)) {

    Write-Host "`nOperation aborted: Service account does not exist" -ForegroundColor Red
    Write-Log "Operation aborted: Service account does not exist" -Level "ERROR"

    if ($LogPath) {
        $separator = "=" * 80
        Add-Content -Path $LogPath -Value $separator
        Add-Content -Path $LogPath -Value "Execution finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        Add-Content -Path $LogPath -Value "Status: FAILED"
        Add-Content -Path $LogPath -Value $separator
    }

    exit 1

}

# Handle ListOnly parameter
if ($PSCmdlet.ParameterSetName -eq 'ListSPN') {

    Write-Log "Listing existing SPNs for: $($accountInfo.FullName)"
    Get-ExistingSPNs -ServiceAccount $accountInfo.FullName
    Write-Log "List operation completed"

    if ($LogPath) {

        Write-Host "`nLog file: $LogPath" -ForegroundColor Cyan
        $separator = "=" * 80
        Add-Content -Path $LogPath -Value $separator
        Add-Content -Path $LogPath -Value "Execution finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        Add-Content -Path $LogPath -Value "Status: SUCCESS"
        Add-Content -Path $LogPath -Value $separator

    }

    exit 0

}

# Get server FQDN list
$fqdnList = Get-ServerFQDNList -Hostnames $Hostnames -Domain $Domain -ServerFQDN $ServerFQDN

Write-Host "`nConfiguration:" -ForegroundColor Cyan
Write-Host "  Server(s):       $($fqdnList -join ', ')" -ForegroundColor White
Write-Host "  Instance Name:   $InstanceName" -ForegroundColor White
Write-Host "  Service Account: $($accountInfo.FullName)" -ForegroundColor White

Write-Log "Configuration: Servers=$($fqdnList -join ', '), Instance=$InstanceName, Account=$($accountInfo.FullName)"

if ($Port) {
    Write-Host "  Port:            $Port" -ForegroundColor White
    Write-Log "Port: $Port"
}

Write-Host ""

# Handle AD permissions if requested
if ($SetADPermissions) {

    Write-Log "AD permissions configuration requested"

    # Extract hostnames from FQDNs for AD computer objects
    $computersForPermissions = $fqdnList | ForEach-Object { $_.Split('.')[0] }

    Write-Host "Computer objects for AD permissions: $($computersForPermissions -join ', ')" -ForegroundColor Cyan
    Write-Log "Computer objects for permissions: $($computersForPermissions -join ', ')"

    $permissionsSet = Set-SPNADPermissions -ServiceAccount $accountInfo.FullName -ComputerNames $computersForPermissions

    if (-not $permissionsSet) {

        Write-Host "`nWarning: AD permissions were not set successfully." -ForegroundColor Yellow
        Write-Host "SQL Server may not be able to register SPNs dynamically." -ForegroundColor Yellow
        Write-Log "AD permissions were not set successfully" -Level "WARN"

    } else {

        Write-Log "AD permissions set successfully"

    }
}

# Build SPN list for all servers
$spnList = @()

foreach ($fqdn in $fqdnList) {

    # Add instance name SPN
    $instanceSPN = "MSSQLSvc/${fqdn}:${InstanceName}"
    $spnList    += $instanceSPN

    # Add port SPN if specified
    if ($Port) {
        $portSPN = "MSSQLSvc/${fqdn}:${Port}"
        $spnList += $portSPN
    }

}

Write-Log "Total SPNs to process: $($spnList.Count)"
Write-Log "SPN list: $($spnList -join ', ')"

# Process SPNs
$success = $false

if ($PSCmdlet.ParameterSetName -eq 'RemoveSPN') {

    Write-Host "Removing SPNs..." -ForegroundColor Cyan
    Write-Host "----------------" -ForegroundColor Cyan
    Write-Log "=== Removing SPNs ==="

    $successCount = 0
    foreach ($spn in $spnList) {

        if (security_setSqlSpn -SPN $spn -ServiceAccount $accountInfo.FullName -Remove) {
            $successCount++
        }

    }

    Write-Host "`nRemoved $successCount of $($spnList.Count) SPNs" -ForegroundColor Cyan
    Write-Log "Removed $successCount of $($spnList.Count) SPNs"

    $success = ($successCount -eq $spnList.Count)

} else {

    Write-Host "Setting SPNs..." -ForegroundColor Cyan
    Write-Host "---------------" -ForegroundColor Cyan
    Write-Log "=== Setting SPNs ==="

    $successCount = 0
    foreach ($spn in $spnList) {

        if (security_setSqlSpn -SPN $spn -ServiceAccount $accountInfo.FullName) {
            $successCount++
        }

    }

    Write-Host "`nSuccessfully set $successCount of $($spnList.Count) SPNs" -ForegroundColor Cyan
    Write-Log "Successfully set $successCount of $($spnList.Count) SPNs"

    $success = ($successCount -eq $spnList.Count)

}


# Show current SPNs
Get-ExistingSPNs -ServiceAccount $accountInfo.FullName

if ($PSCmdlet.ParameterSetName -eq 'SetSPN') {

    # Provide validation guidance
    Write-Host "`n=== Validation ===" -ForegroundColor Cyan
    Write-Host "==================" -ForegroundColor Cyan
    Write-Host "To validate Kerberos authentication:" -ForegroundColor White
    Write-Host "  1. Restart SQL Server service" -ForegroundColor Gray
    Write-Host "  2. Connect using SSMS with Windows Authentication" -ForegroundColor Gray
    Write-Host "  3. Run: SELECT auth_scheme FROM sys.dm_exec_connections WHERE session_id = @@SPID" -ForegroundColor Gray
    Write-Host "  4. Expected result: KERBEROS" -ForegroundColor Gray

    Write-Log "Validation guidance provided to user"

    if (-not $SetADPermissions) {

        Write-Host "`n=== Required AD Permissions ===" -ForegroundColor Yellow
        Write-Host "===============================" -ForegroundColor Yellow
        Write-Host "The service account '$($accountInfo.FullName)' needs the following permissions" -ForegroundColor White
        Write-Host "on the computer objects in Active Directory:" -ForegroundColor White
        Write-Host ""
        Write-Host "  - Read servicePrincipalName" -ForegroundColor Gray
        Write-Host "  - Write servicePrincipalName" -ForegroundColor Gray
        Write-Host "  - Validated write to servicePrincipalName" -ForegroundColor Gray
        Write-Host ""
        Write-Host "To set these permissions automatically, run this script with -SetADPermissions" -ForegroundColor Cyan

        if ($Hostnames -and $Domain) {
            Write-Host "Example: .\security_setSqlSpn.ps1 -ServiceAccount '$ServiceAccount' -InstanceName '$InstanceName' -Hostnames $($Hostnames -join ',') -Domain '$Domain' -IsGMSA:$($IsGMSA.IsPresent) -SetADPermissions" -ForegroundColor Gray
        } else {
            Write-Host "Example: .\security_setSqlSpn.ps1 -ServiceAccount '$ServiceAccount' -InstanceName '$InstanceName' -IsGMSA:$($IsGMSA.IsPresent) -SetADPermissions" -ForegroundColor Gray
        }

        Write-Host ""
        Write-Host "Or set manually:" -ForegroundColor White
        Write-Host "  1. Open 'Active Directory Users and Computers'" -ForegroundColor Gray
        Write-Host "  2. Enable 'Advanced Features' in View menu" -ForegroundColor Gray
        Write-Host "  3. Navigate to computer objects" -ForegroundColor Gray
        Write-Host "  4. Right-click -> Properties -> Security -> Advanced" -ForegroundColor Gray
        Write-Host "  5. Add -> Select Principal: $($accountInfo.FullName)" -ForegroundColor Gray
        Write-Host "  6. Set permissions as listed above" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Without these permissions, SQL Server cannot register/update SPNs dynamically." -ForegroundColor Yellow

        Write-Log "AD permissions reminder displayed to user"

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
    Add-Content -Path $LogPath -Value "Status: $(if ($success) { 'SUCCESS' } else { 'FAILED' })"
    Add-Content -Path $LogPath -Value $separator

}

#endregion

<# EXAMPLES

    # ===== EXAMPLE 1: SingleNode - SPN for standalone Server with gMSA =====
    .\security_setSqlSpn.ps1 `
        -ServiceAccount "LAB\g-DEV22A-oltp" `
        -InstanceName "DEV22A" `
        -Port 51101 `
        -Hostnames "DEV-SRV01" `
        -Domain "lab.local" `
        -IsGMSA `
        -SetADPermissions `
        -LogPath "C:\Temp\SPN_SingleNode_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

    # ===== EXAMPLE 2: AlwaysOn - SPNs for 2 Nodes with AD Permissions =====
    .\security_setSqlSpn.ps1 `
        -ServiceAccount "LAB\g-LAB22A-oltp" `
        -InstanceName "LAB22A" `
        -Port 51101 `
        -Hostnames "LAB-NODE01","LAB-NODE02" `
        -Domain "lab.local" `
        -IsGMSA `
        -SetADPermissions `
        -LogPath "C:\Temp\SPN_AlwaysOn_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

    # ===== EXAMPLE 3: List existing SPNs =====
    .\security_setSqlSpn.ps1 `
        -ServiceAccount "LAB\g-LAB22A-oltp" `
        -IsGMSA `
        -ListOnly `
        -LogPath "C:\Temp\SPN_List_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

    # ===== EXAMPLE 4: Remove SPNs =====
    .\security_setSqlSpn.ps1 `
        -ServiceAccount "LAB\g-LAB22A-oltp" `
        -InstanceName "LAB22A" `
        -Hostnames "LAB-NODE01","LAB-NODE02" `
        -Domain "lab.local" `
        -IsGMSA `
        -RemoveSPN `
        -LogPath "C:\Temp\SPN_Remove_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

#>