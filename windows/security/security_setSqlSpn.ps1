<#
.SYNOPSIS
    Sets Service Principal Names (SPN) for SQL Server service accounts
.DESCRIPTION
    Registers SPNs for SQL Server instances to enable Kerberos authentication.
    Supports both named instances and port-based SPNs using native setspn.exe.
    Validates existing SPNs and prevents duplicates.
.PARAMETER ServiceAccount
    Service account in format DOMAIN\account (without $ suffix)
.PARAMETER InstanceName
    SQL Server instance name (e.g., "DEV22A", "MSSQLSERVER" for default instance)
.PARAMETER Port
    SQL Server TCP port (e.g., 1433, 51101). Optional for named instances.
.PARAMETER ServerFQDN
    Fully qualified domain name of SQL Server (default: current computer FQDN)
.PARAMETER IsGMSA
    Switch to indicate account is a group managed service account (adds $ suffix)
.PARAMETER RemoveSPN
    Switch to remove SPNs instead of adding them
.PARAMETER ListOnly
    Switch to only list existing SPNs for the service account
.EXAMPLE
    .\Add-RemoveSPN.ps1 -ServiceAccount "DEV\g-engine-dev22a" -InstanceName "DEV22A" -IsGMSA
    Sets SPN for named instance DEV22A using gMSA account
.EXAMPLE
    .\Add-RemoveSPN.ps1 -ServiceAccount "DEV\g-engine-dev22a" -InstanceName "DEV22A" -Port 51101 -IsGMSA
    Sets both instance name and port SPNs for gMSA
.EXAMPLE
    .\Add-RemoveSPN.ps1 -ServiceAccount "DEV\sql_service" -InstanceName "MSSQLSERVER" -Port 1433
    Sets SPNs for default instance with regular service account
.EXAMPLE
    .\Add-RemoveSPN.ps1 -ServiceAccount "DEV\g-engine-dev22a" -IsGMSA -ListOnly
    Lists all SPNs registered for the gMSA account
.EXAMPLE
    .\Add-RemoveSPN.ps1 -ServiceAccount "DEV\g-engine-dev22a" -InstanceName "DEV22A" -IsGMSA -RemoveSPN
    Removes SPNs for the specified instance
.NOTES
    File Name  : Add-RemoveSPN.ps1
    Author     : Gabriel Köhl
    Website    : https://dbavonnebenan.de
    GitHub     : https://github.com/gabrielkoehl/DBAScriptBox
    HISTORY
    - 30.01.2026 - Init
    Disclaimer: This script is provided "as is" without warranty of any kind.
                Use at your own risk. The author assumes no responsibility for
                any damages or issues that may arise from using this script.

    REQUIREMENTS:
    - Run with Domain Admin privileges or delegated SPN permissions
    - setspn.exe (included in Windows)

    NOTES:
    - For gMSA accounts, use -IsGMSA switch ($ suffix added automatically)
    - For default instance, use "MSSQLSERVER" as InstanceName
    - Port SPNs are optional but recommended for named instances
    - SPNs must be unique across the domain
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
    [string]$ServerFQDN,

    [Parameter(ParameterSetName='SetSPN')]
    [Parameter(ParameterSetName='RemoveSPN')]
    [Parameter(ParameterSetName='ListSPN')]
    [switch]$IsGMSA,

    [Parameter(Mandatory=$true, ParameterSetName='RemoveSPN')]
    [switch]$RemoveSPN,

    [Parameter(Mandatory=$true, ParameterSetName='ListSPN')]
    [switch]$ListOnly
)

#Requires -Modules ActiveDirectory
#Requires -RunAsAdministrator

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
        } else {
            Write-Host "Using service account: $domain\$accountName" -ForegroundColor Cyan
        }

        return @{
            FullName    = "$domain\$accountName"
            Domain      = $domain
            Account     = $accountName
        }

    } catch {

        throw "Error processing service account: $($_.Exception.Message)"

    }
}

