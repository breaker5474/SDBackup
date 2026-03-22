# SD Backup App

**轻量级 SD 卡自动备份工具** — 插入即备份，零配置，零打扰。

## ✨ 特性

- 🚀 **插入即备份**：检测到 SD 卡插入时自动开始备份，无需手动操作
- 💾 **多目标支持**：备份到移动硬盘、NAS 或本地任意目录
- 🌍 **多语言支持**：中文 / English 自动切换
- ⚡️ **轻量级**：< 5MB 二进制文件，< 50MB 内存占用
- 🔒 **安全可靠**：只读访问 SD 卡，不会修改或删除源文件
- 🍎 **原生体验**：使用 Swift 开发，完美集成 macOS

## 📸 截图

> TODO: 添加截图或 GIF 演示
> - 菜单栏图标状态
> - 备份进度提示
> - 设置界面（如果有）

## 🛠 系统要求

- macOS 13.0 (Ventura) 或更高版本
- Xcode 15.0+ (仅构建时需要)

## 📦 安装

### 方式 1：下载预编译版本（推荐）

从 [Releases](https://github.com/YOUR_USERNAME/SDBackupApp/releases) 页面下载最新的 `.zip` 文件，解压后将 `sd-backup-app` 移动到 `/usr/local/bin/`：

```bash
unzip sd-backup-app-macos.zip
sudo mv sd-backup-app /usr/local/bin/
```

### 方式 2：从源码构建

```bash
# 克隆仓库
git clone https://github.com/YOUR_USERNAME/SDBackupApp.git
cd SDBackupApp

# 构建
swift build -c release

# 安装到 /usr/local/bin
sudo cp .build/release/SDBackupApp /usr/local/bin/sd-backup-app
```

## 🚀 使用方法

### 启动应用

```bash
sd-backup-app
```

应用将在后台运行，自动检测 SD 卡插入事件。

### 配置备份目标

首次运行时，应用会提示你选择备份目标目录（移动硬盘、NAS 等）。

> TODO: 添加配置文件路径和格式说明

### 停止应用

```bash
pkill -f sd-backup-app
```

## 📝 工作原理

1. **SD 卡检测**：监控 macOS 的磁盘挂载事件
2. **自动识别**：通过文件系统特征识别 SD 卡（而非普通 USB 驱动器）
3. **智能备份**：
   - 增量备份：只复制新增或修改的文件
   - 文件校验：确保备份完整性
   - 冲突处理：避免覆盖已有文件

## 🗺 路线图

- [ ] 支持自定义备份规则（按文件类型、日期等）
- [ ] 备份历史记录和版本管理
- [ ] 菜单栏 UI（显示备份状态、进度）
- [ ] 云备份支持（iCloud、Google Drive、Dropbox）
- [ ] 多 SD 卡同时备份
- [ ] Windows 和 Linux 支持

## 🤝 贡献

欢迎贡献代码、报告 bug 或提出功能建议！

1. Fork 本仓库
2. 创建功能分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 创建 Pull Request

## 📄 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件

## 🙏 致谢

- 灵感来源：作为摄影师，厌倦了每次手动备份 SD 卡
- 所有提供反馈的用户

## 📮 联系方式

- GitHub Issues: [提交 bug 或功能建议](https://github.com/YOUR_USERNAME/SDBackupApp/issues)

---

**如果这个项目对你有帮助，请给一个 ⭐️ Star！**
