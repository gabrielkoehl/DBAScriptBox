<#
.SYNOPSIS
    Sets required local security policy rights for SQL Server service accounts
.DESCRIPTION
    Configures Windows User Rights Assignment policies for SQL Server Engine, Agent, SSIS,
    and SSAS service accounts. Supports both regular AD accounts and group managed service
    accounts (gMSA). Can add or remove permissions based on service type.
.PARAMETER ServiceAccount
    AD account name (e.g., "DOMAIN\sql_svc" or "sql_gmsa$")
.PARAMETER ServiceType
    Type of SQL Server service: agent, engine, ssis, ssis_pxy, ssas
.PARAMETER Remove
    Switch to remove permissions instead of adding them
.PARAMETER IsGMSA
    Switch to indicate account is a group managed service account
.PARAMETER LogPath
    Optional path to log file for detailed operation logging
    If not specified, only console output is generated
    Example: "C:\Temp\SqlSecurity_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
.EXAMPLE
    .\security_setSqlLocalSec.ps1 -ServiceAccount "DOMAIN\sql_agent_user" -ServiceType "agent"
    Sets required permissions for SQL Server Agent service account
.EXAMPLE
    .\security_setSqlLocalSec.ps1 -ServiceAccount "sql_engine_gmsa$" -ServiceType "engine" -IsGMSA
    Sets required permissions for gMSA running SQL Server Engine
.EXAMPLE
    .\security_setSqlLocalSec.ps1 -ServiceAccount "DOMAIN\sql_agent_user" -ServiceType "agent" -Remove
    Removes previously assigned permissions
.NOTES
    File Name  : security_setSqlLocalSec.ps1
    Author     : Gabriel Köhl
    Website    : https://dbavonnebenan.de
    GitHub     : https://github.com/gabrielkoehl/DBAScriptBox
    HISTORY
    - 02.06.2025 - Init
    - 30.01.2026 - Minor Updates, improved error handling
    - 05.02.2026 - Added logging functionality and examples

    Disclaimer: This script is provided "as is" without warranty of any kind.
                Use at your own risk. The author assumes no responsibility for
                any damages or issues that may arise from using this script.

    REQUIREMENTS:
    - Run as Administrator
    - ActiveDirectory PowerShell module (for AD account validation)
    - Windows Server

#>

#Requires -RunAsAdministrator
#Requires -Modules ActiveDirectory

param (
    [Parameter(Mandatory=$true)]
    [string]    $ServiceAccount,

    [Parameter(Mandatory=$true)]
    [ValidateSet("agent", "engine", "ssis", "ssis_pxy", "ssas")]
    [string]    $ServiceType,

    [switch]    $Remove,
    [switch]    $IsGMSA,
    [string]    $LogPath
)

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

#endregion

# Define rights per service type
$rights = @{
    engine   = @("SeBatchLogonRight","SeServiceLogonRight","SeLockMemoryPrivilege","SeManageVolumePrivilege","SeAssignPrimaryTokenPrivilege","SeIncreaseQuotaPrivilege","SeChangeNotifyPrivilege")
    agent    = @("SeBatchLogonRight","SeServiceLogonRight","SeAssignPrimaryTokenPrivilege","SeIncreaseQuotaPrivilege","SeChangeNotifyPrivilege")
    ssis     = @("SeBatchLogonRight","SeServiceLogonRight","SeImpersonatePrivilege","SeChangeNotifyPrivilege")
    ssis_pxy = @("SeNetworkLogonRight")
    ssas     = @()
}

function Get-AccountInfo {
    param (
        [string]$Account,
        [switch]$IsGMSA
    )

    $result = @{
        Name    = $Account
        SID     = $null
        Found   = $false
    }

    try {

        if ($IsGMSA) {

            Write-Log "Searching for gMSA account: $Account"
            $accountObj = Get-ADServiceAccount -Identity $Account.TrimEnd('$') -ErrorAction Stop

        } else {

            Write-Log "Searching for AD user account: $Account"
            $accountObj = Get-ADUser -Identity $Account -ErrorAction Stop

        }

        if ($null -ne $accountObj) {

            $result.Found       = $true
            $result.SID         = $accountObj.SID.Value
            $domain             = (Get-ADDomain).NetBIOSName
            Write-Log "Account found - SID: $($result.SID)"

        }

    } catch {

        Write-Host "Error: Account $Account not found in Active Directory." -ForegroundColor Red
        Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "Account not found: $Account - $($_.Exception.Message)" -Level "ERROR"

    }

    return $result
}

