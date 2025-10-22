<#
.SYNOPSIS
    Retrieves Windows Event Log entries with flexible filtering options
.DESCRIPTION
    Filters Windows Event Logs by severity, log names, time range, and message content.
    Output can be displayed in GridView or as formatted console table.
.NOTES
    File Name  : Get-SnapWinEvents.ps1
    Author     : Gabriel Köhl
    Website    : https://dbavonnebenan.de
    GitHub     : https://github.com/gabrielkoehl/DBAScriptBox

    HISTORY
	- 02.05.2023 - Init
	- 22.10.2025 - function and param

    Disclaimer: This script is provided "as is" without warranty of any kind.
                Use at your own risk. The author assumes no responsibility for
                any damages or issues that may arise from using this script.

.PARAMETER StartTime
    Start of the time range (default: 24 hours ago)
.PARAMETER EndTime
    End of the time range (default: now)
.PARAMETER Severity
    Event severity levels to filter (Critical, Error, Warning, Information, Verbose)
    Default: Critical, Error
.PARAMETER LogNames
    Array of log names to query (default: System, Application)
.PARAMETER MessageFilter
    Optional string to filter events by message content
.PARAMETER OutGrid
    Switch to display results in Out-GridView instead of console table
.EXAMPLE
    .\Get-SnapWinEvents.ps1
    Displays critical and error events from last 24 hours in console table
.EXAMPLE
    .\Get-SnapWinEvents.ps1 -OutGrid
    Displays results in GridView window
.EXAMPLE
    .\Get-SnapWinEvents.ps1 -Severity Critical,Error -StartTime (Get-Date).AddDays(-7)
    Shows critical and error events from last 7 days in console
.EXAMPLE
    .\Get-SnapWinEvents.ps1 -LogNames 'System','Application','Microsoft-Windows-FailoverClustering/Operational' -MessageFilter "cluster" -OutGrid
    Filters cluster-related events and displays in GridView
.EXAMPLE
    .\Get-SnapWinEvents.ps1 -StartTime "2025-10-20 08:00" -EndTime "2025-10-20 17:00" -Severity Warning
    Shows warnings for specific time range in console
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [DateTime]$StartTime = (Get-Date).AddHours(-24),

    [Parameter(Mandatory = $false)]
    [DateTime]$EndTime = (Get-Date),

    [Parameter(Mandatory = $false)]
    [ValidateSet('Critical', 'Error', 'Warning', 'Information', 'Verbose')]
    [String[]]$Severity = @('Critical', 'Error'),

    [Parameter(Mandatory = $false)]
    [String[]]$LogNames = @('System', 'Application'),

    [Parameter(Mandatory = $false)]
    [String]$MessageFilter,

    [Parameter(Mandatory = $false)]
    [Switch]$OutGrid
)

# Validate time range
if ($EndTime -lt $StartTime) {
    Write-Error "EndTime must be after StartTime"
    exit 1
}

# Map severity names to event levels
$severityMap = @{
    'Critical'    = 1
    'Error'       = 2
    'Warning'     = 3
    'Information' = 4
    'Verbose'     = 5
}

$levels = $Severity | ForEach-Object { $severityMap[$_] }

# Build filter hashtable
$filterHashtable = @{
    LogName   = $LogNames
    Level     = $levels
    StartTime = $StartTime
    EndTime   = $EndTime
}

# Retrieve events
try {
    $events = Get-WinEvent -FilterHashtable $filterHashtable -ErrorAction Stop

    # Apply message filter if specified
    if ($MessageFilter) {
        $events = $events | Where-Object { $_.Message -like "*$MessageFilter*" }
        Write-Host "Filtered by message: '$MessageFilter'" -ForegroundColor Cyan
    }

    # Select properties for output
    $output = $events | Select-Object TimeCreated, LevelDisplayName, LogName, ProviderName, Id, Message

    # Display results based on switch
    if ($OutGrid) {
        $output | Out-GridView -Title "Windows Events: $($Severity -join ', ') ($StartTime - $EndTime)"
    }
    else {
        $output | Format-Table -AutoSize -Wrap
    }

    Write-Host "Found $($events.Count) events" -ForegroundColor Green
}
catch {
    if ($_.Exception.Message -like "*No events were found*") {
        Write-Host "No events found matching the specified criteria" -ForegroundColor Yellow
    }
    else {
        Write-Error "Error retrieving events: $($_.Exception.Message)"
    }
}