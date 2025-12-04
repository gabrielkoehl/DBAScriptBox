# SQL Server Disk Performance Testing with DISKSPD

## Overview

This package contains a PowerShell script for performing disk performance testing optimized for SQL Server workloads using Microsoft's DISKSPD tool.

## Author

Gabriel Köhl  
Site: https://dbavonnebenan.de  
Repository: https://github.com/gabrielkoehl/DBAScriptBox

## Official DISKSPD Repository

Microsoft DISKSPD: https://github.com/microsoft/diskspd

## Scripts

### run_diskspd.ps1

A PowerShell script that performs three different disk performance tests optimized for SQL Server environments. Each test is designed to simulate different I/O patterns commonly found in database workloads.

**Key Features:**
- SQL Server optimized test with 8KB block size
- 64KB random I/O test for general performance assessment
- 64KB sequential I/O test for throughput measurement
- Automatic result file generation with timestamps
- Error handling and cleanup

**Test Configurations:**

1. **SQL Server Test** (`-b8K -d30 -h -L -o32 -t8 -r -w40 -c10G`)
   - Block size: 8KB (SQL Server page size)
   - Duration: 30 seconds
   - Outstanding I/O: 32 (simulates concurrent transactions)
   - Threads: 8 (simulates parallel queries)
   - Write percentage: 40% (typical OLTP workload)

2. **64KB Random Test** (`-b64K -d120 -h -L -o16 -t8 -r -w40 -c2G`)
   - Block size: 64KB
   - Duration: 120 seconds
   - Outstanding I/O: 16
   - Random access pattern

3. **64KB Sequential Test** (`-b64K -d120 -h -L -o16 -t8 -w40 -c10G`)
   - Block size: 64KB
   - Duration: 120 seconds
   - Outstanding I/O: 16
   - Sequential access pattern

## DISKSPD Parameters Explained

- `-b8K` / `-b64K`: Block size (8KB matches SQL Server page size)
- `-d30` / `-d120`: Test duration in seconds
- `-h`: Disables software and hardware caching
- `-L`: Enables large pages for better performance
- `-o32` / `-o16`: Outstanding I/O requests (queue depth)
- `-t8`: Number of threads (simulates parallel operations)
- `-r`: Enables random I/O access pattern
- `-w40`: Write operations percentage (40% writes, 60% reads)
- `-c10G` / `-c2G`: Test file size

## Prerequisites

- Windows PowerShell 5.1 or later
- Administrator privileges (recommended)
- DISKSPD executable in the `bin` folder
- Sufficient disk space for test files

## Usage

### Basic Execution

```powershell
# Copy DISKSPD folder to target disk
# Run PowerShell console as administrator
powershell -ExecutionPolicy Bypass .\run_diskspd.ps1
```

### Advanced Execution

```powershell
# Navigate to the DISKSPD folder
cd "<PATH>\DBAScriptBox\perf_diskspeed\DISKSPD"

# Run the script with execution policy bypass
powershell -ExecutionPolicy Bypass .\run_diskspd.ps1
```

## Output Files

The script generates timestamped result files in the `output` folder:

- `YYYYMMDD_HHmmss_diskspd_results_SQL.txt`: SQL Server optimized test results
- `YYYYMMDD_HHmmss_diskspd_results_64KB_RND.txt`: 64KB random I/O test results
- `YYYYMMDD_HHmmss_diskspd_results_64KB_SEQ.txt`: 64KB sequential I/O test results

## File Structure

```
DISKSPD/
├── run_diskspd.ps1          # Main PowerShell script
├── README.md                # This documentation
├── bin/
│   ├── diskspd.exe         # DISKSPD executable
│   └── diskspd.pdb         # Debug symbols
└── output/                 # Generated during execution
    ├── testfile.dat        # Temporary test file (auto-deleted)
    └── *_diskspd_results_*.txt # Result files
```

## Best Practices

### Test Environment

1. Copy the entire DISKSPD folder to the target disk for testing
2. Open PowerShell as Administrator
3. Navigate to the DISKSPD folder
4. Execute the script: `powershell -ExecutionPolicy Bypass .\run_diskspd.ps1`
5. Monitor the console output for progress updates
6. Review generated result files in the `output` folder
7. Compare results against your performance requirements

### Result Interpretation

- **IOPS**: Focus on random I/O results for OLTP workloads
- **Throughput**: Sequential tests show maximum data transfer rates
- **Latency**: Lower latency values indicate better performance
- **CPU Usage**: Monitor CPU during tests to identify bottlenecks

### SQL Server Specific Considerations

- The 8KB test most closely simulates SQL Server data page I/O
- 40% write ratio simulates typical OLTP workloads
- Adjust test parameters based on your specific workload patterns

## Troubleshooting

### Common Issues

1. **Access Denied**: Run PowerShell as Administrator
2. **Execution Policy**: Use `-ExecutionPolicy Bypass` parameter
3. **Insufficient Disk Space**: Ensure adequate space for test files or adjust testfile size ( `-c10G` )
4. **Antivirus Interference**: Temporarily disable real-time scanning

## Performance Baselines

### SQL Server Storage Performance Baseline (8KB Random I/O):

- **HDD (7200 RPM):** 150-300 IOPS - Minimum for small databases
- **SATA SSD:** 8,000-25,000 IOPS - Standard for production systems
- **NVMe SSD:** 30,000-100,000 IOPS - Recommended for high-performance OLTP
- **Latency:** <8ms HDD, <0.5ms SATA SSD, <0.1ms NVMe

### SQL Server Specific Requirements

- **Data Files:** Minimum 1,000 IOPS per active database (8KB random I/O)
- **Log Files:** Minimum 500 IOPS, sequential write performance critical (64KB sequential)
- **TempDB:** Should be on fastest storage, requires high random I/O (NVMe preferred)
- **Backup:** Storage: Sequential throughput most important (100+ MB/s minimum)

### Production Minimum Requirements

- **Small DB** (<100GB): SATA SSD with 10,000+ IOPS
- **Medium DB** (100GB-1TB): NVMe with 40,000+ IOPS
- **Large DB** (>1TB): NVMe with 80,000+ IOPS or storage array

Bottleneck Warning: Below 100 IOPS SQL Server becomes noticeably slow, below 50 IOPS practically unusable.

## Compatibility

- Windows Server 2016 and later
- Windows 10 and later
- PowerShell 5.1 or later
- DISKSPD 2.0.21 or later

## License

This script is provided "as is" without warranty of any kind. You are free to use, modify, and distribute this script as you wish. No liability is assumed for any damages resulting from its use.

Attribution is appreciated but not required.