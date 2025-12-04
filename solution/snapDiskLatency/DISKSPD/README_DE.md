# SQL Server Disk Performance Testing mit DISKSPD

## Übersicht

Dieses Paket enthält ein PowerShell-Script für die Durchführung von Festplatten-Performance-Tests, die für SQL Server-Arbeitslasten optimiert sind und Microsoft's DISKSPD-Tool verwenden.

## Autor

Gabriel Köhl  
Site: https://dbavonnebenan.de  
Repository: https://github.com/gabrielkoehl/DBAScriptBox

## Offizielles DISKSPD Repository

Microsoft DISKSPD: https://github.com/microsoft/diskspd

## Scripts

### run_diskspd.ps1

Ein PowerShell-Script, das drei verschiedene Festplatten-Performance-Tests durchführt, die für SQL Server-Umgebungen optimiert sind. Jeder Test ist darauf ausgelegt, verschiedene I/O-Muster zu simulieren, die häufig in Datenbank-Arbeitslasten vorkommen.

**Hauptfunktionen:**
- SQL Server optimierter Test mit 8KB Block-Größe
- 64KB Random I/O-Test für allgemeine Performance-Bewertung
- 64KB Sequential I/O-Test für Durchsatz-Messung
- Automatische Ergebnisdatei-Generierung mit Zeitstempel
- Fehlerbehandlung und Bereinigung

**Test-Konfigurationen:**

1. **SQL Server Test** (`-b8K -d30 -h -L -o32 -t8 -r -w40 -c10G`)
   - Block-Größe: 8KB (SQL Server Page-Größe)
   - Dauer: 30 Sekunden
   - Outstanding I/O: 32 (simuliert gleichzeitige Transaktionen)
   - Threads: 8 (simuliert parallele Abfragen)
   - Schreibanteil: 40% (typische OLTP-Arbeitslast)

2. **64KB Random Test** (`-b64K -d120 -h -L -o16 -t8 -r -w40 -c2G`)
   - Block-Größe: 64KB
   - Dauer: 120 Sekunden
   - Outstanding I/O: 16
   - Random Access-Pattern

3. **64KB Sequential Test** (`-b64K -d120 -h -L -o16 -t8 -w40 -c10G`)
   - Block-Größe: 64KB
   - Dauer: 120 Sekunden
   - Outstanding I/O: 16
   - Sequential Access-Pattern

## DISKSPD Parameter Erklärung

- `-b8K` / `-b64K`: Block-Größe (8KB entspricht SQL Server Page-Größe)
- `-d30` / `-d120`: Testdauer in Sekunden
- `-h`: Deaktiviert Software- und Hardware-Caching
- `-L`: Aktiviert Large Pages für bessere Performance
- `-o32` / `-o16`: Outstanding I/O-Anfragen (Queue Depth)
- `-t8`: Anzahl der Threads (simuliert parallele Operationen)
- `-r`: Aktiviert Random I/O Access-Pattern
- `-w40`: Schreiboperationen-Prozentsatz (40% Schreibvorgänge, 60% Lesevorgänge)
- `-c10G` / `-c2G`: Testdatei-Größe

## Voraussetzungen

- Windows PowerShell 5.1 oder neuer
- Administrator-Rechte (empfohlen)
- DISKSPD-Executable im `bin`-Ordner
- Ausreichend Festplattenspeicher für Testdateien

## Verwendung

### Grundlegende Ausführung

```powershell
# DISKSPD-Ordner auf Zielfestplatte kopieren
# PowerShell-Konsole als Administrator ausführen
powershell -ExecutionPolicy Bypass .\run_diskspd.ps1
```

### Erweiterte Ausführung

```powershell
# Zum DISKSPD-Ordner navigieren
cd "<PFAD>\DBAScriptBox\perf_diskspeed\DISKSPD"

# Script mit Execution Policy Bypass ausführen
powershell -ExecutionPolicy Bypass .\run_diskspd.ps1
```

## Ausgabe-Dateien

Das Script generiert zeitgestempelte Ergebnisdateien im `output`-Ordner:

- `YYYYMMDD_HHmmss_diskspd_results_SQL.txt`: SQL Server optimierte Testergebnisse
- `YYYYMMDD_HHmmss_diskspd_results_64KB_RND.txt`: 64KB Random I/O-Testergebnisse
- `YYYYMMDD_HHmmss_diskspd_results_64KB_SEQ.txt`: 64KB Sequential I/O-Testergebnisse

