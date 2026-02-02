<#
.SYNOPSIS
    Creates and configures Group Managed Service Accounts (gMSA) for SQL Server services
.DESCRIPTION
    Automates the creation of gMSA accounts in Active Directory including:
    - Creating security groups for server access control (optional)
    - Creating gMSA accounts for SQL Server Engine and/or Agent
    - Installing gMSA accounts on local server (optional, requires restart)
    - Removing gMSA accounts from AD
    - Logging all operations to file (optional)
    
    IMPORTANT: Install operations require elevated privileges and must be run separately
    from account creation as they may require a system restart.
    
    NOTE: Uninstall-ADServiceAccount does not reliably remove gMSA from local cache due to 
    Windows LSA limitations. Function removed
.PARAMETER EngineAccountName
    Name for SQL Server Engine gMSA account (without $ suffix)
.PARAMETER AgentAccountName
    Name for SQL Server Agent gMSA account (without $ suffix)
.PARAMETER SecurityGroupName
    Name of AD security group that contains allowed servers (without $ suffix)
.PARAMETER ServerNames
    Array of server names for security group (without $ suffix). Only used if creating new group.
.PARAMETER DnsDomain
    DNS domain for the gMSA accounts (default: current AD domain)
.PARAMETER PasswordIntervalDays
    Password rotation interval in days (default: 30, max: 365)
.PARAMETER CreateSecurityGroup
    Switch to create new security group with specified servers
.PARAMETER SecurityGroupOU
    Optional OU path for security group (e.g., "OU=ServiceAccounts,DC=domain,DC=com")
.PARAMETER SecurityGroupDescription
    Optional description for security group (default: "gMSA security group for SQL Server computers")
.PARAMETER EngineAccountDescription
    Optional description for Engine gMSA account (default: "SQL Server gMSA account for <AccountName>")
.PARAMETER AgentAccountDescription
    Optional description for Agent gMSA account (default: "SQL Server gMSA account for <AccountName>")
.PARAMETER InstallLocally
    Switch to install created gMSA accounts on local server (REQUIRES ADMIN RIGHTS, SEPARATE EXECUTION)
.PARAMETER InitializeKDS
    Switch to initialize KDS Root Key (only needed once per AD forest)
.PARAMETER DropGmsa
    Switch to remove gMSA accounts from Active Directory
.PARAMETER LogPath
    Optional path to log file. If not specified, only console output is generated.
.EXAMPLE
    .\security_createGMSA.ps1 -EngineAccountName "g-engine-dev22a" -AgentAccountName "g-agent-dev22a" -SecurityGroupName "SQL_CL_DEV22A"
    Creates gMSA accounts using existing security group
.EXAMPLE
    .\security_createGMSA.ps1 -EngineAccountName "g-engine-dev22a" -SecurityGroupName "SQL_CL_DEV22A" -ServerNames "DEV-NODE1","DEV-NODE2" -CreateSecurityGroup
    Creates Engine gMSA and new security group with specified servers
.EXAMPLE
    .\security_createGMSA.ps1 -InstallLocally -EngineAccountName "g-engine-dev22a" -AgentAccountName "g-agent-dev22a"
    Installs existing gMSA accounts on local server (requires restart, admin rights required)
.EXAMPLE
    .\security_createGMSA.ps1 -DropGmsa -EngineAccountName "g-engine-dev22a" -AgentAccountName "g-agent-dev22a" -LogPath "C:\Logs\gMSA_Remove.log"
    Removes gMSA accounts from Active Directory
.EXAMPLE
    .\security_createGMSA.ps1 -InitializeKDS -LogPath "C:\Logs\KDS_Init.log"
    Initializes KDS Root Key and logs operation to file
