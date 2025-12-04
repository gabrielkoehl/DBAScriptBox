function format-SnapSqlLockReport {
    param (
        [Parameter(Mandatory=$true)]
        [string]$XmlContent
    )


    function Format-DeadlockXml {
        param (
            [xml]$XmlContent
        )

        # Extract relevant information from the XML
        $deadlockGraph      = $XmlContent.deadlock
        $victimList         = $deadlockGraph.'victim-list'.victimProcess
        $processList        = $deadlockGraph.'process-list'.process

        # Begin output
        $eventTime = $deadlockGraph.'process-list'.process |
                            Select-Object -First 1 -ExpandProperty lasttranstarted -ErrorAction SilentlyContinue

        if ( -not $eventTime ) {
            $eventTime = Get-Date
        }

        $output = "SQL Server Deadlock Analysis | Event Time: $eventTime`n"
        $output += "=" * 80 + "`n`n"

        # SQL Statements Summary
        $output += "SQL STATEMENTS INVOLVED`n"
        $output += "-" * 80 + "`n`n"

        foreach ( $process in $processList ) {

            $output += "`tProcess ID:   $($process.id)`n"
            $output += "`tSPID:         $($process.spid)`n"
            $output += "`tDatabase:     $($process.currentdbname)`n"

            if ( $process.inputbuf ) {

                $sql    = $process.inputbuf.Trim()
                $output += "`tQuery:        $sql`n`n"

            }

            $output += "-" * 40 + "`n`n"

        }

        # Victim list
        $output += "VICTIM LIST`n"
        $output += "-" * 80 + "`n`n"

        foreach ( $victim in $victimList ) {

            $victimProcess = $processList | Where-Object { $_.id -eq $victim.id }
            $output += "`tProcess ID:   $($victim.id)`n"

            if ( $victimProcess ) {

                $output += "`tSPID:         $($victimProcess.spid)`n"
                $output += "`tDatabase:     $($victimProcess.currentdbname)`n"

            }
        }

        $output += "`n"

        # Process list
        $output += "`nPROCESS LIST`n"
        $output += "-" * 80 + "`n`n"

        foreach ( $process in $processList ) {

            $output += "`tProcess ID:               $($process.id)`n"
            $output += "`tSPID:                     $($process.spid)`n"
            $output += "`tIsolation Level:          $($process.isolationlevel)`n"
            $output += "`tLogical Reads:            $($process.logused)`n"
            $output += "`tWait Resource:            $($process.waitresource)`n"
            $output += "`tWait Time (ms):           $($process.waittime)`n"
            $output += "`tTransaction:              $($process.transactionname)`n"
            $output += "`tLast Transaction Started: $($process.lasttranstarted)`n"
            $output += "`tClient:                   $($process.clientapp)`n"
            $output += "`tHostname:                 $($process.hostname)`n"
            $output += "`tUser:                     $($process.loginname)`n"

            # Input Buffer (SQL Statement)
            $output += "`n`nEXECUTED SQL STATEMENT`n"
            $output += "-" * 40 + "`n`n"

            if ( $process.inputbuf ) {

                $output += "`t$($process.inputbuf.Trim())`n"

            } else {

                $output += "`tNo SQL Statement available`n"

            }

            $output += "`n`nProcess Details`n"
            $output += "" + "=" * 80 + "`n`n`n"

        }

        # Resource list
        $output += "RESOURCE LIST`n"
        $output += "-" * 80 + "`n`n"

        # Handle different resource types in the resource-list
        foreach ( $resource in $deadlockGraph.'resource-list'.ChildNodes ) {

            $resourceType   = $resource.LocalName
            $output         += "`tResource:`n"
            $output         += "`t`tType:               $resourceType`n"

            # Different properties depending on resource type
            switch ( $resourceType ) {
                "keylock" {
                    $output += "`t`tDatabase:           $($resource.dbid)`n"
                    $output += "`t`tObject:             $($resource.objectname)`n"
                    $output += "`t`tIndex:              $($resource.indexname)`n"
                    $output += "`t`tLock Mode:          $($resource.mode)`n"
                    $output += "`t`tHOBT ID:            $($resource.hobtid)`n"

                    if ( $resource.associatedObjectId ) {

                        $output += "`t`tAssociated Object ID: $($resource.associatedObjectId)`n"

                    }
                }
                "pagelock" {
                    $output += "`t`tDatabase:           $($resource.dbid)`n"
                    $output += "`t`tObject:             $($resource.objectname)`n"
                    $output += "`t`tPage:               $($resource.pageid)`n"
                    $output += "`t`tLock Mode:          $($resource.mode)`n"
                }
                "objectlock" {
                    $output += "`t`tDatabase:           $($resource.dbid)`n"
                    $output += "`t`tObject:             $($resource.objectname)`n"
                    $output += "`t`tLock Mode:          $($resource.mode)`n"
                }
                default {
                    # List all attributes if specific type is unknown
                    foreach ( $attr in $resource.Attributes ) {
                        if ( $attr.Name -and $attr.Value ) {
                            $output += "`t`t$($attr.Name):      $($attr.Value)`n"
                        }
                    }
                }
            }

            # Owner list
            $output += "`n`tOwners:`n"
            foreach ( $owner in $resource.'owner-list'.owner ) {

                $output += "`t`tProcess ID:         $($owner.id), Mode: $($owner.mode)`n"

            }

            # Waiter list
            $output += "`n`tWaiting Processes:`n"
            foreach ( $waiter in $resource.'waiter-list'.waiter ) {

                $output += "`t`tProcess ID:         $($waiter.id), Mode: $($waiter.mode), Request Type: $($waiter.requestType)`n"

            }

            $output += "`n" + "=" * 80 + "`n`n"
        }

        return $output
    }

    function Format-BlockedProcessReport {
        param (
            [xml]$XmlContent
        )

        # Extract relevant information from the XML
        $blockedProcessReport   = $XmlContent.'blocked-process-report'
        $blockedProcess         = $blockedProcessReport.'blocked-process'.process
        $blockingProcess        = $blockedProcessReport.'blocking-process'.process

        # Begin output
        $eventTime = $blockedProcess.lastbatchstarted

        if ( -not $eventTime ) {
            $eventTime = Get-Date
        }

        $output = "SQL Server Blocked Process Analysis | Event Time: $eventTime`n"
        $output += "=" * 80 + "`n`n"
        $output += "Monitor Loop: $($blockedProcessReport.monitorLoop)`n`n"

        # Blocked process
        $output += "BLOCKED PROCESS`n"
        $output += "-" * 80 + "`n"
        $output += "`tProcess ID:           $($blockedProcess.id)`n"
        $output += "`tSPID:                 $($blockedProcess.spid)`n"
        $output += "`tStatus:               $($blockedProcess.status)`n"
        $output += "`tIsolation Level:      $($blockedProcess.isolationlevel)`n"
        $output += "`tTransaction ID:       $($blockedProcess.xactid)`n"
        $output += "`tWait Resource:        $($blockedProcess.waitresource)`n"
        $output += "`tWait Time (ms):       $($blockedProcess.waittime)`n"
        $output += "`tLock Mode:            $($blockedProcess.lockMode)`n"
        $output += "`tDatabase:             $($blockedProcess.currentdbname) (ID: $($blockedProcess.currentdb))`n"
        $output += "`tClient:               $($blockedProcess.clientapp)`n"
        $output += "`tHostname:             $($blockedProcess.hostname)`n"
        $output += "`tUser:                 $($blockedProcess.loginname)`n"
        $output += "`tTimeout (ms):         $($blockedProcess.lockTimeout)`n"


        # Execution Stack
        if ($blockedProcess.executionStack -and $blockedProcess.executionStack.frame) {
            $output += "`nEXECUTION STACK`n"
            $output += "-" * 40 + "`n"
            $frames = $blockedProcess.executionStack.frame

            # Handle both single frame and multiple frames
            if ( $frames -is [array] ) {

                $hasFrames = $false

                foreach ( $frame in $frames ) {

                    if ( ![string]::IsNullOrWhiteSpace($frame.procname) -or ![string]::IsNullOrWhiteSpace($frame.line) ) {

                        $output     += "`tProcedure: $($frame.procname), Line: $($frame.line), SQL Handle: $($frame.sqlhandle)`n"
                        $hasFrames  = $true

                    } elseif (![string]::IsNullOrWhiteSpace($frame.InnerText)) {

                        $output     += "`t$($frame.InnerText.Trim())`n"
                        $hasFrames  = $true

                    }

                }

                if ( -not $hasFrames ) {

                    $output += "`t<No execution stack information available>`n"

                }

            } else {

                # Single frame
                if ( ![string]::IsNullOrWhiteSpace($frames.procname) -or ![string]::IsNullOrWhiteSpace($frames.line) ) {

                    $output += "`tProcedure: $($frames.procname), Line: $($frames.line), SQL Handle: $($frames.sqlhandle)`n"

                } elseif ( ![string]::IsNullOrWhiteSpace($frames.InnerText) ) {

                    $output += "`t$($frames.InnerText.Trim())`n"

                } else {

                    $output += "`t<No execution stack information available>`n"

                }
            }
        }

        # Input Buffer (SQL Statement)
        $output += "`n`nEXECUTED SQL STATEMENT (BLOCKED)`n"
        $output += "-" * 40 + "`n"
        $output += "`t`t$($blockedProcess.inputbuf)`n"
        $output += "`n" + "=" * 80 + "`n`n"

        # Blocking process
        $output += "BLOCKING PROCESS`n"
        $output += "-" * 80 + "`n"
        $output += "`tSPID:                 $($blockingProcess.spid)`n"
        $output += "`tStatus:               $($blockingProcess.status)`n"
        $output += "`tTransaction:          $($blockingProcess.trancount)`n"
        $output += "`tIsolation Level:      $($blockingProcess.isolationlevel)`n"
        $output += "`tTransaction ID:       $($blockingProcess.xactid)`n"
        $output += "`tDatabase:             $($blockingProcess.currentdbname) (ID: $($blockingProcess.currentdb))`n"
        $output += "`tClient:               $($blockingProcess.clientapp)`n"
        $output += "`tHostname:             $($blockingProcess.hostname)`n"
        $output += "`tUser:                 $($blockingProcess.loginname)`n"
        $output += "`tLast Batch Started:   $($blockingProcess.lastbatchstarted)`n"
        $output += "`tLast Batch Completed: $($blockingProcess.lastbatchcompleted)`n"


        # Input Buffer (SQL Statement)
        $output += "`nEXECUTED SQL STATEMENT (BLOCKING)`n"
        $output += "-" * 40 + "`n"
        $output += "`t`t$($blockingProcess.inputbuf)`n"
        $output += "`n" + "=" * 80 + "`n`n"

        # Summary and recommendations
        $output += "SUMMARY`n"
        $output += "-" * 80 + "`n"
        $output += "`tBlocking Scenario:    SPID $($blockingProcess.spid) blocking SPID $($blockedProcess.spid)`n"
        $output += "`tWait Time:            $([math]::Round($blockedProcess.waittime / 1000, 2)) seconds`n"
        $output += "`tResource:             $($blockedProcess.waitresource)`n"
        $output += "`tLock Mode Requested:  $($blockedProcess.lockMode)`n"

        return $output

    }

    try {

        [xml]$xmlObj = $XmlContent

        # Detect report type and call corresponding formatting function
        if ( $null -ne $xmlObj.deadlock ) {

            Write-Verbose "Deadlock XML detected"
            return Format-DeadlockXml -XmlContent $xmlObj

        } elseif ( $null -ne $xmlObj.'blocked-process-report' ) {

            Write-Verbose "Blocked-Process Report detected"
            return Format-BlockedProcessReport -XmlContent $xmlObj

        } else {

            return "ERROR: Unknown XML type. Neither Deadlock nor Blocked-Process Report detected."

        }

    } catch {

        return "ERROR processing XML content: $_"

    }

}
