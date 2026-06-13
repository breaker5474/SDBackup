# SDBackup

[![zh](https://img.shields.io/badge/简体中文-blue.svg)](README.md)
[![en](https://img.shields.io/badge/English-red.svg)](README_en.md)

macOS 菜单栏应用，用于 SD 卡自动备份。面向摄影师和视频创作者，将相机存储卡中的照片和视频可靠地传输到 Mac。

---

## 功能

### 自动备份

插入 SD 卡即开始复制，无需手动操作。支持多卡排队，插入两张卡按顺序逐一备份。

### 多源目录选择

指定要备份的目录（DCIM、CLIP、PRIVATE 等），留空则备份全部内容。每张卡独立记忆自己的目录配置。

### 文件格式过滤

按扩展名过滤，支持包含和排除两种模式。默认覆盖常见摄影格式：ARW、CR2、CR3、JPG、HEIF、MOV、MP4、XML。自动跳过缩略图、数据库等无关文件。

### 数据完整性校验

三种校验级别：

- **基础校验**：比对文件大小和修改日期
- **MD5 校验**：传输后计算哈希值比对
- **SHA256 校验**：完整加密校验，发现损坏时推送系统通知

### 备份策略

- **更新已修改文件**（默认）：跳过未变化的文件，重新传输已修改的文件
- **跳过已存在文件**：不覆盖目标路径中已有的文件

### 传输预估

正式传输前执行预演，计算待传输的文件数量和数据大小，显示预计完成时间。

### 备份统计

完成通知按类型分类：照片、视频、元数据、其他。

### 双目标路径 + 临时缓存

设置主备份路径（移动硬盘）和可选的本地临时路径。外接硬盘未连接时自动写入临时路径，重新连接后自动迁移缓存数据。

### 存储卡健康度监测

追踪每张卡的连续 IO 错误次数。累计三次失败后提示该卡可能即将损坏，建议更换。

### 崩溃恢复

锁文件防止同一目标目录的并发备份。状态文件每 10 个文件更新一次进度。崩溃后下次启动时检测到残留状态文件会发出通知。

### 传输历史

完整记录每次备份的时间、源设备、目标路径、文件数、数据量、耗时和状态。支持导出为 CSV。

### 自动更新检查

每天检查一次 GitHub Releases，发现新版本时在设置页面显示更新提示。

### 开机自启

使用 macOS ServiceManagement 框架实现原生登录项注册，无第三方依赖。

### 存储卡重命名

为存储卡分配自定义名称，便于在菜单栏和设置中识别。

### 双语言

完整支持简体中文和英文，在设置页面即时切换。

---

## 界面预览

### 菜单栏

![菜单栏](Screenshots/menu_bar.png)

### 备份设置

![备份设置](Screenshots/backup_settings.png)

### 高级设置

![高级设置](Screenshots/advanced_settings.png)

### 传输历史

![传输历史](Screenshots/transfer_history.png)

### 其他设置

![其他设置](Screenshots/other_settings.png)

---

## 安装

1. 从 [Releases](https://github.com/breaker5474/SDBackup/releases) 下载 `SDBackup-1.0.0.dmg`
2. 打开 DMG，将 `SDBackup.app` 拖入应用程序文件夹
3. 启动 SDBackup，它会出现在菜单栏
4. 打开设置配置备份目标路径

## 系统要求

- macOS 13.0 (Ventura) 或更高版本
- Apple Silicon 或 Intel Mac

## 从源码构建

```bash
git clone https://github.com/breaker5474/SDBackup.git
cd SDBackup
swift build -c release
```

打包 DMG：

```bash
bash Scripts/build_dmg.sh
```

## 许可证

MIT

## 开发者

南洋NanYang
