<#
.SYNOPSIS
    Creates and configures Group Managed Service Accounts (gMSA) in Active Directory
.DESCRIPTION
    Automates the creation of gMSA accounts in Active Directory including:
    - Creating security groups for server access control (optional)
    - Creating gMSA accounts
    - Installing gMSA accounts on local server (optional, requires restart)
    - Removing gMSA accounts from AD
    - Logging all operations to file (optional)

    IMPORTANT: Install operations require elevated privileges and must be run separately
    from account creation as they may require a system restart.

    NOTE: Uninstall-ADServiceAccount does not reliably remove gMSA from local cache due to
    Windows LSA limitations. Function removed
.PARAMETER AccountName
    Array of account definitions. Each element can be:
    - String: Account name only (no description)
    - Array: [Name, Description]
    Example: @("gmsa-svc1", @("gmsa-svc2", "Web Service Account"))
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
    Optional description for security group (default: "gMSA security group for computers")
.PARAMETER InstallLocally
    Switch to install created gMSA accounts on local server (REQUIRES ADMIN RIGHTS, SEPARATE EXECUTION)
.PARAMETER InitializeKDS
    Switch to initialize KDS Root Key (only needed once per AD forest)
.PARAMETER DropGmsa
    Switch to remove gMSA accounts from Active Directory. Local removement not working ATM (2DO)
.PARAMETER LogPath
    Optional path to log file. If not specified, only console output is generated.
.EXAMPLE
    .\security_createGMSA.ps1 -InitializeKDS -LogPath "C:\Temp\KDS_Init.log"
    Initializes KDS Root Key (required once per AD forest)
.EXAMPLE
    .\security_createGMSA.ps1 -AccountName @(@("g-LAB22A-oltp", "SQL Engine"), @("g-LAB22A-agnt", "SQL Agent")) -SecurityGroupName "SQL_LAB_CL01" -ServerNames "LAB-NODE01","LAB-NODE02" -CreateSecurityGroup
    Creates gMSA accounts for AlwaysOn cluster with new security group
.EXAMPLE
    .\security_createGMSA.ps1 -InstallLocally -AccountName "g-LAB22A-oltp","g-LAB22A-agnt"
    Installs gMSA accounts on local server (requires restart, admin rights required)
.EXAMPLE
    .\security_createGMSA.ps1 -DropGmsa -AccountName "g-LAB22A-oltp" -LogPath "C:\Temp\gMSA_Remove.log"
    Removes gMSA account from Active Directory
