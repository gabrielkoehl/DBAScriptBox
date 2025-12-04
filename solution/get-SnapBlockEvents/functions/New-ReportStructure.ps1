function New-ReportStructure {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [DateTime]$EventTime
    )

    $reportBase      = Join-Path $RootPath "_report"
    $textReportPath  = Join-Path $reportBase "text_reports"

    $year       = $EventTime.ToString("yyyy")
    $month      = $EventTime.ToString("MM")
    $day        = $EventTime.ToString("dd")
    $hour       = $EventTime.ToString("HH")

    $datePath   = Join-Path $textReportPath "$year\$month\$day\$hour"

    # Create directory if it doesn't exist
    if ( -not (Test-Path $datePath) ) {

        New-Item -Path $datePath -ItemType Directory -Force | Out-Null

    }

    return @{
        TextPath    = $datePath
        ExcelPath   = Join-Path $reportBase "excel_reports"
    }
}