.NOTES
    File Name  : security_createGMSA.ps1
    Author     : Gabriel Köhl
    Website    : https://dbavonnebenan.de
    GitHub     : https://github.com/gabrielkoehl/DBAScriptBox
    HISTORY
    - 25.05.2024 - Init
    - 30.01.2026 - Updated with different functions
    Disclaimer: This script is provided "as is" without warranty of any kind.
                Use at your own risk. The author assumes no responsibility for
                any damages or issues that may arise from using this script.

    REQUIREMENTS:
    - Run as Domain Administrator or delegated permissions for account creation
    - Local Administrator rights ONLY for -InstallLocally operation
    - ActiveDirectory PowerShell module
    - KDS Root Key must be initialized (use -InitializeKDS once per forest)
    - For production: Wait 10 hours after KDS initialization
    - For testing: Use Add-KdsRootKey -EffectiveTime (Get-Date).AddHours(-10)
    
    ADMIN RIGHTS:
    - Account creation/removal: Domain admin or delegated AD permissions
    - Install locally: Local administrator rights required
    - Install operations must be run separately and may require restart
#>

[CmdletBinding(DefaultParameterSetName='CreateAccounts')]
param (
    [Parameter(ParameterSetName='CreateAccounts')]
    [Parameter(ParameterSetName='DropAccounts')]
    [Parameter(ParameterSetName='InstallOnly')]
    [string]    $EngineAccountName,

    [Parameter(ParameterSetName='CreateAccounts')]
    [Parameter(ParameterSetName='DropAccounts')]
    [Parameter(ParameterSetName='InstallOnly')]
    [string]    $AgentAccountName,

    [Parameter(Mandatory=$true, ParameterSetName='CreateAccounts')]
    [string]    $SecurityGroupName,

    [Parameter(ParameterSetName='CreateAccounts')]
    [string[]]  $ServerNames,

    [Parameter(ParameterSetName='CreateAccounts')]
    [string]    $DnsDomain,

    [Parameter(ParameterSetName='CreateAccounts')]
    [ValidateRange(1,365)]
    [int]       $PasswordIntervalDays = 30,

    [Parameter(ParameterSetName='CreateAccounts')]
    [switch]    $CreateSecurityGroup,

    [Parameter(ParameterSetName='CreateAccounts')]
    [string]    $SecurityGroupOU,

    [Parameter(ParameterSetName='CreateAccounts')]
    [string]    $SecurityGroupDescription,

    [Parameter(ParameterSetName='CreateAccounts')]
    [string]    $EngineAccountDescription,

    [Parameter(ParameterSetName='CreateAccounts')]
    [string]    $AgentAccountDescription,

    [Parameter(Mandatory=$true, ParameterSetName='InstallOnly')]
    [switch]    $InstallLocally,

    [Parameter(Mandatory=$true, ParameterSetName='InitKDS')]
    [switch]    $InitializeKDS,

    [Parameter(Mandatory=$true, ParameterSetName='DropAccounts')]
    [switch]    $DropGmsa,

    [Parameter(ParameterSetName='CreateAccounts')]
    [Parameter(ParameterSetName='DropAccounts')]
    [Parameter(ParameterSetName='InitKDS')]
    [Parameter(ParameterSetName='InstallOnly')]
    [string]    $LogPath
)

#Requires -Modules ActiveDirectory

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

function Initialize-KDSRootKey {

    try {

        Write-Host "Checking existing KDS Root Keys..." -ForegroundColor Cyan
        Write-Log "Checking existing KDS Root Keys"
        
        $existingKeys = Get-KdsRootKey

        if ($existingKeys) {
            Write-Host "KDS Root Key already exists:" -ForegroundColor Green
            Write-Log "KDS Root Key already exists"
            $existingKeys | Select-Object EffectiveTime, CreationTime, DomainController | Format-Table
            return $true
        }

        Write-Host "Creating KDS Root Key..." -ForegroundColor Cyan
        Write-Log "Creating KDS Root Key"
        Write-Warning "In production environments, there's a 10-hour replication delay."
        Write-Warning "For testing, use: Add-KdsRootKey -EffectiveTime (Get-Date).AddHours(-10)"

        $key = Add-KdsRootKey -EffectiveImmediately
        Write-Host "KDS Root Key created successfully. KeyId: $($key.KeyId)" -ForegroundColor Green
        Write-Log "KDS Root Key created successfully. KeyId: $($key.KeyId)"

        return $true

    } catch {

        Write-Host "Error initializing KDS Root Key: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "Error initializing KDS Root Key: $($_.Exception.Message)" -Level "ERROR"
        return $false

    }
}