.NOTES
    File Name  : security_createGMSA.ps1
    Author     : Gabriel Köhl
    Website    : https://dbavonnebenan.de
    GitHub     : https://github.com/gabrielkoehl/DBAScriptBox
    HISTORY
    - 25.05.2024 - Init
    - 30.01.2026 - Updated with different functions
    - 04.02.2026 - Removed Sql Server Dependencies

    Disclaimer: This script is provided "as is" without warranty of any kind.
                Use at your own risk. The author assumes no responsibility for
                any damages or issues that may arise from using this script.

    REQUIREMENTS:
    - Run as Domain Administrator or delegated permissions for account creation
    - Local Administrator rights ONLY for -InstallLocally operation
    - ActiveDirectory PowerShell module
    - KDS Root Key must be initialized (use -InitializeKDS once per forest)

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
    [object[]]  $AccountName,

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

        $existingKey = Get-KdsRootKey

        if ($existingKey) {
            Write-Host "KDS Root Key already exists." -ForegroundColor Green
            Write-Log "KDS Root Key already exists"
            return $true
        }

        Write-Host "Creating KDS Root Key..." -ForegroundColor Cyan
        Write-Log "Creating KDS Root Key..."

        Add-KdsRootKey -EffectiveTime (Get-Date).AddHours(-10) | Out-Null
        Write-Host "KDS Root Key created successfully." -ForegroundColor Green
        Write-Log "KDS Root Key created successfully."

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

        $defaultDescription = "gMSA security group for computers"
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
        [string]    $AccountName,
        [string]    $DnsHostName,
        [string]    $PrincipalsGroup,
        [int]       $PasswordInterval,
        [string]    $Description
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
        Write-Log "Creating gMSA account '$AccountName' with Description: '$Description', DNS: '$DnsHostName', Group: '$PrincipalsGroup', PasswordInterval: $PasswordInterval days"

        $newAccountParams = @{
            Name                                        = $AccountName
            PrincipalsAllowedToRetrieveManagedPassword  = $PrincipalsGroup
            Enabled                                     = $true
            DNSHostName                                 = $DnsHostName
            SamAccountName                              = $AccountName
            ManagedPasswordIntervalInDays               = $PasswordInterval
            ErrorAction                                 = 'Stop'
        }

        if ($Description) {
            $newAccountParams['Description'] = $Description
        }

        New-ADServiceAccount @newAccountParams

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
        [object[]]  $AccountDefinitions
    )

    try {

        Write-Host "`nInstalling gMSA accounts on local server..." -ForegroundColor Cyan

        # Extract account names from definitions
        $accountNames = @()
        foreach ($def in $AccountDefinitions) {

            if ($def -is [array]) {
                $accountNames += $def[0]
            } else {
                $accountNames += $def
            }

        }

        Write-Log "Installing gMSA accounts locally: $($accountNames -join ', ')"

        $installResults = @()

        foreach ($accountName in $accountNames) {

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

                } catch {

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
        [object[]]  $AccountDefinitions
    )

    $removedAccounts = @()

    # Extract account names from definitions
    $accountNames = @()
    foreach ($def in $AccountDefinitions) {

        if ($def -is [array]) {
            $accountNames += $def[0]
        } else {
            $accountNames += $def
        }

    }

    foreach ($accountName in $accountNames) {

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

function ConvertTo-AccountDefinitions {
    param (
        [object[]]$InputArray
    )

    $definitions = @()

    foreach ($item in $InputArray) {

        if ($item -is [array]) {
            # Already array format [Name, Description]
            $definitions += ,@($item[0].TrimEnd('$'), $item[1])
        } else {
            # Simple string, no description
            $definitions += ,@($item.TrimEnd('$'), "")
        }

    }

    return $definitions
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

    if (-not $AccountName -or $AccountName.Count -eq 0) {

        Write-Host "Error: At least one account name must be specified." -ForegroundColor Red
        Write-Log "Error: No account names specified for installation" -Level "ERROR"
        exit 1

    }

    Write-Host "`nAccounts to install:" -ForegroundColor Cyan

    foreach ($acc in $AccountName) {
        $displayName = if ($acc -is [array]) { $acc[0] } else { $acc }
        Write-Host "  - $displayName" -ForegroundColor White
    }

    Write-Host ""

    $success = Install-gMSALocally -AccountDefinitions $AccountName

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

    Write-Host "=== gMSA Account Removal ===" -ForegroundColor Cyan
    Write-Host "============================" -ForegroundColor Cyan
    Write-Log "=== gMSA Account Removal ==="

    if (-not $AccountName -or $AccountName.Count -eq 0) {

        Write-Host "Error: At least one account name must be specified." -ForegroundColor Red
        Write-Log "Error: No account names specified for removal" -Level "ERROR"

        exit 1

    }

    Write-Host "`nAccounts to remove from AD:" -ForegroundColor Cyan

    foreach ($acc in $AccountName) {
        $displayName = if ($acc -is [array]) { $acc[0] } else { $acc }
        Write-Host "  - $displayName" -ForegroundColor White
    }

    Write-Host ""
    Write-Host "NOTE: Local gMSA cache (Install-ADServiceAccount) cannot be reliably removed" -ForegroundColor Yellow
    Write-Host "      due to Windows LSA limitations. This is harmless and does not affect AD removal." -ForegroundColor Yellow
    Write-Host ""

    $removedAccounts = Remove-gMSAServiceAccount -AccountDefinitions $AccountName

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
Write-Log "=== gMSA Account Creation ==="

if (-not $AccountName -or $AccountName.Count -eq 0) {

    Write-Host "Error: At least one account name must be specified." -ForegroundColor Red
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

# Convert AccountName to normalized definitions
$accountDefinitions = ConvertTo-AccountDefinitions -InputArray $AccountName

Write-Host "=== gMSA Account Creation ===" -ForegroundColor Cyan
Write-Host "=============================" -ForegroundColor Cyan

Write-Host "`nConfiguration:" -ForegroundColor Cyan
Write-Host "  Security Group: $SecurityGroupName" -ForegroundColor White
Write-Host "  Accounts:" -ForegroundColor White

foreach ($def in $accountDefinitions) {

    $displayText = "    - $($def[0])"
    if ($def[1]) { $displayText += " ($($def[1]))" }
    Write-Host $displayText -ForegroundColor White

}

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
$stepNumber = 2

foreach ($def in $accountDefinitions) {

    $accountName = $def[0]
    $accountDesc = $def[1]

    Write-Host "`nStep $stepNumber`: Creating gMSA account '$accountName'" -ForegroundColor Cyan
    if ($accountDesc) {
        Write-Host "Description: $accountDesc" -ForegroundColor Gray
    }
    Write-Host "-----------------------------------------" -ForegroundColor Cyan

    $accountDns = "$accountName.$DnsDomain"
    $accountSuccess = New-gMSAServiceAccount -AccountName $accountName `
                                             -DnsHostName $accountDns `
                                             -PrincipalsGroup $SecurityGroupName `
                                             -PasswordInterval $PasswordIntervalDays `
                                             -Description $accountDesc

    if ($accountSuccess) { $createdAccounts += $accountName }
    $stepNumber++

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
    $installCommand = ".\security_createGMSA.ps1 -InstallLocally -AccountName"

    # Build account list for install command
    $accountList = "@("
    $accountList += ($createdAccounts | ForEach-Object { "'$_'" }) -join ","
    $accountList += ")"

    Write-Host "     $installCommand $accountList" -ForegroundColor Gray
    Write-Host "     Note: Restart system after installation if accounts were just created" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  2. Configure services to use gMSA accounts" -ForegroundColor White
    Write-Host "     Format: DOMAIN\`$account$" -ForegroundColor Gray

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

    # ===== EXAMPLE 1: Initialize KDS Root Key (once per Forest) =====
    .\security_createGMSA.ps1 `
        -InitializeKDS `
        -LogPath "C:\Temp\KDS_Init.log"

    # ===== EXAMPLE 2: AlwaysOn - gMSA for 2 Nodes with new Security Group =====
    .\security_createGMSA.ps1 `
        -AccountName @( `
            @("g-LAB22A-oltp", "SQL Server Engine Account for LAB22A"), `
            @("g-LAB22A-agnt", "SQL Server Agent Account for LAB22A") ) `
        -SecurityGroupName "SQL_LAB_CL01" `
        -SecurityGroupDescription "SQL Server Cluster CL01 gMSA Group" `
        -ServerNames "LAB-NODE01","LAB-NODE02" `
        -CreateSecurityGroup `
        -SecurityGroupOU "OU=lab_secgrp,DC=lab,DC=local" `
        -PasswordIntervalDays 90 `
        -LogPath "C:\Temp\gMSA_Creation_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

    # ===== EXAMPLE 3: SingleNode - gMSA for standalone Server =====
    .\security_createGMSA.ps1 `
        -AccountName @( `
            @("g-DEV22A-oltp", "SQL Server Engine Account for DEV22A"), `
            @("g-DEV22A-agnt", "SQL Server Agent Account for DEV22A") ) `
        -SecurityGroupName "SQL_DEV_SRV01" `
        -SecurityGroupDescription "SQL Server DEV-SRV01 gMSA Group" `
        -ServerNames "DEV-SRV01" `
        -CreateSecurityGroup `
        -LogPath "C:\Temp\gMSA_SingleNode_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

    # ===== EXAMPLE 4: Install gMSA locally (separate execution, local admin required) =====
    .\security_createGMSA.ps1 `
        -InstallLocally `
        -AccountName "g-LAB22A-oltp","g-LAB22A-agnt" `
        -LogPath "C:\Temp\gMSA_Install_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

    # ===== EXAMPLE 5: Remove gMSA accounts from AD =====
    .\security_createGMSA.ps1 `
        -DropGmsa `
        -AccountName "g-LAB22A-oltp","g-LAB22A-agnt" `
        -LogPath "C:\Temp\gMSA_Remove_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

#>