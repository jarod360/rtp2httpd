# <img src="./web-ui/public/assets/icon-192.png" width="24" height="24"> rtp2httpd - IPTV 流媒体转发服务器

[>> 访问官方文档网站 <<](https://rtp2httpd.com)

[>> English Documentation <<](https://rtp2httpd.com/en/)

rtp2httpd 是一个 IPTV 转发服务器，支持将组播 RTP/UDP、RTSP 转换为 HTTP 流，或将 HLS 流从内网代理到外网。

本项目专为中国大陆 IPTV 环境进行优化，实现了运营商级的 FCC（[Fast Channel Change](https://blog.csdn.net/yangzex/article/details/131328837)）快速换台协议，可作为 `udpxy` 和 `msd_lite` 的无缝替代，为 IPTV 用户提供接近原生机顶盒的观看体验。

## 宁夏联通 IPTV 回放与时移适配

此分支基于 rtp2httpd v3.17.2。已在 QWRT 25.12.2（`ipq53xx/generic`、`aarch64_cortex-a53`、`opkg`）验证。核心 IPK 为 `rtp2httpd_3.17.2-r2_aarch64_cortex-a53.ipk`，可搭配现有 LuCI 应用。云端检查了架构、配置文件和升级时的频道列表保留逻辑，并在目标路由器上通过 `opkg --noaction` 模拟升级。 [QWRT IPK 构建和下载](https://github.com/jarod360/rtp2httpd/actions/runs/43791443211)

### 核心改动

- **回放重定向**：保留运营商在 HTTP `Location` 中给定的 `PlaySeek` 查询参数位置，避免历史请求被当作直播处理。
- **TiviMate**：对 Starcor HLS 回放和时移请求，把客户端发来的 Unix 秒转换为运营商要求的紧凑 UTC 格式。已在 Android TV 上验证 CCTV1 往期节目回放。
- **HTTPS 反代**：启用可信反代转发头后，代理输出的 HLS 分片使用同源绝对路径，让客户端沿用清单的协议、域名和端口。已通过 Lucky 和雷池 WAF 的转发链路验证 CCTV10 的历史清单和视频分片。

### IPTV 上游与客户端配置

- 在 QWRT 的 `/etc/config/network` 中，让 IPTV 接口通过 DHCP 获取运营商网段的 IPv4 地址，并设置 `defaultroute=0`、`peerdns=0`。把回放入口及其 HLS 重定向、分片所在网段的静态路由绑定到 IPTV 接口，网关使用当地 IPTV 网关。普通上网的默认路由继续走 WAN。实际接口名、网关和分发网段以当地运营商为准。
- 在 rtp2httpd 中把 IPTV 网口指定为上游接口。直播沿用 RTP 组播，HLS 回放用 `catchup="default"` 和 `catchup-source`，并配置对应的 EPG。回放和时移支持范围以机顶盒频道表和实际播放验证为准。
- **APTV** 已实机验证回放。客户端列表采用 APTV 的本地时间占位符。北京时间且未另设客户端时区修正时，可用下面的查询格式和 rtp2httpd 现有的 `r2h-seek-offset` 参数。 [APTV 开发者示例](https://github.com/Kimentanm/aptv/issues/59)

  ```text
  ?PlaySeek=${(b)yyyyMMddHHmmss}-${(e)yyyyMMddHHmmss}&r2h-seek-offset=-28800
  ```

## ✨ 核心功能特性

### 📡 多协议支持

- **RTP->HTTP**：将组播 RTP/UDP 流转换为标准 HTTP 流
- **RTSP->HTTP**：RTSP 转为 HTTP 视频流，完整支持 RTSP/RTP 协议栈，支持 UDP NAT 穿透 (STUN)
  - 可以实现 IPTV RTSP 时移源的回看
- **HTTP->HTTP**：实现了完整反向代理，可以将 IPTV 内网 HLS 源代理到局域网、公网，方便观看
- **udpxy 兼容性**：完全兼容 udpxy URL 格式
- **M3U 播放列表集成**：支持 M3U/M3U8 格式，自动识别并转换节目地址，提供标准化的播放列表
  - 支持外部 M3U URL
  - 智能识别 RTP/RTSP URL 并转换为 HTTP 代理格式
  - 自动处理 catchup-source 时移回看地址
  - 通过 `http://<server:port>/playlist.m3u` 访问转换后的播放列表
- **抗丢包抗抖动**：支持乱序恢复、FEC 前向纠错技术，保证播放质量
  - 自动纠正乱序到达的 RTP 包，消除网络抖动导致的花屏
  - 支持 Reed-Solomon FEC 冗余恢复，可抵抗轻度丢包（需组播上游支持 FEC）
- **频道快照**：支持通过 HTTP 请求快速获取频道的快照图片，降低播放端解码压力

### ⚡ FCC 快速换台技术

- **支持运营商 FCC 协议**：搭配运营商 FCC 服务器，实现毫秒级换台响应，媲美原生 IPTV 机顶盒
- **快速解码**：FCC 保证了换台时迅速提供 IDR 帧，可供播放器立即解码

### 📊 实时状态监控

- **Web 状态页面**：通过浏览器访问 `http://<server:port>/status` 查看实时运行状态
- **客户端连接统计**：显示每个连接的 IP、状态、带宽使用、传输数据量
- **系统日志查看**：实时查看服务器日志，支持动态调整日志级别
- **远程管理功能**：通过 Web 界面强制断开客户端连接

### 🎬 内置播放器

- **浏览器直接使用**：内置基于 Web 的现代化播放器界面，可以在浏览器直接打开播放，桌面/移动端 UI 自适应
- **快速起播**：搭配 FCC 可实现快速起播、快速换台
- **支持时移和回看**：支持 EPG 电子节目单，支持时移和回看（需要有 RTSP 回看源）
- **零开销**：纯 Web 前端实现，对 rtp2httpd 运行几乎没有资源占用（无解码转码开销）
- **画质增强**：支持自动反交错、AMD FSR 1 超分辨率技术，优化 576i / 1080i 在现代 2K/4K 屏幕上的表现

### 🚀 高性能优化

- **非阻塞 IO 模型**：使用 epoll 事件驱动，高效处理大量并发连接
- **多核优化**：支持多 worker 进程，充分利用多核 CPU 提高最大吞吐量
- **缓冲池优化**：预分配缓冲池，避免频繁内存分配，多客户端根据负载动态共享，避免慢客户端吃满资源
- **同源复用**：同一工作进程内共享组播订阅、RTP 处理和批量缓冲，减少多客户端重复工作
- **轻量化**：使用纯 C 语言编写，零依赖，小巧简洁，适合运行在各种嵌入式设备上（路由器、光猫、NAS 等）
  - 程序大小仅 509KB (x86_64)，并内置了 Web 播放器所有前端资源
- 查看 **[性能测试报告](https://rtp2httpd.com/reference/benchmark)**（与 msd_lite、udpxy、tvgate 的性能对比）

## 📹 演示效果

### 快速换台 + 时移回看

https://github.com/user-attachments/assets/ca1a332f-d6e7-4a1e-be88-92bef67758b3

> [!TIP]
> 快速换台需要使用针对 IPTV 优化的播放器，例如 [mytv-android](https://github.com/mytv-android/mytv-android) / [TiviMate](https://tivimate.com) / [Cloud Stream](https://apps.apple.com/us/app/cloud-stream-iptv-player/id1138002135) 等（视频中的播放器是 mytv-android）。
> 常见普通播放器，例如 PotPlayer / IINA 等，没有专门优化起播速度，FCC 效果不明显。

### 内置播放器

https://github.com/user-attachments/assets/d3dab0c0-03c4-453b-86ae-85406e5208eb

> [!TIP]
> 需要配置 M3U 播放列表后使用，通过浏览器访问 `http://<server:port>/player` 即可打开。
> 受限于浏览器解码能力，一些频道可能不支持（表现为无音频、画面黑屏）。

### 实时状态监控

<img width="2890" height="1762" alt="web-dashboard" src="https://github.com/user-attachments/assets/09ad1e6e-f21f-4635-9706-04833063ba1b" />

### 25 条 1080p 组播流同时播放

https://github.com/user-attachments/assets/9d531ab6-6c35-4c50-802a-71f88b6b22c5

> [!NOTE]
> 单流码率 8 Mbps。总仅占用 25% CPU 单核 (i3-N305)，消耗 4MB 内存。

## 📖 文档

- **[快速上手](https://rtp2httpd.com/guide/quick-start)**：OpenWrt 快速配置指南
- **[安装方式](https://rtp2httpd.com/guide/installation)**：各种平台的安装指南

如果是首次搭建 IPTV 组播转发服务，对相关网络知识比较陌生（DHCP 鉴权、路由、组播、防火墙），推荐先看 [搭建教程](https://rtp2httpd.com/reference/related-resources#iptv-搭建教程)。

## 📄 开源许可

本项目基于 GNU General Public License v2.0 开源协议发布。这意味着：

- ✅ 可以部署在商业环境中（如企业内部使用）
- ✅ 可以基于它提供收费的 IPTV 转码服务
- ✅ 可以在有偿 IPTV 咨询服务中使用本软件
- ✅ 可以销售包含此软件的硬件设备
- ⚠️ 如果修改代码，必须公开修改后的源代码
- ⚠️ 如果分发二进制文件，必须同时提供源代码
- ⚠️ 不能将其闭源后再销售

## 🙏 致谢

- 原始项目 [oskar456/rtp2httpd](https://github.com/oskar456/rtp2httpd) 的开发者们
- 愿意在互联网上公开 FCC 协议细节的业内人士
- 所有测试和反馈用户