function New-gMSASecurityGroup {
    param (
        [string]    $GroupName,
        [string[]]  $Members,
        [string]    $OU,
        [string]    $Description
    )

    try {

        $existingGroup = Get-ADGroup -Filter "Name -eq '$GroupName'" -ErrorAction SilentlyContinue

        if ($existingGroup) {
            Write-Host "Security group '$GroupName' already exists." -ForegroundColor Yellow
            Write-Log "Security group '$GroupName' already exists" -Level "WARN"
            return $true
        }

        Write-Host "Creating security group '$GroupName'..." -ForegroundColor Cyan
        Write-Log "Creating security group '$GroupName' with Description: '$Description', OU: '$OU'"

        $defaultDescription = "gMSA security group for SQL Server computers"
        $groupDescription   = if ($Description) { $Description } else { $defaultDescription }

        $newGroupParams = @{
            Name            = $GroupName
            Description     = $groupDescription
            GroupCategory   = 'Security'
            GroupScope      = 'Global'
            ErrorAction     = 'Stop'
        }

        if ($OU) {
            $newGroupParams['Path'] = $OU
        }

        New-ADGroup @newGroupParams
        Write-Host "Security group created successfully." -ForegroundColor Green
        Write-Log "Security group '$GroupName' created successfully"

        if ($Members -and $Members.Count -gt 0) {

            Write-Host "Adding server members to group..." -ForegroundColor Cyan
            Write-Log "Adding members to group: $($Members -join ', ')"

            foreach ($member in $Members) {
                $computerName = if ($member.EndsWith('$')) { $member } else { "$member$" }

                try {
                    Add-ADGroupMember -Identity $GroupName -Members $computerName -ErrorAction Stop
                    Write-Host "  Added: $computerName" -ForegroundColor Green
                    Write-Log "Added member: $computerName"
                }
                catch {
                    Write-Host "  Failed to add $computerName : $($_.Exception.Message)" -ForegroundColor Red
                    Write-Log "Failed to add member $computerName : $($_.Exception.Message)" -Level "ERROR"
                }
            }

        }

        Write-Host "`nCurrent group members:" -ForegroundColor Cyan
        $groupMembers = Get-ADGroupMember -Identity $GroupName

        if ($groupMembers) {
            foreach ($m in $groupMembers) {
                Write-Host "  $($m.Name) ($($m.ObjectClass))" -ForegroundColor White
            }

        } else {

            Write-Host "  No members" -ForegroundColor Yellow

        }

        return $true

    } catch {

        Write-Host "Error creating security group: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "Error creating security group: $($_.Exception.Message)" -Level "ERROR"
        return $false

    }
}

function Test-SecurityGroup {
    param (
        [string]$GroupName
    )

    try {

        $group = Get-ADGroup -Filter "Name -eq '$GroupName'" -ErrorAction Stop

        if ($group) {

            Write-Host "Security group '$GroupName' found." -ForegroundColor Green
            Write-Log "Security group '$GroupName' validated"

            $members = Get-ADGroupMember -Identity $GroupName
            if ($members) {

                Write-Host "Group members:" -ForegroundColor Cyan
                foreach ($member in $members) {
                    Write-Host "  $($member.Name) ($($member.ObjectClass))" -ForegroundColor White
                }

            } else {

                Write-Host "Group has no members." -ForegroundColor Yellow
                Write-Log "Security group '$GroupName' has no members" -Level "WARN"

            }

            return $true

        }

        return $false

    } catch {

        Write-Host "Security group '$GroupName' not found." -ForegroundColor Red
        Write-Log "Security group '$GroupName' not found" -Level "ERROR"
        return $false

    }
}