## Dateistruktur

```
DISKSPD/
├── run_diskspd.ps1          # Haupt-PowerShell-Script
├── README.md                # Diese Dokumentation
├── bin/
│   ├── diskspd.exe         # DISKSPD-Executable
│   └── diskspd.pdb         # Debug-Symbole
└── output/                 # Wird während der Ausführung generiert
    ├── testfile.dat        # Temporäre Testdatei (wird automatisch gelöscht)
    └── *_diskspd_results_*.txt # Ergebnisdateien
```

## Best Practices

### Testumgebung

1. Den gesamten DISKSPD-Ordner auf die zu testende Zielfestplatte kopieren
2. PowerShell als Administrator starten
3. Zum DISKSPD-Ordner navigieren
4. Script ausführen: `powershell -ExecutionPolicy Bypass .\run_diskspd.ps1`
5. Konsolenausgabe für Fortschritts-Updates überwachen
6. Generierte Ergebnisdateien im `output`-Ordner überprüfen
7. Ergebnisse mit Ihren Performance-Anforderungen vergleichen

### Ergebnis-Interpretation

- **IOPS**: Fokus auf Random I/O-Ergebnisse für OLTP-Arbeitslasten
- **Durchsatz**: Sequential-Tests zeigen maximale Datenübertragungsraten
- **Latenz**: Niedrigere Latenz-Werte zeigen bessere Performance an
- **CPU-Verwendung**: CPU während Tests überwachen, um Bottlenecks zu identifizieren

### SQL Server-spezifische Überlegungen

- Der 8KB-Test simuliert am besten SQL Server Data Page I/O
- 40% Schreibanteil simuliert typische OLTP-Arbeitslasten
- Testparameter basierend auf Ihren spezifischen Workload-Mustern anpassen

## Fehlerbehebung

### Häufige Probleme

1. **Zugriff verweigert**: PowerShell als Administrator ausführen
2. **Execution Policy**: `-ExecutionPolicy Bypass` Parameter verwenden
3. **Unzureichender Festplattenspeicher**: Ausreichend Speicher für Testdateien sicherstellen oder Testdatei-Größe anpassen ( `-c10G` )
4. **Antivirus-Interferenz**: Echtzeit-Scanning temporär deaktivieren

## Performance-Baselines

### SQL Server Storage Performance Baseline (8KB Random I/O):

- **HDD (7200 RPM):** 150-300 IOPS - Minimum für kleine Datenbanken
- **SATA SSD:** 8.000-25.000 IOPS - Standard für Produktionssysteme
- **NVMe SSD:** 30.000-100.000 IOPS - Empfohlen für hochperformante OLTP
- **Latenz:** <8ms HDD, <0.5ms SATA SSD, <0.1ms NVMe

### SQL Server-spezifische Anforderungen

- **Data Files:** Minimum 1.000 IOPS pro aktiver Datenbank (8KB Random I/O)
- **Log Files:** Minimum 500 IOPS, Sequential Write Performance kritisch (64KB Sequential)
- **TempDB:** Sollte auf schnellstem Storage sein, benötigt hohes Random I/O (NVMe bevorzugt)
- **Backup Storage:** Sequential Durchsatz am wichtigsten (100+ MB/s minimum)

### Produktions-Mindestanforderungen

- **Kleine DB** (<100GB): SATA SSD mit 10.000+ IOPS
- **Mittlere DB** (100GB-1TB): NVMe mit 40.000+ IOPS
- **Große DB** (>1TB): NVMe mit 80.000+ IOPS oder Storage Array

Bottleneck-Warnung: Unter 100 IOPS wird SQL Server merklich langsam, unter 50 IOPS praktisch unbrauchbar.

## Kompatibilität

- Windows Server 2016 und neuer
- Windows 10 und neuer
- PowerShell 5.1 oder neuer
- DISKSPD 2.0.21 oder neuer

## Lizenz

Dieses Script wird "wie es ist" ohne jegliche Garantie bereitgestellt. Sie können dieses Script frei verwenden, modifizieren und verteilen. Keine Haftung wird für Schäden übernommen, die durch seine Verwendung entstehen.

Namensnennung wird geschätzt, ist aber nicht erforderlich.
