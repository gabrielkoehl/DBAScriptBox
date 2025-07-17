# SQL Server Disk Latency Monitoring Scripts

## Überblick

Dieses Paket enthält zwei Stored Procedures zur Überwachung und Analyse von Disk I/O Latency-Statistiken in SQL Server Umgebungen.

## Autor

Gabriel Köhl  
Website: https://dbavonnebenan.de  
Repository: https://github.com/gabrielkoehl/DBAScriptBox

## Scripts

### usp_snapCollectDiskLatencyStats.sql

Sammelt Disk I/O Latency-Statistiken von SQL Server und speichert sie in einer permanenten Tabelle zur Analyse. Konzipiert für die Ausführung als Teil eines Agent Jobs zur regelmäßigen Überwachung der Disk-Performance.

**Hauptfunktionen:**
- Sammelt Daten aus sys.dm_io_virtual_file_stats
- Speichert historische Snapshots in einer permanenten Tabelle
- Erstellt automatisch erforderliche Tabellen und Indizes
- Schließt Systemdatenbanken aus (master, model, msdb)

**Empfohlene Nutzung:**
- Ausführung in Intervallen von mindestens 1 Stunde für aussagekräftige Statistiken
- Kürzere Intervalle können zu unzuverlässigen Delta-Berechnungen führen
- Optimal geeignet für SQL Server Agent Job Scheduling

### usp_snapReportDiskLatencyStats.sql

Analysiert Disk I/O Latency-Daten und liefert Statistiken für die Performance-Analyse. Unterstützt sowohl historische Analyse aus gespeicherten Snapshots als auch aktuelle Zustandsanalyse direkt aus DMVs.

**Hauptfunktionen:**
- Historische Analyse aus gespeicherten Daten mit Delta-Berechnungen
- Aktuelle Zustandsanalyse aus sys.dm_io_virtual_file_stats
- Berechnet durchschnittliche Latenzen pro I/O-Operation
- Liefert Read/Write-Operationszähler und Datentransfer-Statistiken
- Dateianzahl-Aggregation nach Datenbank und Dateityp

**Analyse-Modi:**
- Historisch: Analysiert gespeicherte Snapshots mit konfigurierbaren Zeiträumen
- Aktueller Zustand: Direkte Analyse aus DMVs ohne historische Daten

## Parameter

### usp_snapCollectDiskLatencyStats

- `@ArchiveDatabase` (NVARCHAR(128), erforderlich): Datenbank zur Speicherung der Latency-Daten
- `@SchemaName` (NVARCHAR(128), Standard: 'dbo'): Schema für die Latency-Tabelle
- `@TableName` (NVARCHAR(128), Standard: 'reportDiskLatency'): Tabellenname zur Speicherung der Statistiken

### usp_snapReportDiskLatencyStats

- `@ArchiveDatabase` (NVARCHAR(128), erforderlich für historische Analyse): Datenbank mit historischen Daten
- `@SchemaName` (NVARCHAR(128), Standard: 'dbo'): Schema mit der Latency-Tabelle
- `@TableName` (NVARCHAR(128), Standard: 'reportDiskLatency'): Tabelle mit historischen Daten
- `@HoursBack` (INT, Standard: 24): Stunden für Rückblick bei historischer Analyse
- `@DatabaseName` (NVARCHAR(128), Standard: NULL): Filter für spezifische Datenbank (optional)
- `@FileType` (NVARCHAR(20), Standard: NULL): Filter für spezifischen Dateityp ('DATA', 'LOG', oder NULL für alle)
- `@fromDM` (BIT, Standard: 0): Analyse-Modus (0 = historisch, 1 = aktueller Zustand)

## Verwendungsbeispiele

### Datensammlung

```sql
-- Grundlegende Sammlung
EXEC usp_snapCollectDiskLatencyStats
    @ArchiveDatabase = 'SqlDba';

-- Benutzerdefiniertes Schema und Tabelle
EXEC usp_snapCollectDiskLatencyStats 
    @ArchiveDatabase = 'SqlDba', 
    @SchemaName      = 'monitoring', 
    @TableName       = 'disk_latency_stats';
```

### Datenanalyse

```sql
-- Historische Analyse (letzte 24 Stunden)
EXEC usp_snapReportDiskLatencyStats
    @ArchiveDatabase = 'SqlDba';

-- Historische Analyse (letzte 48 Stunden)
EXEC usp_snapReportDiskLatencyStats
    @ArchiveDatabase = 'SqlDba',
    @HoursBack       = 48;

-- Aktuelle Zustandsanalyse
EXEC usp_snapReportDiskLatencyStats 
    @fromDM = 1;

-- Filter nach spezifischer Datenbank und Dateityp
EXEC usp_snapReportDiskLatencyStats 
    @ArchiveDatabase = 'SqlDba', 
    @DatabaseName    = 'MyDatabase',
    @FileType        = 'DATA';

-- Filter nur nach Log-Dateien
EXEC usp_snapReportDiskLatencyStats 
    @ArchiveDatabase = 'SqlDba', 
    @FileType        = 'LOG';

-- Benutzerdefinierte Tabellenanalyse mit Filtern
EXEC usp_snapReportDiskLatencyStats 
    @ArchiveDatabase = 'SqlDba', 
    @SchemaName      = 'monitoring', 
    @TableName       = 'disk_latency_stats', 
    @DatabaseName    = 'MyDatabase',
    @HoursBack       = 12;
```