function New-gMSAServiceAccount {
    param (
        [string]$AccountName,
        [string]$DnsHostName,
        [string]$PrincipalsGroup,
        [int]$PasswordInterval,
        [string]$Description
    )

    try {

        $AccountName        = $AccountName.TrimEnd('$')
        $existingAccount    = Get-ADServiceAccount -Filter "Name -eq '$AccountName'" -ErrorAction SilentlyContinue

        if ($existingAccount) {

            Write-Host "gMSA account '$AccountName' already exists." -ForegroundColor Yellow
            Write-Log "gMSA account '$AccountName' already exists" -Level "WARN"
            $existingAccount | Format-List Name, Enabled, DNSHostName, PrincipalsAllowedToRetrieveManagedPassword
            return $true

        }

        Write-Host "Creating gMSA account '$AccountName'..." -ForegroundColor Cyan
        
        $defaultDescription = "SQL Server gMSA account for $AccountName"
        $accountDescription = if ($Description) { $Description } else { $defaultDescription }
        
        Write-Log "Creating gMSA account '$AccountName' with Description: '$accountDescription', DNS: '$DnsHostName', Group: '$PrincipalsGroup', PasswordInterval: $PasswordInterval days"

        New-ADServiceAccount -Name $AccountName `
                             -PrincipalsAllowedToRetrieveManagedPassword $PrincipalsGroup `
                             -Enabled $true `
                             -DNSHostName $DnsHostName `
                             -SamAccountName $AccountName `
                             -ManagedPasswordIntervalInDays $PasswordInterval `
                             -Description $accountDescription `
                             -ErrorAction Stop

        Write-Host "gMSA account '$AccountName' created successfully." -ForegroundColor Green
        Write-Log "gMSA account '$AccountName' created successfully"
        Get-ADServiceAccount -Identity $AccountName | Format-List Name, Enabled, DNSHostName, SamAccountName

        return $true

    } catch {

        Write-Host "Error creating gMSA account '$AccountName': $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "Error creating gMSA account '$AccountName': $($_.Exception.Message)" -Level "ERROR"
        return $false

    }
}

function Install-gMSALocally {
    param (
        [string[]]$AccountNames
    )

    try {

        Write-Host "`nInstalling gMSA accounts on local server..." -ForegroundColor Cyan
        Write-Log "Installing gMSA accounts locally: $($AccountNames -join ', ')"

        $installResults = @()

        foreach ($accountName in $AccountNames) {

            $accountName = $accountName.TrimEnd('$')
            Write-Host "  Processing: $accountName..." -NoNewline

            # Check if account exists in AD
            try {

                $adAccount = Get-ADServiceAccount -Identity $accountName -ErrorAction Stop

            } catch {

                Write-Host " ERROR (not found in AD)" -ForegroundColor Red
                Write-Log "gMSA account '$accountName' not found in AD" -Level "ERROR"
                $installResults += [PSCustomObject]@{
                    Account = $accountName
                    Status  = "NotFoundInAD"
                }

                continue

            }

            # Check if already installed
            $isInstalled = $false

            try {

                $testResult  = Test-ADServiceAccount -Identity $accountName -ErrorAction Stop
                $isInstalled = ($testResult -eq $true)

            } catch {

                $isInstalled = $false

            }

            if ($isInstalled) {

                Write-Host " Already installed" -ForegroundColor Yellow
                Write-Log "gMSA account '$accountName' already installed locally" -Level "WARN"
                $installResults += [PSCustomObject]@{
                    Account = $accountName
                    Status  = "AlreadyInstalled"
                }

                continue

            }

            # Install account
            try {

                Install-ADServiceAccount -Identity $accountName -Force -ErrorAction Stop
                
                # Verify installation
                Start-Sleep -Seconds 1
                $verifyInstalled = $false

                try {

                    $verifyResult    = Test-ADServiceAccount -Identity $accountName -ErrorAction Stop
                    $verifyInstalled = ($verifyResult -eq $true)

                }
                catch {
                    $verifyInstalled = $false
                }
                
                if ($verifyInstalled) {

                    Write-Host " OK" -ForegroundColor Green
                    Write-Log "gMSA account '$accountName' installed locally"

                    $installResults += [PSCustomObject]@{
                        Account = $accountName
                        Status  = "Success"
                    }

                } else {

                    Write-Host " FAILED (verification failed)" -ForegroundColor Red
                    Write-Log "gMSA account '$accountName' installation verification failed" -Level "ERROR"
                    $installResults += [PSCustomObject]@{
                        Account = $accountName
                        Status  = "FailedVerification"
                    }

                }

            } catch {

                $errorMsg = $_.Exception.Message
                Write-Host " ERROR" -ForegroundColor Red
                Write-Host "    $errorMsg" -ForegroundColor Red
                Write-Log "Error installing gMSA account '$accountName': $errorMsg" -Level "ERROR"
                
                $installResults += [PSCustomObject]@{
                    Account = $accountName
                    Status  = "Failed"
                    Error   = $errorMsg
                }

            }
        }

        # Summary
        Write-Host "`n=== Installation Summary ===" -ForegroundColor Cyan

        foreach ($result in $installResults) {

            $color = switch ($result.Status) {
                "Success" { "Green" }
                "AlreadyInstalled" { "Yellow" }
                default { "Red" }
            }
            Write-Host "  $($result.Account): $($result.Status)" -ForegroundColor $color

        }

        $failedCount = ($installResults | Where-Object { $_.Status -like "Failed*" }).Count

        if ($failedCount -gt 0) {

            Write-Host "`nWARNING: $failedCount account(s) failed to install." -ForegroundColor Red
            Write-Log "Installation completed with $failedCount failure(s)" -Level "WARN"

        }

        Write-Host "`nIMPORTANT: A system restart may be required for changes to take effect." -ForegroundColor Yellow
        Write-Log "gMSA installation process completed"

        return ($failedCount -eq 0)

    } catch {

        Write-Host "Critical error during installation: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "Critical error during installation: $($_.Exception.Message)" -Level "ERROR"
        return $false

    }
}

