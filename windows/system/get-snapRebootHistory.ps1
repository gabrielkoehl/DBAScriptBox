<#
.SYNOPSIS
    Analyzes Windows system reboot and shutdown events
.DESCRIPTION
    Retrieves relevant boot and shutdown events from System log with proper Event ID filtering
.NOTES
    File Name  : Get-SnapRebootHistory.ps1
    Author     : Gabriel Köhl
    Website    : https://dbavonnebenan.de
    GitHub     : https://github.com/gabrielkoehl/DBAScriptBox

    HISTORY
	- 22.10.2025 - to function and release

    Disclaimer: This script is provided "as is" without warranty of any kind.
                Use at your own risk. The author assumes no responsibility for
                any damages or issues that may arise from using this script.

.PARAMETER StartTime
    Start of the time range (default: 7 days ago)
.PARAMETER EndTime
    End of the time range (default: now)
.PARAMETER ExportPath
    Optional path to export results as CSV
.EXAMPLE
    .\Get-SnapRebootHistory.ps1
    Shows reboot/shutdown events from last 7 days
.EXAMPLE
    .\Get-SnapRebootHistory.ps1 -StartTime (Get-Date).AddDays(-30)
    Shows reboot history for last 30 days
.EXAMPLE
    .\Get-SnapRebootHistory.ps1 -ExportPath "C:\temp\RebootEvents.csv"
    Exports results to CSV file
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [DateTime]$StartTime = (Get-Date).AddDays(-7),

    [Parameter(Mandatory = $false)]
    [DateTime]$EndTime = (Get-Date),

    [Parameter(Mandatory = $false)]
    [String]$ExportPath
)

$criticalEventIds = @(
    1074,  # System shutdown/restart initiated by user/application
    6005,  # Event Log service started (system boot)
    6006,  # Event Log service stopped (shutdown)
    6008,  # Unexpected shutdown
    6009,  # System boot with OS info
    41     # System rebooted without cleanly shutting down (crash/power loss)
)

$eventDescriptions = @{
    1074 = "Shutdown/Restart initiated"
    6005 = "System boot (Event Log started)"
    6006 = "System shutdown (Event Log stopped)"
    6008 = "Unexpected shutdown"
    6009 = "System boot"
    41   = "Unexpected reboot (crash/power loss)"
}

# Reason code translations for Event ID 1074
$reasonCodes = @{
    "0x80020002" = "Application (software request)"
    "0x80020003" = "Operating System (software request)"
    "0x50000010" = "System failure (critical stop)"
    "0x50000018" = "Security issue"
    "0x500000ff" = "Other system failure"
    "0x800000ff" = "Power failure"
    "0x400000ff" = "User initiated (other)"
    "0x40010004" = "User initiated (planned)"
    "0x80000000" = "Legacy API shutdown"
}

Write-Host "Searching System Event Log for reboot/shutdown events..." -ForegroundColor Cyan

try
	{
		$events = Get-WinEvent -FilterHashtable @{
			LogName   = 'System'
			ID        = $criticalEventIds
			StartTime = $StartTime
			EndTime   = $EndTime
		} -ErrorAction Stop

    Write-Host "Found $($events.Count) events" -ForegroundColor Green

    $results = $events | ForEach-Object {
        $event = $_

        # Base properties
        $props = [ordered]@{
            TimeCreated = $event.TimeCreated
            EventID     = $event.Id
            EventType   = $eventDescriptions[$event.Id]
            User        = $null
            Process     = $null
            ReasonCode  = $null
            Reason      = $null
            Comment     = $null
        }

        # Extract details for shutdown events (1074)
        if ($event.Id -eq 1074) {
            # Extract reason code
            if ($event.Message -match "Reason Code: (0x\w+)") {
                $props.ReasonCode = $matches[1]
                if ($reasonCodes.ContainsKey($matches[1])) {
                    $props.Reason = $reasonCodes[$matches[1]]
                }
            }

            # Extract process
            if ($event.Message -match "Process:\s*([^\r\n,]+)") {
                $props.Process = $matches[1].Trim()
            }

            # Extract user
            if ($event.Message -match "User:\s*([^\r\n]+)") {
                $props.User = $matches[1].Trim()
            }

            # Extract comment
            if ($event.Message -match "Comment:\s*([^\r\n]+)") {
                $props.Comment = $matches[1].Trim()
            }
        }

        [PSCustomObject]$props
    } | Sort-Object TimeCreated

    Write-Host "`nReboot/Shutdown History ($($StartTime.ToString('yyyy-MM-dd')) to $($EndTime.ToString('yyyy-MM-dd')))" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Cyan

    foreach ($result in $results) {
        $color = switch ($result.EventID) {
            41 		{ 'Red' }
            6008 	{ 'Red' }
            1074 	{ 'Yellow' }
            default { 'White' }
        }

        Write-Host "`n$($result.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')) - $($result.EventType)" -ForegroundColor $color

        if ($result.User) 		{ Write-Host "  User: $($result.User)" 			-ForegroundColor Gray }
        if ($result.Process) 	{ Write-Host "  Process: $($result.Process)" 	-ForegroundColor Gray }
        if ($result.Reason) 	{ Write-Host "  Reason: $($result.Reason)" 		-ForegroundColor Gray }
        if ($result.Comment) 	{ Write-Host "  Comment: $($result.Comment)" 	-ForegroundColor Gray }
    }

    Write-Host "`n" ("=" * 80) -ForegroundColor Cyan
    Write-Host "Total: $($results.Count) events" -ForegroundColor Green

    # Export if requested
    if ($ExportPath) {
        $results | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
        Write-Host "Exported to: $ExportPath" -ForegroundColor Green
    }

} catch {

    if ($_.Exception.Message -like "*No events were found*") {
        Write-Host "No reboot or shutdown events found in the specified time period" -ForegroundColor Yellow
    } else {
        Write-Error "Error retrieving events: $($_.Exception.Message)"
    }
}