function Set-UserRights {
    param (
        [string]    $Account,
        [string]    $SID,
        [array]     $Rights,
        [switch]    $Remove
    )

    $secpolFile     = Join-Path $env:TEMP "secpol_$([guid]::NewGuid().ToString()).cfg"
    $newSecpolFile  = Join-Path $env:TEMP "new_secpol_$([guid]::NewGuid().ToString()).cfg"
    $dbFile         = $null

    try {

        Write-Host "Exporting security policies..." -ForegroundColor Cyan
        Write-Log "Exporting security policies to: $secpolFile"
        $exportResult = secedit /export /cfg $secpolFile /areas USER_RIGHTS /quiet 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Log "secedit export failed: $exportResult" -Level "ERROR"
            throw "secedit export failed: $exportResult"
        }

        $secpolContent = Get-Content $secpolFile -Raw -Encoding UTF-16LE
        Write-Log "Security policy exported successfully"

        foreach ($right in $Rights) {

            Write-Host "`n[$right] " -NoNewline -ForegroundColor Cyan

            $valueToUse     = "*$SID"
            $escapedValue   = [regex]::Escape($valueToUse)
            $rightPattern   = "(?m)^$right\s*=\s*(.*?)$"

            if ($secpolContent -match $rightPattern) {

                $currentValue = $matches[1].Trim()

                if ($Remove) {

                    Write-Host "Removing permission..." -NoNewline
                    Write-Log "Attempting to remove $right for SID: $SID"

                    if ($currentValue -match $escapedValue) {

                        # Remove using array-based approach for reliability
                        $entries        = $currentValue -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne $valueToUse }
                        $newValue       = $entries -join ','
                        $secpolContent  = $secpolContent -replace $rightPattern, "$right = $newValue"
                        Write-Host "OK" -ForegroundColor Green
                        Write-Log "Permission removed: $right"

                    } else {

                        Write-Host "Account not found" -ForegroundColor Yellow
                        Write-Log "Account not found in $right - no action needed"

                    }

                } else {

                    if ($currentValue -match $escapedValue) {
                        Write-Host "Permission already exists" -ForegroundColor Green
                        Write-Log "Permission already exists: $right"
                    } else {
                        Write-Host "Adding permission..." -NoNewline
                        Write-Log "Adding permission: $right for SID: $SID"

                        $newValue       = if ($currentValue) { "$valueToUse,$currentValue" } else { $valueToUse }
                        $secpolContent  = $secpolContent -replace $rightPattern, "$right = $newValue"
                        Write-Host "OK" -ForegroundColor Green
                        Write-Log "Permission added: $right"
                    }

                }

            } else {

                if (-not $Remove) {

                    Write-Host "Right not configured, creating new..." -NoNewline
                    Write-Log "Creating new right: $right for SID: $SID"

                    $secpolContent = $secpolContent -replace '(\[Privilege Rights\])', "`$1`r`n$right = $valueToUse"
                    Write-Host "OK" -ForegroundColor Green
                    Write-Log "New right created: $right"

                } else {

                    Write-Host "Right not configured, no action needed" -ForegroundColor Yellow
                    Write-Log "Right not configured: $right - no action needed"

                }
            }

        }

        $secpolContent | Set-Content $newSecpolFile -Encoding UTF-16LE
        Write-Log "Writing modified security policy to: $newSecpolFile"

        Write-Host "`nApplying security policies..." -ForegroundColor Cyan
        Write-Log "Applying security policies via secedit"

        $dbFile         = Join-Path $env:TEMP "secedit_$([guid]::NewGuid().ToString()).sdb"
        $applyResult    = secedit /configure /db $dbFile /cfg $newSecpolFile /areas USER_RIGHTS /quiet 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Log "secedit configure failed: $applyResult" -Level "ERROR"
            throw "secedit configure failed: $applyResult"
        }

        Write-Log "Security policies applied successfully"

    } catch {

        Write-Host "`nError setting rights: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "Error setting rights: $($_.Exception.Message)" -Level "ERROR"
        throw

    } finally {

        Remove-Item $secpolFile     -Force -ErrorAction SilentlyContinue
        Remove-Item $newSecpolFile  -Force -ErrorAction SilentlyContinue
        Remove-Item $dbFile         -Force -ErrorAction SilentlyContinue
        Write-Log "Temporary files cleaned up"

    }
}