function Remove-gMSAServiceAccount {
    param (
        [string[]]$AccountNames
    )

    $removedAccounts = @()

    foreach ($accountName in $AccountNames) {

        try {

            $accountName = $accountName.TrimEnd('$')
            $account = Get-ADServiceAccount -Filter "Name -eq '$accountName'" -ErrorAction SilentlyContinue
            
            if (-not $account) {
                Write-Host "gMSA account '$accountName' not found in AD." -ForegroundColor Yellow
                Write-Log "gMSA account '$accountName' not found for removal" -Level "WARN"
                continue
            }

            Write-Host "Processing gMSA account '$accountName'..." -ForegroundColor Cyan
            Write-Log "Removing gMSA account '$accountName' from AD"

            Write-Host "  Removing from AD..." -NoNewline
            Remove-ADServiceAccount -Identity $accountName -Confirm:$false -ErrorAction Stop
            Write-Host " OK" -ForegroundColor Green
            Write-Log "gMSA account '$accountName' removed from AD"
            
            $removedAccounts += $accountName

        } catch {

            Write-Host " Error: $($_.Exception.Message)" -ForegroundColor Red
            Write-Log "Error removing gMSA account '$accountName': $($_.Exception.Message)" -Level "ERROR"

        }
    }

    return $removedAccounts
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
    
    Write-Log "Script parameters: $($PSBoundParameters | Out-String)"

}

# Admin rights check for install operation
if ($PSCmdlet.ParameterSetName -eq 'InstallOnly') {

    if (-not (Test-AdminRights)) {
        Write-Host "ERROR: This operation requires local administrator rights." -ForegroundColor Red
        Write-Host "Please run PowerShell as Administrator and try again." -ForegroundColor Yellow
        Write-Log "Operation aborted: Missing admin rights" -Level "ERROR"
        exit 1
    }

    Write-Log "Admin rights verified"

}

# KDS Initialization
if ($PSCmdlet.ParameterSetName -eq 'InitKDS') {

    Write-Host "=== KDS Root Key Initialization ===" -ForegroundColor Cyan
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Log "=== KDS Root Key Initialization ==="

    $success = Initialize-KDSRootKey

    if ($success) {
        Write-Host "`nKDS Root Key setup completed. You can now create gMSA accounts." -ForegroundColor Green
        Write-Log "KDS Root Key setup completed successfully"
    } else {
        Write-Host "`nKDS Root Key setup failed." -ForegroundColor Red
        Write-Log "KDS Root Key setup failed" -Level "ERROR"
        exit 1
    }

    exit 0

}

