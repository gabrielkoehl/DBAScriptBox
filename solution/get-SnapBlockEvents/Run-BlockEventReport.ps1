[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string] $eventFilePath,

    [Parameter(Mandatory = $true)]
    [string] $metaFilePath,

    [Parameter(Mandatory = $false)]
    [string] $reportRoot = $(Join-Path $(Split-Path -Parent $MyInvocation.MyCommand.Path) "_report"),

    [Parameter(Mandatory = $false)]
    [DateTime] $StartTime = (Get-Date).AddHours(-24),

    [Parameter(Mandatory = $false)]
    [DateTime] $EndTime = $(Get-Date),

    [Parameter(Mandatory = $false)]
    [int] $hoursBack = 2,

    [Parameter(Mandatory = $false)]
    [int] $ChartIntervalMinutes = 60,

    [Parameter(Mandatory = $true)]
    [string] $SqlInstance,

    [Parameter(Mandatory = $false)]
    [switch] $returnSummary,

    [Parameter(Mandatory = $false)]
    [switch] $excel,
    
    [Parameter(Mandatory = $false)]
    [switch] $cleanUp,

    [Parameter(Mandatory = $false)]
    [int] $cleanUpDays = 30

)



# Event Param

    $sqlParams = @{
        EventFilePath   = $eventFilePath
        metaFilePath    = $metaFilePath
        SqlInstance     = $SqlInstance
    }

    if ( $PSBoundParameters.ContainsKey('hoursBack')) {

        $sqlParams['StartTime'] = (Get-Date).AddHours(-$hoursBack)
        $sqlParams['EndTime']   = Get-Date

    } else {

        $sqlParams['StartTime'] = $StartTime
        $sqlParams['EndTime']   = $EndTime

    }

# Vars
    $dbEventSummary = @{}


# Load functions
    $functionPath = Join-Path $PSScriptRoot "functions"
    Get-ChildItem -Path $functionPath -Filter "*.ps1" | ForEach-Object {
        . $_.FullName
    }

# Get events from SQL
    $events = Get-SqlBlockEvents @sqlParams

    if (-not $events) {
        Write-Warning "No events found in the specified time period"
        exit 0
    }


# Create report structure
    $excelReportPath    = Join-Path $reportRoot "excel_reports"



    @($reportRoot, $excelReportPath) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -Path $_ -ItemType Directory -Force | Out-Null
        }
    }

# Process each event and create text reports
    foreach ( $event in $events ) {
        # Extract database name from the first process
        $dbName = ""
        $xmlObj = [xml]$event.report_xml

        $eventType = $null

        if ($event.report_type -eq 'blocked') {

            $dbName = $xmlObj.'blocked-process-report'.'blocked-process'.process.currentdbname

            $eventType = 'block'

        } else {

            # For deadlocks: Take the database from the first process or resource
            $firstProcess = $xmlObj.deadlock.process | Select-Object -First 1
            if ( $firstProcess.currentdb ) {

                $dbName = $firstProcess.currentdbname

            } elseif ($null -eq $dbName -or $dbName -eq '') {    # Fallback: Try to get the database from the first resource

                $firstResource = $xmlObj.deadlock.SelectNodes("//resource-list/*") | Select-Object -First 1

                if ( $firstResource.dbid ) {

                    $dbName = Invoke-DbaQuery -Query "SELECT DB_NAME($($firstResource.dbid)) as dbname" -SqlInstance $SqlInstance |
                                    Select-Object -ExpandProperty dbname

                }
            }

            $eventType = 'lock'

        }

        # collecting summary data
        if ( -not [string]::IsNullOrEmpty($dbName) ) {

            if (-not $dbEventSummary.ContainsKey($dbName)) {
                $dbEventSummary[$dbName] = @{
                    'lock'  = 0
                    'block' = 0
                }
            }

            $dbEventSummary[$dbName][$eventType]++

        }        

        $reportPaths = New-ReportStructure -RootPath $PSScriptRoot -EventTime $event.event_time

        # Format filename with timestamp and database
        $timestamp  = $event.event_time.ToString('yyyyMMdd_HHmmss')
        $dbPart     = if ($dbName) { "_$dbName" } else { "" }
        $baseName   = "${timestamp}${dbPart}_$($event.report_type)"
        $outPath    = Join-Path $reportPaths.TextPath "$baseName.txt"
        $xmlPath    = Join-Path $reportPaths.TextPath "$baseName.xml"

        # Generate report
        format-SnapSqlLockReport -XmlContent $event.report_xml | Out-File $outPath -Force

        # Save XML file
        $event.report_xml | Out-File $xmlPath -Force

    }

# format summary data

    $convertedObjects = @()
        
    foreach ($db in $dbEventSummary.Keys) {
        $dbObject = [PSCustomObject]@{
            dbname = $db
            lock   = $dbEventSummary[$db]['lock']
            block  = $dbEventSummary[$db]['block']
        }
        $convertedObjects += $dbObject
    }
    
    $dbEventSummaryReport = $convertedObjects    


# Generate Excel report with current timestamp

    if ( $excel.IsPresent ) {

        $excelPath = Join-Path $excelReportPath "BlockReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').xlsx"
        New-SqlBlockExcelReport -Events $events -ExcelPath $excelPath -IntervalMinutes $ChartIntervalMinutes
    
        Write-Host "Excel report: $excelPath"

    }

# cleanup

    if ( $cleanUp.IsPresent ) {

        start-cleanUp -reportPath $reportRoot -days $cleanUpDays

    }

# Console completed

    if ( $returnSummary.IsPresent ) {

        return $dbEventSummaryReport

    }

    Write-Host "Report generation complete"