function Show-CurrentRights {
    param (
        [string]$SID,
        [array]$RequiredRights
    )

    $secpolFile = Join-Path $env:TEMP "secpol_status_$([guid]::NewGuid().ToString()).cfg"

    try {

        Write-Log "Checking current rights status for SID: $SID"
        $null       = secedit /export /cfg $secpolFile /areas USER_RIGHTS /quiet
        $content    = Get-Content $secpolFile -Encoding UTF-16LE

        Write-Host "`n Right                          Status    " -ForegroundColor Blue
        Write-Host " ----------------------------------------    " -ForegroundColor Blue

        $sidWithAsterisk = "*$SID"

        foreach ($right in $RequiredRights) {

            $rightLine = $content | Where-Object { $_ -match "^$right\s*=" }

            if ($rightLine -and $rightLine -match [regex]::Escape($sidWithAsterisk)) {

                $status = "PRESENT"
                $color  = "Green"
                Write-Log "Right status: $right - PRESENT"

            } else {

                $status = "MISSING"
                $color  = "Red"
                Write-Log "Right status: $right - MISSING"

            }

            Write-Host " " -NoNewline
            Write-Host ("{0,-30}" -f $right) -NoNewline
            Write-Host ("{0,-10}" -f $status) -ForegroundColor $color

        }

    } finally {

        Remove-Item $secpolFile -Force -ErrorAction SilentlyContinue

    }
}

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
    Add-Content -Path $LogPath -Value "ServiceAccount: $ServiceAccount"
    Add-Content -Path $LogPath -Value "ServiceType: $ServiceType"
    Add-Content -Path $LogPath -Value "Remove: $($Remove.IsPresent)"
    Add-Content -Path $LogPath -Value "IsGMSA: $($IsGMSA.IsPresent)"
    Add-Content -Path $LogPath -Value $separator

}

# Main execution
Write-Host "SQL Service Account Rights Assignment" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Log "=== SQL Service Account Rights Assignment ==="
Write-Log "Script parameters: ServiceAccount=$ServiceAccount, ServiceType=$ServiceType, Remove=$($Remove.IsPresent), IsGMSA=$($IsGMSA.IsPresent)"

$accountInfo = Get-AccountInfo -Account $ServiceAccount -IsGMSA:$IsGMSA

if ($accountInfo.Found) {

    Write-Host "`nServiceType: $ServiceType" -ForegroundColor Cyan
    Write-Host "ServiceAccount: $($accountInfo.Name)" -ForegroundColor Cyan
    Write-Host "SID: $($accountInfo.SID)" -ForegroundColor Cyan
    Write-Log "Account validated - Name: $($accountInfo.Name), SID: $($accountInfo.SID)"

    Set-UserRights -Account $accountInfo.Name -SID $accountInfo.SID -Rights $rights[$ServiceType] -Remove:$Remove

    Write-Host "`nCurrent rights status for $($accountInfo.Name):`n" -ForegroundColor Cyan
    Show-CurrentRights -SID $accountInfo.SID -RequiredRights $rights[$ServiceType]

    Write-Host "`nOperation completed." -ForegroundColor Green
    Write-Log "=== Operation completed successfully ==="

} else {

    Write-Host "Operation aborted because account $ServiceAccount does not exist." -ForegroundColor Red
    Write-Log "=== Operation aborted - Account not found ===" -Level "ERROR"
    exit 1

}

if ($LogPath) {
    $separator = "=" * 80
    Add-Content -Path $LogPath -Value $separator
    Add-Content -Path $LogPath -Value "Execution finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Add-Content -Path $LogPath -Value $separator
    Write-Host "`nLog file: $LogPath" -ForegroundColor Cyan
}

#endregion


<# EXAMPLES

    # ===== EXAMPLE 1: Set Engine Permissions for gMSA =====
    .\security_setSqlLocalSec.ps1 `
        -ServiceAccount "g-LAB22A-oltp$" `
        -ServiceType "engine" `
        -IsGMSA `
        -LogPath "C:\Temp\LAB22A_Engine_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

    # ===== EXAMPLE 2: Set Agent Permissions for gMSA =====
    .\security_setSqlLocalSec.ps1 `
        -ServiceAccount "g-LAB22A-agnt$" `
        -ServiceType "agent" `
        -IsGMSA `
        -LogPath "C:\Temp\LAB22A_Agent_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

    # ===== EXAMPLE 3: Remove Permissions =====
    .\security_setSqlLocalSec.ps1 `
        -ServiceAccount "g-LAB22A-oltp$" `
        -ServiceType "engine" `
        -IsGMSA `
        -Remove `
        -LogPath "C:\Temp\LAB22A_Remove_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

#>