# Install Only Operation
if ($PSCmdlet.ParameterSetName -eq 'InstallOnly') {

    Write-Host "=== gMSA Local Installation ===" -ForegroundColor Cyan
    Write-Host "===============================" -ForegroundColor Cyan
    Write-Log "=== gMSA Local Installation ==="

    if (-not $EngineAccountName -and -not $AgentAccountName) {

        Write-Host "Error: At least one account name must be specified." -ForegroundColor Red
        Write-Log "Error: No account names specified for installation" -Level "ERROR"
        exit 1

    }

    $accountsToInstall = @()
    if ($EngineAccountName) { $accountsToInstall += $EngineAccountName }
    if ($AgentAccountName)  { $accountsToInstall += $AgentAccountName }

    Write-Host "`nAccounts to install:" -ForegroundColor Cyan

    foreach ($acc in $accountsToInstall) {
        Write-Host "  - $acc" -ForegroundColor White
    }

    Write-Host ""

    $success = Install-gMSALocally -AccountNames $accountsToInstall

    if ($success) {
        Write-Host "`nOperation completed successfully." -ForegroundColor Green
        Write-Host "IMPORTANT: Restart the system if accounts were just created." -ForegroundColor Yellow
        Write-Log "Installation operation completed successfully"

    } else {

        Write-Host "`nOperation completed with errors. Check output above." -ForegroundColor Red
        Write-Log "Installation operation completed with errors" -Level "ERROR"
    }

    exit 0

}

# Drop Accounts Operation
if ($PSCmdlet.ParameterSetName -eq 'DropAccounts') {

    Write-Host "=== SQL Server gMSA Account Removal ===" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Log "=== SQL Server gMSA Account Removal ==="

    if (-not $EngineAccountName -and -not $AgentAccountName) {

        Write-Host "Error: At least one account name must be specified." -ForegroundColor Red
        Write-Log "Error: No account names specified for removal" -Level "ERROR"

        exit 1

    }

    $accountsToRemove = @()
    if ($EngineAccountName) { $accountsToRemove += $EngineAccountName }
    if ($AgentAccountName)  { $accountsToRemove += $AgentAccountName }

    Write-Host "`nAccounts to remove from AD:" -ForegroundColor Cyan

    foreach ($acc in $accountsToRemove) {
        Write-Host "  - $acc" -ForegroundColor White
    }

    Write-Host ""
    Write-Host "NOTE: Local gMSA cache (Install-ADServiceAccount) cannot be reliably removed" -ForegroundColor Yellow
    Write-Host "      due to Windows LSA limitations. This is harmless and does not affect AD removal." -ForegroundColor Yellow
    Write-Host ""

    $removedAccounts = Remove-gMSAServiceAccount -AccountNames $accountsToRemove

    Write-Host "`n=== Summary ===" -ForegroundColor Cyan
    if ($removedAccounts.Count -gt 0) {

        Write-Host "`nSuccessfully removed from AD:" -ForegroundColor Green
        Write-Log "Successfully removed accounts: $($removedAccounts -join ', ')"
        foreach ($account in $removedAccounts) {
            Write-Host "  - $account" -ForegroundColor Green
        }

    } else {

        Write-Host "No accounts were removed." -ForegroundColor Yellow
        Write-Log "No accounts were removed" -Level "WARN"

    }

    Write-Host "`nOperation completed." -ForegroundColor Green
    Write-Log "Operation completed"
    exit 0
    
}

# Create Accounts Workflow
Write-Log "=== SQL Server gMSA Account Creation ==="

if (-not $EngineAccountName -and -not $AgentAccountName) {

    Write-Host "Error: At least one account name (Engine or Agent) must be specified." -ForegroundColor Red
    Write-Log "Error: No account names specified" -Level "ERROR"
    exit 1

}

if ($CreateSecurityGroup -and (-not $ServerNames -or $ServerNames.Count -eq 0)) {

    Write-Host "Error: -ServerNames required when using -CreateSecurityGroup." -ForegroundColor Red
    Write-Log "Error: -ServerNames required when using -CreateSecurityGroup" -Level "ERROR"
    exit 1

}

if (-not $DnsDomain) {

    $DnsDomain = (Get-ADDomain).DNSRoot

}

