# SQL Server Block Event Reporter

Ein PowerShell-basiertes Tool zur Analyse von SQL Server Blocking Events und Deadlocks unter Verwendung von Extended Events.

## Übersicht

**Diese Lösung ermöglicht:**
- Automatische Erfassung von Blocking Events und Deadlocks
- Detaillierte Textreports für einzelne Events
- Aggregierte Excel-Berichte mit grafischer Auswertung
- Flexible Zeitraumanalyse
- Automatische Berichtsarchivierung

## Voraussetzungen

- Windows PowerShell 5.1 oder höher
- SQL Server 2016 oder höher
- PowerShell Module:
  - dbatools
  - ImportExcel

Installation der benötigten Module:
```powershell
Install-Module dbatools
Install-Module ImportExcel
```

## Berechtigungen

Für die Ausführung des Scripts werden folgende Berechtigungen benötigt ([microsoft.com](https://learn.microsoft.com/de-de/sql/relational-databases/system-functions/sys-fn-xe-file-target-read-file-transact-sql?view=sql-server-ver16)):

- SQL 2019 und älter: VIEW SERVER STATE
- SQL 2022 und neuer: VIEW SERVER PERFORMANCE STATE
- Lesezugriff auf den Pfad mit den XEL-Dateien

## Installation

1. Repository klonen oder alle Dateien in ein Verzeichnis entpacken
2. Mit der Datei "create_XE.sql" die Extended Event Session auf dem entsprechenden SQL Server anlegen (vorab Parameter anpassen!)

### Extended Events Session (create_XE.sql)

Hauptparameter der XE-Session:

```sql
DECLARE @session_name NVARCHAR(128)     = N'blocked_process'
DECLARE @file_path NVARCHAR(260)        = N'D:\USERDATA\extendedEvents'
DECLARE @max_file_size INT              = 1024
DECLARE @max_rollover_files INT         = 1
DECLARE @startup_state BIT              = 0  -- 0 = OFF, 1 = ON
```

Das SQL-Script gibt im Message-Blog folgenden Output:

```
Path for report generation
--------------------------
 
	D:\USERDATA\extendedEvents\blocked_process*.xel
	D:\USERDATA\extendedEvents\blocked_process*.xem
 
--------------------------
```

Dies sind die Pfade, welche für das eigentliche PowerShell-Script benötigt werden. Entweder werden sie als Default in den Script-Parametern hinterlegt, wenn nur eine Instanz überwacht wird, oder sie müssen beim Aufruf mitgegeben werden.

## Verwendung

### Parameter

| Parameter | Typ | Mandatory | Default | Beschreibung |
|-----------|-----|-----------|---------|-------------|
| `-eventFilePath` | String | Ja | - | Pfad zu den XE-Dateien (*.xel) |
| `-metaFilePath` | String | Ja | - | Pfad zu den XE-Metadaten (*.xem) |
| `-SqlInstance` | String | Ja | - | SQL Server Instance-Name mit konfigurierten Extended Events |
| `-reportRoot` | String | Nein | "$(Join-Path $(Split-Path -Parent $MyInvocation.MyCommand.Path) "_report")" | Pfad zum Reportverzeichnis |
| `-StartTime` | DateTime | Nein | (Get-Date).AddHours(-24) | Startzeit der Analyse |
| `-EndTime` | DateTime | Nein | $(Get-Date) | Endzeit der Analyse |
| `-hoursBack` | Int | Nein | 2 | Alternative Zeitspanne (Start: Now-hoursBack, Ende: Now) |
| `-ChartIntervalMinutes` | Int | Nein | 60 | Intervall für die Excel-Grafik in Minuten |
| `-returnSummary` | Switch | Nein | $false | Gibt eine Tabelle zurück mit der Anzahl der Events pro Datenbank |
| `-excel` | Switch | Nein | $false | Erstellt Excel-Zusammenfassung |
| `-cleanUp` | Switch | Nein | $false | Bereinigt Report-Dateien älter als cleanUpDays |
| `-cleanUpDays` | Int | Nein | 30 | Anzahl der Tage für die Bereinigung |

### Basis-Aufruf

```powershell
.\Run-BlockEventReport.ps1 -eventFilePath 'D:\USERDATA\extendedEvents\blocked_process*.xel' -metaFilePath 'D:\USERDATA\extendedEvents\blocked_process*.xem' -SqlInstance 'DEV-NODE1\DEV22A'
```

### Beispiele

```powershell
# Mit ISO-Datumsformat
.\Run-BlockEventReport.ps1 -SqlInstance 'DEV-NODE1\DEV22A' -StartTime "2025-04-25 08:00" -EndTime "2025-04-25 18:00" -eventFilePath 'D:\USERDATA\extendedEvents\blocked_process*.xel' -metaFilePath 'D:\USERDATA\extendedEvents\blocked_process*.xem'

# Nur Datum (setzt Zeit auf 00:00 Uhr)
.\Run-BlockEventReport.ps1 -SqlInstance 'DEV-NODE1\DEV22A' -StartTime "2023-11-20" -EndTime "2023-11-21" -eventFilePath 'D:\USERDATA\extendedEvents\blocked_process*.xel' -metaFilePath 'D:\USERDATA\extendedEvents\blocked_process*.xem'

# Mit Excel-Erstellung und Bereinigung
.\Run-BlockEventReport.ps1 -SqlInstance 'DEV-NODE1\DEV22A' -hoursBack 2 -eventFilePath 'D:\USERDATA\extendedEvents\blocked_process*.xel' -metaFilePath 'D:\USERDATA\extendedEvents\blocked_process*.xem' -excel -cleanUp -cleanUpDays 14
```

## Berichtsstruktur

```
_report/
├── text_reports/
│   └── YYYY/
│       └── MM/
│           └── DD/
│               ├── 20231120_123456_dbname_blocked.txt
│               ├── 20231120_123456_dbname_blocked.xml
│               ├── 20231120_123456_dbname_deadlock.txt
│               └── 20231120_123456_dbname_deadlock.xml
└── excel_reports/
    └── BlockReport_20231120_123456.xlsx
```

### Text-Reports
- Detaillierte Analyse einzelner Block- oder Deadlock-Events
- Enthält SQL-Statements, Prozess-Details und Ressourceninformationen
- Zeitstempel im Dateinamen für einfache Zuordnung

### Excel-Report
- Übersichtsgrafik der Events pro Zeitintervall
- "Overview"-Tab mit aggregierten Daten
- "BlockedDetails"- und "DeadlockDetails"-Tabs mit Einzelereignissen

## Fehlerbehebung

1. **Keine Events gefunden**
   - Läuft die Extended Event Session?
   - Dateipfade zu den XEL/XEM-Dateien überprüfen
   - Zeitraum überprüfen
   - Direkt im SQL Server Management Studio das Event File prüfen

2. **Zugriffsprobleme**
   - Ausführender Benutzer benötigt:
     - Entsprechende Berechtigungen auf der SQL Server Instance
     - Leserechte für die XEL/XEM-Dateien
     - Schreibrechte im Report-Verzeichnis

## Hinweise

- Die Text-Reports werden nach Datum strukturiert archiviert
- Excel-Reports enthalten eine visuelle Auswertung der Events
- Deadlocks und Blocking Events werden getrennt ausgewertet
- Bei Verwendung des Parameters `-returnSummary` kann die Ausgabe in einer PowerShell-Variable gespeichert werden

## Lizenz

GNU GPL - See LICENSE file