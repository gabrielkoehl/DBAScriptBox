function New-SqlBlockExcelReport {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Array]$Events,

        [Parameter(Mandatory = $true)]
        [string]$ExcelPath,

        [Parameter(Mandatory = $false)]
        [int]$IntervalMinutes = 30
    )


    [array] $blockedEvents  = $events | Where-Object { $_.report_type -eq "blocked" }
    [array] $deadlockEvents = $events | Where-Object { $_.report_type -eq "deadlock" }

    function Group-EventsByTimeInterval {
        param (
            [Parameter(Mandatory = $true)]
            [Array]$EventsList,

            [Parameter(Mandatory = $true)]
            [int]$IntervalMinutes
        )

        $grouped = $EventsList | Group-Object -Property {
            $timeRounded    = $_.event_time
            $minutes        = $timeRounded.Minute
            $roundTo        = [Math]::Floor($minutes / $IntervalMinutes) * $IntervalMinutes
            $timeRounded    = $timeRounded.AddMinutes(-($minutes - $roundTo))

            return $timeRounded.ToString("yyyy-MM-dd HH:mm")
        }

        $result = foreach ( $group in $grouped ) {

            [PSCustomObject]@{
                "Interval"  = $group.Name
                "Count"     = $group.Count
            }

        }

        return $result

    }

    # Group events
    $blockedGrouped     =   if ( $blockedEvents ) {
                                Group-EventsByTimeInterval -EventsList $blockedEvents -IntervalMinutes $IntervalMinutes
                            } else {
                                $null        
                            }

    $deadlockGrouped    =   if ( $deadlockEvents ) {
                                Group-EventsByTimeInterval -EventsList $deadlockEvents -IntervalMinutes $IntervalMinutes
                            } else {
                                $null
                            }

    # Create a complete timeline with all intervals
    $allTimes = @()
    
    # Find min and max times to create a complete timeline
    $minTime = $null
    $maxTime = $null
    $currentDateTime = Get-Date
    
    if ( $Events.Count -gt 0 ) {

        $minTime        = ($Events | Measure-Object -Property event_time -Minimum).Minimum
        $maxEventTime   = ($Events | Measure-Object -Property event_time -Maximum).Maximum
        
        # Use the current time if it's later than the max event time to include the current interval
        $maxTime = if ($currentDateTime -gt $maxEventTime) { $currentDateTime } else { $maxEventTime }
        
        # Round down to nearest interval for min time
        $minutes = $minTime.Minute
        $roundTo = [Math]::Floor($minutes / $IntervalMinutes) * $IntervalMinutes
        $minTime = $minTime.AddMinutes(-($minutes - $roundTo))
        $minTime = $minTime.AddSeconds(-$minTime.Second).AddMilliseconds(-$minTime.Millisecond)
        
        # Round up to nearest interval for max time
        $minutes = $maxTime.Minute
        $roundTo = [Math]::Ceiling($minutes / $IntervalMinutes) * $IntervalMinutes
        $maxTime = $maxTime.AddMinutes($roundTo - $minutes)
        $maxTime = $maxTime.AddSeconds(-$maxTime.Second).AddMilliseconds(-$maxTime.Millisecond)
        
        # Generate all intervals between min and max
        $currentTime = $minTime
        while ($currentTime -le $maxTime) {
            $allTimes += $currentTime.ToString("yyyy-MM-dd HH:mm")
            $currentTime = $currentTime.AddMinutes($IntervalMinutes)
        }
    }
    else {
        # If no events, use current time to create at least one interval
        $minutes = $currentDateTime.Minute
        $roundTo = [Math]::Floor($minutes / $IntervalMinutes) * $IntervalMinutes
        $startTime = $currentDateTime.AddMinutes(-($minutes - $roundTo))
        $startTime = $startTime.AddSeconds(-$startTime.Second).AddMilliseconds(-$startTime.Millisecond)
        
        $endTime = $startTime.AddMinutes($IntervalMinutes)
        $allTimes += $startTime.ToString("yyyy-MM-dd HH:mm")
    }
    
    # Create combined dataset for charting
    $combinedData = @()
    
    # Always use the generated time intervals
    foreach ($interval in $allTimes) {
        $blockedItem = $blockedGrouped | Where-Object { $_.Interval -eq $interval }
        # Fix: Use the Count property from the group, not the array size
        $blockedCount = if ($blockedItem) { $blockedItem.Count } else { 0 }
        
        $deadlockItem = $deadlockGrouped | Where-Object { $_.Interval -eq $interval }
        $deadlockCount = if ($deadlockItem) { $deadlockItem.Count } else { 0 }
        
        # Check if we found data for this interval
        if ($blockedItem -or $deadlockItem) {
            # Use the actual count value from the group object
            $blockedCount = if ($blockedItem) { $blockedItem.Count } else { 0 }
            $deadlockCount = if ($deadlockItem) { $deadlockItem.Count } else { 0 }
        }
        
        $combinedData += [PSCustomObject]@{
            "Interval"  = $interval
            "Blocked"   = $blockedCount
            "Deadlock"  = $deadlockCount
        }
    }

    # Filter out intervals with no data to avoid empty time slots
    $combinedData = $combinedData | Where-Object { $_.Blocked -gt 0 -or $_.Deadlock -gt 0 } | Sort-Object -Property Interval

    # Create chart definition
    $chart = New-ExcelChartDefinition -Title "SQL Blocks and Deadlocks ($IntervalMinutes-min intervals)" `
            -ChartType ColumnClustered `
            -XRange Interval `
            -YRange @("Blocked", "Deadlock") `
            -Width 800 -Height 500 `
            -XAxisTitleText "Time" -YAxisTitleText "Count" `
            -SeriesHeader @("Blocked", "Deadlocks")

    # Export to Excel
    $blockedGrouped     | Export-Excel -Path $ExcelPath -WorksheetName "BlockedDetails" -AutoSize
    $deadlockGrouped    | Export-Excel -Path $ExcelPath -WorksheetName "DeadlockDetails" -AutoSize
    $combinedData       | Export-Excel -Path $ExcelPath -WorksheetName "Overview" `
                                                        -AutoNameRange -AutoSize -AutoFilter `
                                                        -ExcelChartDefinition $chart

    return $ExcelPath

}