function Test-ServiceAccountExists {
    param (
        [string]$ServiceAccount
    )

    try {

        Write-Host "Validating service account..." -NoNewline

        # Try to query SPNs - if account doesn't exist, setspn will fail
        $result = setspn -L $ServiceAccount 2>&1

        if ($LASTEXITCODE -eq 0) {

            Write-Host " OK" -ForegroundColor Green
            return $true

        } else {

            Write-Host " FAILED" -ForegroundColor Red
            Write-Host "Error: Account '$ServiceAccount' not found in Active Directory" -ForegroundColor Red
            Write-Host "Details: $result" -ForegroundColor Gray
            return $false

        }

    } catch {

        Write-Host " FAILED" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        return $false

    }
}

function Get-ServerFQDN {
    param (
        [string]$ServerName
    )

    try {

        if ([string]::IsNullOrWhiteSpace($ServerName)) {

            # Get current computer FQDN
            $computerSystem = Get-WmiObject Win32_ComputerSystem
            $domain         = $computerSystem.Domain
            $hostname       = $computerSystem.Name

            return "$hostname.$domain"

        } else {

            return $ServerName

        }

    } catch {

        throw "Error getting server FQDN: $($_.Exception.Message)"

    }
}

function Get-ExistingSPNs {
    param (
        [string]$ServiceAccount
    )

    try {

        Write-Host "`nQuerying existing SPNs for $ServiceAccount..." -ForegroundColor Cyan

        $result = setspn -L $ServiceAccount 2>&1

        if ($LASTEXITCODE -eq 0) {

            $spnFound = $false
            Write-Host "`nRegistered SPNs:" -ForegroundColor Green

            $result | ForEach-Object {
                if ($_ -match 'MSSQLSvc/') {
                    Write-Host "  $_" -ForegroundColor White
                    $spnFound = $true
                }
            }

            if (-not $spnFound) {
                Write-Host "  No MSSQLSvc SPNs found" -ForegroundColor Yellow
            }

        } else {

            Write-Host "Error querying SPNs" -ForegroundColor Red
            Write-Host $result -ForegroundColor Gray

        }

    } catch {

        Write-Host "Error querying SPNs: $($_.Exception.Message)" -ForegroundColor Red
        
    }
}

function Test-SPNExists {
    param (
        [string]$SPN
    )

    try {
        
        $result = setspn -Q $SPN 2>&1
        $exists = $result -match "Existing SPN found"
        return $exists

    } catch {

        return $false

    }
}

function Add-RemoveSPN {
    param (
        [string]$SPN,
        [string]$ServiceAccount,
        [switch]$Remove
    )

    try {
        if ($Remove) {

            Write-Host "Removing SPN: $SPN..." -NoNewline
            $result = setspn -D $SPN $ServiceAccount 2>&1

        } else {
            # Check if SPN already exists

            if (Test-SPNExists -SPN $SPN) {

                Write-Host "SPN already exists: $SPN" -ForegroundColor Yellow

                # Show which account owns it
                $queryResult = setspn -Q $SPN 2>&1

                Write-Host "Current owner:" -ForegroundColor Yellow

                $queryResult | Where-Object { $_ -match "CN=" } | ForEach-Object {
                    Write-Host "  $_" -ForegroundColor Gray
                }

                return $false
            }

            Write-Host "Setting SPN: $SPN..." -NoNewline
            $result = setspn -S $SPN $ServiceAccount 2>&1

        }

        if ($LASTEXITCODE -eq 0) {

            Write-Host " OK" -ForegroundColor Green
            return $true

        } else {

            Write-Host " FAILED" -ForegroundColor Red
            Write-Host "Error: $result" -ForegroundColor Red
            return $false

        }

    } catch {

        Write-Host " FAILED" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red

        return $false

    }
}

# Main execution
    Write-Host "=== SQL Server SPN Management ===" -ForegroundColor Cyan
    Write-Host "=================================" -ForegroundColor Cyan

