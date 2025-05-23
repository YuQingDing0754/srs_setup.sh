# SRS RTMP转HLS一键脚本

## 项目简介

SRS RTMP转HLS一键脚本是一个用于将RTMP流媒体转换为HLS (HTTP Live Streaming)格式的自动化工具。该脚本可以帮助您快速部署SRS流媒体服务器，并将已有的RTMP直播流转换为兼容性更好的HLS格式，实现在iOS、Android和网页浏览器等多平台播放。

## 功能特性

- **一键安装**：自动安装SRS服务器及所有必要依赖
- **多源支持**：支持GitHub和Gitee源，适合国内外不同网络环境
- **多格式输出**：同时支持HLS(m3u8)和HTTP-FLV格式
- **内置播放器**：自动生成基于HTML5的Web播放器，支持多种流格式
- **问题诊断**：内置HLS问题诊断和修复工具
- **测试工具**：包含测试流推送功能，便于验证配置
- **中文界面**：完全中文化的交互界面，易于使用

## 系统要求

- Ubuntu 18.04/20.04/22.04 或 Debian 9/10/11 系统
- 至少2GB内存，1核CPU
- 至少5GB可用磁盘空间
- sudo权限（脚本需要管理员权限）
- 可访问互联网（安装依赖和下载源码）

## 安装方法

1. 下载脚本

```bash
git clone https://github.com/YuQingDing0754/srs_setup.sh.git
cd srs_setup.sh
```

2. 添加执行权限

```bash
chmod +x srs_setup.sh
```

3. 运行脚本

```bash
./srs_setup.sh
```

## 使用方法

脚本提供了交互式菜单，包含以下功能：

1. **安装SRS及依赖**：安装SRS服务器和所需的所有依赖项
2. **配置SRS**：设置RTMP源地址和基本参数
3. **启动SRS服务**：启动SRS服务器和拉流转换功能
4. **停止SRS服务**：停止SRS服务器及相关进程
5. **查看SRS状态**：查看当前SRS运行状态和流信息
6. **创建HTML播放器**：生成用于播放转换后视频流的网页播放器
7. **诊断和修复HLS问题**：自动诊断并修复常见HLS问题
0. **退出**：退出脚本

### 基本使用流程

1. 首先选择选项1，安装SRS及依赖
2. 然后选择选项2，配置SRS（需要提供RTMP源地址）
3. 接着选择选项3，启动SRS服务
4. 使用选项5检查SRS状态，确认服务正常运行
5. 选择选项6创建HTML播放器（可选）
6. 如遇问题，使用选项7进行诊断和修复

## 配置参数说明

### RTMP源地址格式
RTMP源地址格式通常为：`rtmp://服务器地址/应用名称/流名称`

例如：
- `rtmp://live.example.com/live/stream123`
- `rtmp://192.168.1.100/app/mystream`

### 输出流地址

成功配置后，可以通过以下地址访问转换后的流：

- **HLS地址**：`http://服务器IP:8080/hls/live/drone.m3u8`
- **HTTP-FLV地址**：`http://服务器IP:8080/live/drone.flv`
- **HTML播放器**：`http://服务器IP:8080/player.html`

## 常见问题

### Q: 无法访问M3U8流（出现"Not Found"错误）
**A**: 可能是拉流未成功或HLS文件未生成。选择脚本中的"诊断和修复HLS问题"选项来解决。也可以检查RTMP源是否可访问。

### Q: 播放延迟较高
**A**: HLS协议本身存在一定延迟。当前配置尚未进行低延迟优化。如需更低延迟，建议使用HTTP-FLV格式播放。

### Q: SRS启动失败
**A**: 检查配置文件是否正确，端口是否被占用。脚本会在启动失败时显示日志，根据日志信息排查问题。

### Q: 找不到FFmpeg
**A**: 脚本会自动安装FFmpeg，如果安装失败，可以手动安装：`sudo apt install ffmpeg`

## 高级用法

### 手动拉流
如果自动拉流不工作，可以使用诊断工具中的手动拉流功能：
```bash
# 在脚本中选择选项7，或直接使用以下命令
cd ~/srs-server/srs/trunk
sudo ffmpeg -i "您的RTMP地址" -c copy -f flv rtmp://127.0.0.1:1935/live/drone
```

### 自定义配置
高级用户可以直接编辑配置文件进行更多自定义：
```bash
nano ~/srs-server/srs/trunk/conf/drone.conf
```

### 查看详细日志
```bash
sudo tail -f ~/srs-server/srs/trunk/logs/srs.log
```

## TODO列表

- **低延迟优化**：添加针对延迟的优化配置，减少HLS流的延迟
- **多码率转码支持**：添加多码率转码功能，适应不同网络环境
- **安全性增强**：添加访问控制和鉴权功能
- **统计功能**：添加流量和带宽统计功能
- **Web管理界面**：开发Web管理界面，实现可视化配置
- **录制功能**：添加流媒体录制功能

## 注意事项

- 脚本需要sudo权限才能正常运行
- 请确保防火墙开放了1935和8080端口
- 为获得最佳体验，推荐使用现代浏览器访问HTML播放器
- HLS转换需要一定时间，文件生成可能有延迟

## 许可声明

本脚本基于MIT许可证发布。SRS服务器遵循MIT许可证。

## 鸣谢

- [SRS](https://github.com/ossrs/srs) - Simple RTMP Server
- HLS.js和FLV.js项目，提供了优秀的播放器支持

---

Any Questions? Issue me and enjoy this script!
