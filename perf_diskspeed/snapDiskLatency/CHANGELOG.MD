
2025-07-23
--------------

    usp_snapReportDiskLatencyStats
    ------------------------------

    Problem: Chart gaps and distorted average values due to missing inactive periods

    Fixes
        Added CompleteMatrix CTE for full time series coverage
        LEFT JOIN instead of filtering inactive periods
        ISNULL() shows 0 values instead of missing data
        FORMAT() for clean DateTime output
    Changes
        Removed Period column (useless)
