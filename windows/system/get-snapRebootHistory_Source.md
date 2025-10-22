## Event IDs

| Event ID | Description |
|----------|-------------|
| **1074** | Shutdown/Restart initiated |
| **6005** | Event Log started (System boot) |
| **6006** | Event Log stopped (Clean shutdown) |
| **6008** | Unexpected shutdown |
| **6009** | System boot with OS Info |
| **41** | Unexpected reboot (Crash/Power loss) |

**Source:** [Microsoft Learn - Troubleshoot unexpected reboots](https://learn.microsoft.com/en-us/troubleshoot/windows-server/performance/troubleshoot-unexpected-reboots-system-event-logs)

---

## Reason Codes (Event ID 1074)

| Code | Description |
|------|-------------|
| **0x80020002** | Application (software request) |
| **0x80020003** | Operating System (software request) |
| **0x50000010** | System failure (critical stop) |
| **0x50000018** | Security issue |
| **0x500000ff** | Other system failure |
| **0x800000ff** | Power failure / Other |
| **0x400000ff** | User initiated (other) |
| **0x40010004** | User initiated (planned) |
| **0x80000000** | Legacy API shutdown |

**Sources:**
- [Microsoft Learn - System Shutdown Reason Codes](https://learn.microsoft.com/en-us/windows/win32/shutdown/system-shutdown-reason-codes)
- [Microsoft Q&A - Server rebooted unknowingly](https://learn.microsoft.com/en-us/answers/questions/1373506/server-rebooted-unknowingly)
- [Stack Overflow - Exit code 0x40010004](https://stackoverflow.com/questions/37078953/in-which-cases-does-program-exit-with-0x40010004-code)

---

## Additional Sources

- [Server Fault - Windows Server restart/shutdown history](https://serverfault.com/questions/702828/windows-server-restart-shutdown-history)
- [Windows Central - Find shutdown reason](https://www.windowscentral.com/how-find-reason-pc-shutdown-no-reason-windows-10)
- [AccuWebHosting - Check shutdown logs](https://manage.accuwebhosting.com/knowledgebase/3897/How-to-check-shutdown-and-reboot-logs-in-Windows-servers.html)