Write-Host "=== SQL Server gMSA Account Creation ===" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

Write-Host "`nConfiguration:" -ForegroundColor Cyan
Write-Host "  Security Group: $SecurityGroupName" -ForegroundColor White
if ($EngineAccountName) { Write-Host "  Engine Account: $EngineAccountName" -ForegroundColor White }
if ($AgentAccountName) { Write-Host "  Agent Account:  $AgentAccountName" -ForegroundColor White }
Write-Host "  DNS Domain:     $DnsDomain" -ForegroundColor White
Write-Host "  Password Days:  $PasswordIntervalDays" -ForegroundColor White
if ($ServerNames) { Write-Host "  Servers:        $($ServerNames -join ', ')" -ForegroundColor White }
if ($SecurityGroupOU) { Write-Host "  Group OU:       $SecurityGroupOU" -ForegroundColor White }
Write-Host ""

Write-Host "Step 1: Validate/Create security group" -ForegroundColor Cyan
Write-Host "---------------------------------------" -ForegroundColor Cyan

if ($CreateSecurityGroup) {
    
    $groupSuccess = New-gMSASecurityGroup -GroupName $SecurityGroupName `
                                          -Members $ServerNames `
                                          -OU $SecurityGroupOU `
                                          -Description $SecurityGroupDescription

} else {

    $groupSuccess = Test-SecurityGroup -GroupName $SecurityGroupName

}

if (-not $groupSuccess) {

    Write-Host "`nSecurity group handling failed. Aborting." -ForegroundColor Red
    Write-Log "Security group handling failed. Aborting." -Level "ERROR"
    exit 1

}

$createdAccounts = @()

if ($EngineAccountName) {

    Write-Host "`nStep 2: Creating SQL Engine gMSA account" -ForegroundColor Cyan
    Write-Host "-----------------------------------------" -ForegroundColor Cyan

    $engineDns = "$($EngineAccountName.TrimEnd('$')).$DnsDomain"
    $engineSuccess = New-gMSAServiceAccount -AccountName $EngineAccountName `
                                            -DnsHostName $engineDns `
                                            -PrincipalsGroup $SecurityGroupName `
                                            -PasswordInterval $PasswordIntervalDays `
                                            -Description $EngineAccountDescription

    if ($engineSuccess) { $createdAccounts += $EngineAccountName }

}

if ($AgentAccountName) {

    $stepNumber = if ($EngineAccountName) { "3" } else { "2" }
    Write-Host "`nStep $stepNumber`: Creating SQL Agent gMSA account" -ForegroundColor Cyan
    Write-Host "-----------------------------------------" -ForegroundColor Cyan

    $agentDns = "$($AgentAccountName.TrimEnd('$')).$DnsDomain"
    $agentSuccess = New-gMSAServiceAccount -AccountName $AgentAccountName `
                                           -DnsHostName $agentDns `
                                           -PrincipalsGroup $SecurityGroupName `
                                           -PasswordInterval $PasswordIntervalDays `
                                           -Description $AgentAccountDescription

    if ($agentSuccess) { $createdAccounts += $AgentAccountName }

}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan

if ($createdAccounts.Count -gt 0) {

    Write-Host "`nSuccessfully processed accounts:" -ForegroundColor Green
    Write-Log "Successfully processed accounts: $($createdAccounts -join ', ')"
    foreach ($account in $createdAccounts) {
        Write-Host "  - $account" -ForegroundColor Green
    }

    Write-Host "`nNext steps:" -ForegroundColor Cyan
    Write-Host "  1. Install gMSA on target servers:" -ForegroundColor White
    Write-Host "     Run separately with admin rights:" -ForegroundColor Yellow
    $installCommand = ".\security_createGMSA.ps1 -InstallLocally"
    if ($EngineAccountName) { $installCommand += " -EngineAccountName '$EngineAccountName'" }
    if ($AgentAccountName) { $installCommand += " -AgentAccountName '$AgentAccountName'" }
    Write-Host "     $installCommand" -ForegroundColor Gray
    Write-Host "     Note: Restart system after installation if accounts were just created" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  2. Configure SQL Server services to use gMSA accounts" -ForegroundColor White
    Write-Host "     Format: DOMAIN\$account`$" -ForegroundColor Gray
    Write-Host "  3. Restart SQL Server services" -ForegroundColor White

} else {

    Write-Host "No accounts were created." -ForegroundColor Yellow
    Write-Log "No accounts were created" -Level "WARN"

}