# Format service account
    $accountInfo = Get-FormattedServiceAccount -Account $ServiceAccount -GMSA:$IsGMSA

# Validate service account exists
    if (-not (Test-ServiceAccountExists -ServiceAccount $accountInfo.FullName)) {

        Write-Host "`nOperation aborted: Service account does not exist" -ForegroundColor Red
        exit 1

    }

# Handle ListOnly parameter
    if ($PSCmdlet.ParameterSetName -eq 'ListSPN') {

        Get-ExistingSPNs -ServiceAccount $accountInfo.FullName
        exit 0

    }

# Get server FQDN
    $fqdn = Get-ServerFQDN -ServerName $ServerFQDN

    Write-Host "`nConfiguration:" -ForegroundColor Cyan
    Write-Host "  Server FQDN:     $fqdn" -ForegroundColor White
    Write-Host "  Instance Name:   $InstanceName" -ForegroundColor White
    Write-Host "  Service Account: $($accountInfo.FullName)" -ForegroundColor White

    if ($Port) {
        Write-Host "  Port:            $Port" -ForegroundColor White
    }

    Write-Host ""

# Build SPN list
    $spnList = @()

# Add instance name SPN
    $instanceSPN = "MSSQLSvc/${fqdn}:${InstanceName}"
    $spnList    += $instanceSPN

# Add port SPN if specified
    if ($Port) {
        $portSPN = "MSSQLSvc/${fqdn}:${Port}"
        $spnList += $portSPN
    }

# Process SPNs
    if ($PSCmdlet.ParameterSetName -eq 'RemoveSPN') {

        Write-Host "Removing SPNs..." -ForegroundColor Cyan
        Write-Host "----------------" -ForegroundColor Cyan

        $successCount = 0
        foreach ($spn in $spnList) {
            if (Add-RemoveSPN -SPN $spn -ServiceAccount $accountInfo.FullName -Remove) {
                $successCount++
            }
        }

        Write-Host "`nRemoved $successCount of $($spnList.Count) SPNs" -ForegroundColor Cyan

    } else {

        Write-Host "Setting SPNs..." -ForegroundColor Cyan
        Write-Host "---------------" -ForegroundColor Cyan

        $successCount = 0
        foreach ($spn in $spnList) {
            if (Add-RemoveSPN -SPN $spn -ServiceAccount $accountInfo.FullName) {
                $successCount++
            }
        }

        Write-Host "`nSuccessfully set $successCount of $($spnList.Count) SPNs" -ForegroundColor Cyan
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

    Write-Host "`n=== Required AD Permissions ===" -ForegroundColor Yellow
    Write-Host "===============================" -ForegroundColor Yellow
    Write-Host "The service account '$($accountInfo.FullName)' needs the following permissions" -ForegroundColor White
    Write-Host "on the computer object '$fqdn' in Active Directory:" -ForegroundColor White
    Write-Host ""
    Write-Host "  - Read servicePrincipalName" -ForegroundColor Gray
    Write-Host "  - Write servicePrincipalName" -ForegroundColor Gray
    Write-Host "  - Validated write to servicePrincipalName" -ForegroundColor Gray
    Write-Host ""
    Write-Host "To set these permissions:" -ForegroundColor White
    Write-Host "  1. Open 'Active Directory Users and Computers'" -ForegroundColor Gray
    Write-Host "  2. Enable 'Advanced Features' in View menu" -ForegroundColor Gray
    Write-Host "  3. Navigate to computer object: $fqdn" -ForegroundColor Gray
    Write-Host "  4. Right-click -> Properties -> Security -> Advanced" -ForegroundColor Gray
    Write-Host "  5. Add -> Select Principal: $($accountInfo.FullName)" -ForegroundColor Gray
    Write-Host "  6. Set permissions as listed above" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Without these permissions, SQL Server cannot register/update SPNs dynamically." -ForegroundColor Yellow
}

Write-Host "`nOperation completed." -ForegroundColor Green
