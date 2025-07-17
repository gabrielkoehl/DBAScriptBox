<#
.SYNOPSIS
    Performs disk performance testing optimized for SQL Server workloads

.DESCRIPTION
    Parameters explanation:
    -b8K    : Block size 8KB (matches SQL Server page size)
    -d30    : Test duration 30 seconds
    -h      : Disables software and hardware caching
    -L      : Enables large pages
    -o32    : Outstanding I/O requests (simulates concurrent transactions)
    -t8     : Number of threads (simulates parallel queries)
    -r      : Enables random I/O access
    -w40    : Write operations percentage (typical for OLTP)
    -c10G   : Test file size of 10GB

.EXAMPLE
	# Copy DISKSPD Folder on Target Disk
    # RUN PowerShell console as admin
		powersehll -ExecutionPolicy Bypass <PATHtoScript>\run_diskspd.ps1

.Notes
   File Name      : run_diskspd.ps1
   Author         : Gabriel Köhl
   Date           : July 2025
   
   This script is provided "as is" without warranty of any kind.
   You are free to use, modify, and distribute this script as you wish.
   No liability is assumed for any damages resulting from its use.

.LINK
   https://dbavonnebenan.de
         
#>

# Parameters
    $testPath   			= "$PSScriptRoot\output" 
    $testFile   			= Join-Path $testPath "testfile.dat"
    $resultFile_SQL 		= Join-Path $testPath "$(Get-Date -Format 'yyyyMMdd_HHmmss')_diskspd_results_SQL.txt"
	$resultFile_64KB_RND 	= Join-Path $testPath "$(Get-Date -Format 'yyyyMMdd_HHmmss')_diskspd_results_64KB_RND.txt"
	$resultFile_64KB_SEQ 	= Join-Path $testPath "$(Get-Date -Format 'yyyyMMdd_HHmmss')_diskspd_results_64KB_SEQ.txt"
    $diskSpd    			= "$PSScriptRoot\bin\diskspd.exe"


if (-not (Test-Path $testPath)) {
    New-Item -ItemType Directory -Path $testPath
}

try {
    Write-Host "Starting DiskSpd test SQL..."
    Write-Host "Results will be saved to: $resultFile_SQL "
    
		& $diskSpd -b8K -d30 -h -L -o32 -t8 -r -w40 -c10G $testFile > $resultFile_SQL 
	
	Write-Host "Starting DiskSpd test 64KB RND..."
    Write-Host "Results will be saved to: $resultFile_64KB_RND"
	
		& $diskSpd -b64K -d120 -h -L -o16 -t8 -r -w40 -c2G $testFile > $resultFile_64KB_RND
		
	Write-Host "Starting DiskSpd test 64KB SEQ..."
    Write-Host "Results will be saved to: $resultFile"
		& $diskSpd -b64K -d120 -h -L -o16 -t8 -w40 -c10G $testFile > $resultFile_64KB_SEQ
    
    Write-Host "Test completed successfully!"
    Write-Host "Results have been saved to: $resultFile_64KB_SEQ"
}
catch {
    Write-Error "An error occurred during the test: $_"
}
finally {
    # Cleanup test file if needed
    if (Test-Path $testFile) {
        Remove-Item $testFile -Force
    }
}