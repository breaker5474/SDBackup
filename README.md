# SDBackup

macOS menu bar application for automatic SD card backup. Designed for photographers and videographers who need reliable, hands-free transfer of photos and videos from camera storage cards to your Mac.

macOS 菜单栏应用，用于 SD 卡自动备份。面向摄影师和视频创作者，将相机存储卡中的照片和视频可靠地传输到 Mac。

---

## Features / 功能

### Automatic Backup / 自动备份

Insert an SD card and SDBackup starts copying immediately. Supports multiple cards with a sequential queue -- insert two cards and both will be backed up one after another.

插入 SD 卡即开始复制，无需手动操作。支持多卡排队，插入两张卡按顺序逐一备份。

### Multi-Source Directory Selection / 多源目录选择

Choose specific folders to back up (DCIM, CLIP, PRIVATE, etc.) or leave empty to back up everything. Each card remembers its own source configuration.

指定要备份的目录（DCIM、CLIP、PRIVATE 等），留空则备份全部内容。每张卡独立记忆自己的目录配置。

### File Format Filtering / 文件格式过滤

Filter by file extension in include or exclude mode. Default profile covers common photography formats: ARW, CR2, CR3, JPG, HEIF, MOV, MP4, XML. Skip thumbnails, databases, and other junk files automatically.

按扩展名过滤，支持包含和排除两种模式。默认覆盖常见摄影格式。自动跳过缩略图、数据库等无关文件。

### Data Integrity Verification / 数据完整性校验

Three verification levels:

三种校验级别：

- **Basic / 基础校验**: Compare file size and modification date. / 比对文件大小和修改日期。
- **MD5**: Hash-based verification after transfer. / 传输后计算哈希值比对。
- **SHA256**: Full cryptographic verification with system notification on corruption. / 完整加密校验，发现损坏时推送系统通知。

### Backup Strategy / 备份策略

- **Update if modified / 更新已修改文件** (default): Skip unchanged files, re-transfer modified ones. / 跳过未变化的文件，重新传输已修改的文件。
- **Skip existing / 跳过已存在文件**: Never overwrite files already at the destination. / 不覆盖目标路径中已有的文件。

### Transfer Estimation / 传输预估

Before the real transfer begins, a dry run calculates how many files and how many megabytes will be copied, with an estimated completion time.

正式传输前执行预演，计算待传输的文件数量和数据大小，显示预计完成时间。

### Backup Statistics / 备份统计

Completion notifications break down transferred files by category: photos, videos, metadata, and other.

完成通知按类型分类：照片、视频、元数据、其他。

### Dual Destination with Fallback / 双目标路径 + 临时缓存

Set a primary backup path (external drive) and an optional local fallback path. If the external drive is not connected, SDBackup writes to the fallback automatically. When the external drive reconnects, cached files are migrated over.

设置主备份路径（移动硬盘）和可选的本地临时路径。外接硬盘未连接时自动写入临时路径，重新连接后自动迁移缓存数据。

### Card Health Monitoring / 存储卡健康度监测

Tracks consecutive IO errors per card. After three failures, SDBackup warns that the card may be failing and should be replaced.

追踪每张卡的连续 IO 错误次数。累计三次失败后提示该卡可能即将损坏，建议更换。

### Crash Recovery / 崩溃恢复

A lock file prevents concurrent backups to the same destination. A state file tracks transfer progress every 10 files. If the app or system crashes mid-backup, SDBackup detects the stale state on next launch and notifies you.

锁文件防止同一目标目录的并发备份。状态文件每 10 个文件更新一次进度。崩溃后下次启动时检测到残留状态文件会发出通知。

### Transfer History / 传输历史

Full log of all backup attempts with timestamp, source device, destination, file count, data size, duration, and status. Export to CSV for record keeping.

完整记录每次备份的时间、源设备、目标路径、文件数、数据量、耗时和状态。支持导出为 CSV。

### Auto Update Check / 自动更新检查

Checks GitHub Releases once per day. If a new version is available, a notice appears in the settings page.

每天检查一次 GitHub Releases，发现新版本时在设置页面显示更新提示。

### Launch at Login / 开机自启

Uses macOS ServiceManagement framework for native login item registration. No third-party dependencies.

使用 macOS ServiceManagement 框架实现原生登录项注册，无第三方依赖。

### Card Renaming / 存储卡重命名

Assign custom names to your storage cards for easier identification in the menu bar and settings.

为存储卡分配自定义名称，便于在菜单栏和设置中识别。

### Dual Language / 双语言

Full support for Simplified Chinese and English. Switch instantly from the settings page.

完整支持简体中文和英文，在设置页面即时切换。

---

## Screenshots / 界面预览

### Menu Bar / 菜单栏

![Menu Bar](Screenshots/menu_bar.png)

### Backup Settings / 备份设置

![Backup Settings](Screenshots/backup_settings.png)

### Advanced Settings / 高级设置

![Advanced Settings](Screenshots/advanced_settings.png)

### Transfer History / 传输历史

![Transfer History](Screenshots/transfer_history.png)

### Other Settings / 其他设置

![Other Settings](Screenshots/other_settings.png)

---

## Installation / 安装

1. Download `SDBackup-1.0.0.dmg` from [Releases](https://github.com/breaker5474/SDBackup/releases)
   从 [Releases](https://github.com/breaker5474/SDBackup/releases) 下载 `SDBackup-1.0.0.dmg`
2. Open the DMG and drag `SDBackup.app` into your Applications folder
   打开 DMG，将 `SDBackup.app` 拖入应用程序文件夹
3. Launch SDBackup -- it appears in the menu bar
   启动 SDBackup，它会出现在菜单栏
4. Open Settings to configure your backup destination
   打开设置配置备份目标路径

## System Requirements / 系统要求

- macOS 13.0 (Ventura) or later / macOS 13.0 (Ventura) 或更高版本
- Apple Silicon or Intel Mac

## Building from Source / 从源码构建

```bash
git clone https://github.com/breaker5474/SDBackup.git
cd SDBackup
swift build -c release
```

Build DMG / 打包 DMG:

```bash
bash Scripts/build_dmg.sh
```

## License / 许可证

MIT

## Developer / 开发者

NanYang (南洋NanYang)