## Implementierungsschritte

1. Beide Stored Procedures in Ihrer SQL Server Instanz bereitstellen
2. Einen SQL Server Agent Job erstellen, der `usp_snapCollectDiskLatencyStats` stündlich ausführt (siehe Beispiel-Script unten)
3. `usp_snapReportDiskLatencyStats` für Analyse und Reporting verwenden
4. Ergebnisse überwachen und Sammlungsintervalle nach Bedarf anpassen

## SQL Server Agent Job Beispiel

Das folgende Script erstellt einen SQL Server Agent Job, der die Sammlung-Procedure stündlich ausführt:

```sql
-- SQL Server Agent Job für Disk Latency Datensammlung erstellen
USE msdb;
GO

-- Job erstellen
EXEC dbo.sp_add_job
    @job_name               = N'adm_collectDiskLatency',
    @enabled                = 1,
    @description            = N'Sammelt stündlich Disk I/O Latency-Statistiken für Performance-Monitoring',
    @start_step_id          = 1,
    @category_name          = N'[Uncategorized (Local)]',
    @owner_login_name       = N'sa';

-- Job Step erstellen
EXEC dbo.sp_add_jobstep
    @job_name               = N'adm_collectDiskLatency',
    @step_name              = N'Collect Latency Stats',
    @step_id                = 1,
    @cmdexec_success_code   = 0,
    @on_success_action      = 1,
    @on_fail_action         = 2,
    @retry_attempts         = 0,
    @retry_interval         = 0,
    @os_run_priority        = 0,
    @subsystem              = N'TSQL',
    @command                = N'EXEC usp_snapCollectDiskLatencyStats @ArchiveDatabase = ''SqlDba'';',
    @database_name          = N'master',
    @flags                  = 0;

-- Schedule erstellen (läuft jede Stunde)
EXEC dbo.sp_add_schedule
    @schedule_name          = N'Hourly Collection',
    @enabled                = 1,
    @freq_type              = 4,
    @freq_interval          = 1,
    @freq_subday_type       = 8,
    @freq_subday_interval   = 1,
    @freq_relative_interval = 0,
    @freq_recurrence_factor = 0,
    @active_start_date      = 20250101,
    @active_end_date        = 99991231,
    @active_start_time      = 0,
    @active_end_time        = 235959;

-- Schedule an Job anhängen
EXEC dbo.sp_attach_schedule
    @job_name               = N'adm_collectDiskLatency',
    @schedule_name          = N'Hourly Collection';

-- Job zum Zielserver hinzufügen
EXEC dbo.sp_add_jobserver
    @job_name               = N'adm_collectDiskLatency',
    @server_name            = N'(local)';

-- Optional: Job sofort starten
-- EXEC dbo.sp_start_job @job_name = N'adm_collectDiskLatency';
```

**Hinweis:** Passen Sie den `@ArchiveDatabase` Parameter im Job Step Command an Ihren Zieldatenbanknamen an.

## Ausgabespalten

Die Report-Procedure gibt folgende Spalten zurück:

- `DateTime`: Zeitstempel der Analyse
- `Period`: Beschreibung des Zeitraums
- `Database`: Datenbankname
- `FileType`: Dateityp (Data File, Transaction Log)
- `AvgReadLatency_ms`: Durchschnittliche Read-Latency pro I/O-Operation
- `AvgWriteLatency_ms`: Durchschnittliche Write-Latency pro I/O-Operation
- `AvgTotalLatency_ms`: Durchschnittliche Gesamt-Latency pro I/O-Operation
- `TotalReads`: Gesamtanzahl Read-Operationen
- `TotalWrites`: Gesamtanzahl Write-Operationen
- `TotalReadKB`: Gesamte gelesene Daten in KB
- `TotalWriteKB`: Gesamte geschriebene Daten in KB
- `TotalReadPages`: Gesamte gelesene Pages (8KB Pages)
- `TotalWritePages`: Gesamte geschriebene Pages (8KB Pages)
- `FileCount`: Anzahl Dateien pro Datenbank und Dateityp

## Kompatibilität

SQL Server 2019 und später getestet

## Lizenz

Dieses Script wird "wie besehen" ohne jegliche Gewährleistung zur Verfügung gestellt. Sie können dieses Script frei verwenden, modifizieren und verteilen. Für eventuelle Schäden durch die Verwendung wird keine Haftung übernommen.

Eine Quellenangabe ist erwünscht, aber nicht erforderlich.
