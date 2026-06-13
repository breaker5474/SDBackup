# SDBackup

[![zh](https://img.shields.io/badge/简体中文-blue.svg)](README.md)
[![en](https://img.shields.io/badge/English-red.svg)](README_en.md)

macOS menu bar application for automatic SD card backup. Designed for photographers and videographers who need reliable, hands-free transfer of photos and videos from camera storage cards to your Mac.

---

## Features

### Automatic Backup

Insert an SD card and SDBackup starts copying immediately. Supports multiple cards with a sequential queue -- insert two cards and both will be backed up one after another.

### Multi-Source Directory Selection

Choose specific folders to back up (DCIM, CLIP, PRIVATE, etc.) or leave empty to back up everything. Each card remembers its own source configuration.

### File Format Filtering

Filter by file extension in include or exclude mode. Default profile covers common photography formats: ARW, CR2, CR3, JPG, HEIF, MOV, MP4, XML. Skip thumbnails, databases, and other junk files automatically.

### Data Integrity Verification

Three verification levels:

- **Basic**: Compare file size and modification date
- **MD5**: Hash-based verification after transfer
- **SHA256**: Full cryptographic verification with system notification on corruption

### Backup Strategy

- **Update if modified** (default): Skip unchanged files, re-transfer modified ones
- **Skip existing**: Never overwrite files already at the destination

### Transfer Estimation

Before the real transfer begins, a dry run calculates how many files and how many megabytes will be copied, with an estimated completion time.

### Backup Statistics

Completion notifications break down transferred files by category: photos, videos, metadata, and other.

### Dual Destination with Fallback

Set a primary backup path (external drive) and an optional local fallback path. If the external drive is not connected, SDBackup writes to the fallback automatically. When the external drive reconnects, cached files are migrated over.

### Card Health Monitoring

Tracks consecutive IO errors per card. After three failures, SDBackup warns that the card may be failing and should be replaced.

### Crash Recovery

A lock file prevents concurrent backups to the same destination. A state file tracks transfer progress every 10 files. If the app or system crashes mid-backup, SDBackup detects the stale state on next launch and notifies you.

### Transfer History

Full log of all backup attempts with timestamp, source device, destination, file count, data size, duration, and status. Export to CSV for record keeping.

### Card Renaming

Assign custom names to your storage cards for easier identification in the menu bar and settings.

---

## Screenshots

### Menu Bar

![Menu Bar](Screenshots/menu_bar.png)

### Backup Settings

![Backup Settings](Screenshots/backup_settings.png)

### Advanced Settings

![Advanced Settings](Screenshots/advanced_settings.png)

### Transfer History

![Transfer History](Screenshots/transfer_history.png)

### Other Settings

![Other Settings](Screenshots/other_settings.png)

---

## Installation

1. Download `SDBackup-1.0.0.dmg` from [Releases](https://github.com/breaker5474/SDBackup/releases)
2. Open the DMG and drag `SDBackup.app` into your Applications folder
3. Launch SDBackup -- it appears in the menu bar
4. Open Settings to configure your backup destination

## System Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon or Intel Mac

## Building from Source

```bash
git clone https://github.com/breaker5474/SDBackup.git
cd SDBackup
swift build -c release
```

Build DMG:

```bash
bash Scripts/build_dmg.sh
```

## License

MIT

## Developer

NanYang (南洋NanYang)

- WeChat: Nany8753
- Email: breaker5474@gmail.com
