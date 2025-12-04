function Start-Cleanup {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$reportPath,
        
        [Parameter(Mandatory = $false)]
        [int]$days
    )
    

    $cutoffDate = (Get-Date).AddDays(-$days)
    
    Write-Host "Deleting files older than $cutoffDate in $reportPath" -ForegroundColor Yellow
    

    Get-ChildItem -Path $reportPath -Recurse -File | Where-Object {
        $_.LastWriteTime -lt $cutoffDate
    } | ForEach-Object {
         Remove-Item -Path $_.FullName -Force
    }
    
    # Drop empty folders
    
    $foundEmpty = $true
    while ( $foundEmpty ) {

        $foundEmpty = $false

        Get-ChildItem -Path $reportPath -Recurse -Directory | ForEach-Object {
            # Prüfe, ob der Ordner leer ist
            if ( -not (Get-ChildItem -Path $_.FullName -Force) ) {

                Write-Verbose "Delete empty folder: $($_.FullName)"
                Remove-Item -Path $_.FullName -Force
                $foundEmpty = $true

            }
        }
    }
    
    Write-Host "Cleanup completed" -ForegroundColor Green
}