function Get-SqlBlockEvents {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$EventFilePath,

        [Parameter(Mandatory = $true)]
        [string]$metaFilePath,

        [Parameter(Mandatory = $false)]
        [DateTime]$StartTime = [DateTime]::Parse("1990-01-01"),

        [Parameter(Mandatory = $false)]
        [DateTime]$EndTime,

        [Parameter(Mandatory = $false)]
        [string]$SqlInstance
    )

    $queryPath  = Join-Path $PSScriptRoot "list_xe.sql"
    $query      = Get-Content -Path $queryPath -Raw


    # Replace placeholders in query
    $query = $query.Replace("'##XEL_PATH##'",   "'$EventFilePath'")
    $query = $query.Replace("'##XEM_PATH##'",   "'$metaFilePath'")
    $query = $query.Replace("'##START_TIME##'", "'$StartTime'")
    $query = $query.Replace("'##END_TIME##'",   "'$EndTime'")

    try {

        $result     = Invoke-dbaquery -Query $query -SqlInstance $SqlInstance
        $validTypes = $result | Where-Object { $_.report_type -in @('blocked', 'deadlock') }

        if ($validTypes.Count -ne $result.Count) {

            Write-Warning "Some events were filtered out as they were neither blocked nor deadlock events"

        }

        return $validTypes

    } catch {

        Write-Error "Failed to execute SQL query: $_"
        return $null

    }

}
