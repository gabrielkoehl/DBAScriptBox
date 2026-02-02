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
.PARAMETER gmsa
    Switch to indicate account is a group managed service account
.EXAMPLE
    .\security_setSqlLocalSec.ps1 -ServiceAccount "DOMAIN\sql_agent_user" -ServiceType "agent"
    Sets required permissions for SQL Server Agent service account
.EXAMPLE
    .\security_setSqlLocalSec.ps1 -ServiceAccount "sql_engine_gmsa$" -ServiceType "engine" -gmsa
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
    Disclaimer: This script is provided "as is" without warranty of any kind.
                Use at your own risk. The author assumes no responsibility for
                any damages or issues that may arise from using this script.

    REQUIREMENTS:
    - Run as Administrator
    - ActiveDirectory PowerShell module (for AD account validation)
    - Windows Server or Windows 10/11 Pro/Enterprise
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
    [switch]    $gmsa
)

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
            $accountObj = Get-ADServiceAccount -Identity $Account.TrimEnd('$') -ErrorAction Stop
        } else {
            $accountObj = Get-ADUser -Identity $Account -ErrorAction Stop
        }

        if ($null -ne $accountObj) {
            $result.Found       = $true
            $result.SID         = $accountObj.SID.Value
            $domain             = (Get-ADDomain).NetBIOSName
        }

    } catch {

        Write-Host "Error: Account $Account not found in Active Directory." -ForegroundColor Red
        Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red

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
        $exportResult = secedit /export /cfg $secpolFile /areas USER_RIGHTS /quiet 2>&1

        if ($LASTEXITCODE -ne 0) {
            throw "secedit export failed: $exportResult"
        }

        $secpolContent = Get-Content $secpolFile -Raw -Encoding UTF-16LE

        foreach ($right in $Rights) {
            Write-Host "`n[$right] " -NoNewline -ForegroundColor Cyan

            $valueToUse     = "*$SID"
            $escapedValue   = [regex]::Escape($valueToUse)
            $rightPattern   = "(?m)^$right\s*=\s*(.*?)$"

            if ($secpolContent -match $rightPattern) {

                $currentValue = $matches[1].Trim()

                if ($Remove) {
                    Write-Host "Removing permission..." -NoNewline

                    if ($currentValue -match $escapedValue) {

                        # Remove using array-based approach for reliability
                        $entries        = $currentValue -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne $valueToUse }
                        $newValue       = $entries -join ','
                        $secpolContent  = $secpolContent -replace $rightPattern, "$right = $newValue"
                        Write-Host "OK" -ForegroundColor Green

                    } else {

                        Write-Host "Account not found" -ForegroundColor Yellow

                    }

                } else {

                    if ($currentValue -match $escapedValue) {
                        Write-Host "Permission already exists" -ForegroundColor Green
                    } else {
                        Write-Host "Adding permission..." -NoNewline

                        $newValue       = if ($currentValue) { "$valueToUse,$currentValue" } else { $valueToUse }
                        $secpolContent  = $secpolContent -replace $rightPattern, "$right = $newValue"
                        Write-Host "OK" -ForegroundColor Green
                    }

                }

            } else {

                if (-not $Remove) {

                    Write-Host "Right not configured, creating new..." -NoNewline

                    $secpolContent = $secpolContent -replace '(\[Privilege Rights\])', "`$1`r`n$right = $valueToUse"
                    Write-Host "OK" -ForegroundColor Green

                } else {

                    Write-Host "Right not configured, no action needed" -ForegroundColor Yellow

                }
            }
        }

        $secpolContent | Set-Content $newSecpolFile -Encoding UTF-16LE

        Write-Host "`nApplying security policies..." -ForegroundColor Cyan

        $dbFile         = Join-Path $env:TEMP "secedit_$([guid]::NewGuid().ToString()).sdb"
        $applyResult    = secedit /configure /db $dbFile /cfg $newSecpolFile /areas USER_RIGHTS /quiet 2>&1

        if ($LASTEXITCODE -ne 0) {
            throw "secedit configure failed: $applyResult"
        }


    } catch {

        Write-Host "`nError setting rights: $($_.Exception.Message)" -ForegroundColor Red
        throw

    } finally {

        Remove-Item $secpolFile     -Force -ErrorAction SilentlyContinue
        Remove-Item $newSecpolFile  -Force -ErrorAction SilentlyContinue
        Remove-Item $dbFile         -Force -ErrorAction SilentlyContinue

    }
}

function Show-CurrentRights {
    param (
        [string]$SID,
        [array]$RequiredRights
    )

    $secpolFile = Join-Path $env:TEMP "secpol_status_$([guid]::NewGuid().ToString()).cfg"

    try {

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
            } else {
                $status = "MISSING"
                $color  = "Red"
            }

            Write-Host " " -NoNewline
            Write-Host ("{0,-30}" -f $right) -NoNewline
            Write-Host ("{0,-10}" -f $status) -ForegroundColor $color

        }

    } finally {

        Remove-Item $secpolFile -Force -ErrorAction SilentlyContinue

    }
}

# Main execution
Write-Host "SQL Service Account Rights Assignment" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan

$accountInfo = Get-AccountInfo -Account $ServiceAccount -IsGMSA:$gmsa

if ($accountInfo.Found) {

    Write-Host "`nServiceType: $ServiceType" -ForegroundColor Cyan
    Write-Host "ServiceAccount: $($accountInfo.Name)" -ForegroundColor Cyan
    Write-Host "SID: $($accountInfo.SID)" -ForegroundColor Cyan

    Set-UserRights -Account $accountInfo.Name -SID $accountInfo.SID -Rights $rights[$ServiceType] -Remove:$Remove

    Write-Host "`nCurrent rights status for $($accountInfo.Name):`n" -ForegroundColor Cyan
    Show-CurrentRights -SID $accountInfo.SID -RequiredRights $rights[$ServiceType]

} else {

    Write-Host "Operation aborted because account $ServiceAccount does not exist." -ForegroundColor Red
    exit 1

}

Write-Host "`nOperation completed." -ForegroundColor Green