Write-Host "`nOperation completed." -ForegroundColor Green
Write-Log "Operation completed successfully"

if ($LogPath) {

    Write-Host "`nLog file: $LogPath" -ForegroundColor Cyan
    
}

#endregion


<# EXAMPLES


    # ===== EXAMPLE 1: Minimal Account Creation (existing Security Group) =====
        .\security_createGMSA.ps1 `
            -EngineAccountName "g-engine-prod01" `
            -AgentAccountName "g-agent-prod01" `
            -SecurityGroupName "SQL_CL_PROD01"

    # ===== EXAMPLE 2: Engine Account only with new Security Group =====
        .\security_createGMSA.ps1 `
            -EngineAccountName "g-engine-dev22a" `
            -SecurityGroupName "SQL_CL_DEV22A" `
            -ServerNames "DEV-NODE1","DEV-NODE2" `
            -CreateSecurityGroup

    # ===== EXAMPLE 3: Complete creation with all options =====
        .\security_createGMSA.ps1 `
            -EngineAccountName "g-engine-test" `
            -AgentAccountName "g-agent-test" `
            -SecurityGroupName "SQL_CL_test" `
            -ServerNames "lab-NODE1","lab-NODE2" `
            -CreateSecurityGroup `
            -SecurityGroupOU "OU=lab_secgroups,DC=dev,DC=local" `
            -SecurityGroupDescription "DEV22A SQL Server Cluster gMSA Group" `
            -EngineAccountDescription "SQL Engine Service Account for DEV22A" `
            -AgentAccountDescription "SQL Agent Service Account for DEV22A" `
            -PasswordIntervalDays 90 `
            -LogPath "C:\Temp\gMSA_Creation_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

    # ===== EXAMPLE 4: Initialize KDS Root Key (once per Forest) =====
        .\security_createGMSA.ps1 `
            -InitializeKDS `
            -LogPath "C:\Temp\KDS_Init.log"

    # ===== EXAMPLE 5: Install accounts locally (separate execution, admin rights required) =====
        .\security_createGMSA.ps1 `
            -InstallLocally `
            -EngineAccountName "g-engine-dev22a" `
            -AgentAccountName "g-agent-dev22a"

    # ===== EXAMPLE 6: Remove accounts from AD =====
        .\security_createGMSA.ps1 `
            -DropGmsa `
            -EngineAccountName "g-engine-test" `
            -AgentAccountName "g-agent-test" `
            -LogPath "C:\Temp\gMSA_Remove_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

    # ===== EXAMPLE 7: Agent Account only for Standalone Server =====
        .\security_createGMSA.ps1 `
            -AgentAccountName "g-agent-standalone01" `
            -SecurityGroupName "SQL_Standalone_Servers" `
            -ServerNames "SQL-STANDALONE01" `
            -CreateSecurityGroup `
            -SecurityGroupDescription "Standalone SQL Servers for gMSA"

    # ===== EXAMPLE 8: Cluster with 4 nodes and custom password interval =====
        .\security_createGMSA.ps1 `
            -EngineAccountName "g-engine-cluster01" `
            -AgentAccountName "g-agent-cluster01" `
            -SecurityGroupName "SQL_CL_CLUSTER01" `
            -ServerNames "SQLNODE1","SQLNODE2","SQLNODE3","SQLNODE4" `
            -CreateSecurityGroup `
            -PasswordIntervalDays 180 `
            -DnsDomain "contoso.com" `
            -LogPath "C:\Logs\gMSA\Creation_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

    # ===== EXAMPLE 09: Account with existing group and specific OU =====
        .\security_createGMSA.ps1 `
            -EngineAccountName "g-engine-newinstance" `
            -SecurityGroupName "SQL_EXISTING_GROUP" `
            -SecurityGroupOU "OU=ServiceAccounts,OU=Production,DC=corp,DC=local"


#>
