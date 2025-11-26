-- rtp2httpd luci CBI for OpenWrt
local fs = require "nixio.fs"
local sys = require "luci.sys"
local http = require "luci.http"
local uci = require "luci.model.uci".cursor()

m = Map("rtp2httpd", "rtp2httpd", "rtp2httpd 用于将 RTP/UDP/RTSP 媒体流转换为 HTTP 流。在这里进行配置。")

s = m:section(TypedSection, "rtp2httpd", "")
s.anonymous = true
s.addremove = false

--------------------------------------------------------
-- Tabs
--------------------------------------------------------
s:tab("basic", "基础设置")
s:tab("network", "网络与性能")
s:tab("player", "播放器与M3U")
s:tab("advanced", "监控与高级功能")

--------------------------------------------------------
-- 基础设置
--------------------------------------------------------
o = s:taboption("basic", Flag, "disabled", "启用", "启用 rtp2httpd 服务")
o.default = "0"
o.enabled = "0"
o.disabled = "1"
o.rmempty = false

o = s:taboption("basic", Flag, "respawn", "自动重启", "程序崩溃后自动重启")
o.default = "1"

o = s:taboption("basic", Value, "port", "端口")
o.datatype = "port"
o.placeholder = "5140"

o = s:taboption("basic", ListValue, "verbose", "日志级别")
o:value("0","Fatal")
o:value("1","Error")
o:value("2","Warn")
o:value("3","Info")
o:value("4","Debug")
o.default = "1"

o = s:taboption("basic", Value, "hostname", "主机名/域名",
    "配置后将会检查 HTTP Host 头，必须匹配这里的值才能访问。M3U 转换时，也会使用这个值来作为转换后节目地址的域名。使用反向代理时，需要配置为经过反向代理后的访问地址（包括 http(s):// 和路径前缀），例如 https://my-domain.com/rtp2httpd，并且需要反向代理透传 Host 头。")

--------------------------------------------------------
-- 获取物理接口
--------------------------------------------------------
local function get_physical_interfaces()
    local devs = {}
    local patterns = { "eth%d+", "enp%d+s%d+", "ens%d+", "eno%d+", "em%d+" }

    local function is_phy(ifname)
        for _, p in ipairs(patterns) do
            if ifname:match("^" .. p .. "$") then return true end
        end
        return false
    end

    local net_devices = sys.net.devices() or {}
    for _, dev in ipairs(net_devices) do
        if is_phy(dev) then table.insert(devs, dev) end
    end
    table.sort(devs)
    return devs
end

local net_devices = get_physical_interfaces()

--------------------------------------------------------
-- 网络与接口设置
--------------------------------------------------------
o = s:taboption("network", Flag, "advanced_interface_settings", "高级接口设置", "分别配置组播、FCC 和 RTSP 的接口")
o.default = "0"

o = s:taboption("network", ListValue, "upstream_interface", "上游接口", "所有上游流量（组播、FCC 和 RTSP）使用的默认接口。留空则使用路由表。")
o:value("", "自动选择")
for _, dev in ipairs(net_devices) do o:value(dev) end
o:depends("advanced_interface_settings", "")

local function add_interface_list(opt, depends_val)
    opt:value("", "自动选择")
    for _, dev in ipairs(net_devices) do opt:value(dev) end
    opt:depends("advanced_interface_settings", depends_val)
end

o = s:taboption("network", ListValue, "upstream_interface_multicast", "上游组播接口")
add_interface_list(o, "1", "用于组播（RTP/UDP）上游媒体流的接口（默认：使用路由表）")

o = s:taboption("network", ListValue, "upstream_interface_fcc", "上游 FCC 接口")
add_interface_list(o, "1", "用于 FCC 单播上游媒体流的接口（默认：使用路由表）")

o = s:taboption("network", ListValue, "upstream_interface_rtsp", "上游 RTSP 接口")
add_interface_list(o, "1", "用于 RTSP 单播上游媒体流的接口（默认：使用路由表）")

o = s:taboption("network", Value, "maxclients", "最大客户端数")
o.datatype = "range(1,5000)"
o.placeholder = "5"

o = s:taboption("network", Value, "workers", "工作进程数", "工作进程数量。资源紧凑设备建议设置为 1，最佳吞吐量可以设置为 CPU 核心数。")
o.datatype = "range(1,64)"
o.placeholder = "1"

o = s:taboption("network", Value, "buffer_pool_max_size", "缓冲池最大容量", "零拷贝缓冲池的最大缓冲区数量。每个缓冲区 1536 字节，默认 16384 个（约 24MB）。增大此值以提高多客户端并发时的吞吐量。使用反向代理时不建议开启。")
o.datatype = "range(1024,1048576)"
o.placeholder = "16384"

o = s:taboption("network", Flag, "zerocopy_on_send", "启用零拷贝发送", "启用 MSG_ZEROCOPY 零拷贝发送以提升性能。需要内核 4.14+（支持 MSG_ZEROCOPY）。在支持的设备上，可提升吞吐量并降低 CPU 占用，特别是在高并发负载下。使用反向代理时不建议开启。")
o.default = "0"

o = s:taboption("network", Value, "mcast_rejoin_interval", "组播周期性重新加入间隔", "周期性重新加入组播组的间隔时间（秒），0 表示禁用（默认 0）。如果您的网络交换机因缺少 IGMP Query 消息而导致组播成员关系超时，可以启用此功能（建议 30-120 秒）。仅在网络环境有问题时需要启用。")
o.datatype = "range(0,86400)"
o.placeholder = "0"

o = s:taboption("network", Value, "fcc_listen_port_range", "FCC 监听端口范围", "FCC 客户端套接字使用的本地 UDP 端口范围（格式：起始端口-结束端口，例如：40000-40100）。留空则使用随机端口。")
o.placeholder = ""

--------------------------------------------------------
-- 播放器
--------------------------------------------------------
o = s:taboption("player", Value, "external_m3u", "外部 M3U", "从 URL 获取 M3U 播放列表（支持 file://、http://、https://）。示例：https://example.com/playlist.m3u 或 file:///path/to/playlist.m3u")
o.placeholder = "https://example.com/playlist.m3u"

o = s:taboption("player", Value, "external_m3u_update_interval", "外部 M3U 更新间隔", "外部 M3U 自动更新间隔（秒），默认 7200（2 小时）。设为 0 禁用自动更新。")
o.datatype = "uinteger"
o.placeholder = "7200"

o = s:taboption("player", Value, "player_page_path", "播放器页面路径", "播放器页面的 URL 路径（默认：/player）")
o.placeholder = "/player"

--------------------------------------------------------
--新窗口打开
--------------------------------------------------------
local function make_popup_link(map, section, pathKey)
    local defaultPath = (pathKey == "status_page_path") and "/status" or "/player"
    local pagePath = map:get(section, pathKey) or defaultPath
    if pagePath:sub(1,1) ~= "/" then
        pagePath = "/" .. pagePath
    end

    -- 读取端口
    local port = tonumber(map:get(section, "port")) or 5140

    -- token 参数
    local token = map:get(section, "r2h_token")
    local token_param = (token and token ~= "") and ("?r2h-token=" .. http.urlencode(token)) or ""

    -- 使用浏览器访问 LuCI 时的 host
    local host = http.getenv("HTTP_HOST") or "127.0.0.1"
    host = host:match("([^:]+)") or host  -- 去掉可能的端口

    return string.format("http://%s:%s%s%s", host, port, pagePath, token_param)
end

--------------------------------------------------------
-- 播放器按钮
--------------------------------------------------------
o = s:taboption("player", DummyValue, "_player_page_link", "播放器页面")
o.rawhtml = true
function o.cfgvalue(self, section)
    local url = make_popup_link(self.map, section, "player_page_path")
    return string.format(
        '<a class="cbi-button cbi-button-apply" href="%s" target="_blank">打开播放器页面</a>',
        url
    )
end

--------------------------------------------------------
-- 播放器警告
--------------------------------------------------------
o = s:taboption("player", DummyValue, "_player_warning", "")
o.rawhtml = true
function o.cfgvalue(self, section)
    local m3u = m:get(section, "external_m3u") or ""
    if m3u == "" then
        return '<div class="alert-message warning" style="margin-top: 10px;">注意：播放器页面需要外部 M3U。</div>'
    end
    return ""
end

--------------------------------------------------------
-- 状态面板
--------------------------------------------------------
o = s:taboption("advanced", DummyValue, "_status_dashboard_link", "状态面板")
o.rawhtml = true
function o.cfgvalue(self, section)
    local url = make_popup_link(self.map, section, "status_page_path")
    return string.format(
        '<a class="cbi-button cbi-button-apply" href="%s" target="_blank">打开状态面板</a>',
        url
    )
end

o = s:taboption("advanced", Value, "status_page_path", "状态页面路径", "状态页面的 URL 路径（默认：/status）")
o.placeholder = "/status"

o = s:taboption("advanced", Value, "r2h_token", "HTTP 请求认证令牌", "设置后，所有 HTTP 请求必须携带 r2h-token 查询参数，且值与此配置匹配（例如：http://server:5140/service?r2h-token=your-token）")
o.password = true

o = s:taboption("advanced", Flag, "xff", "X-Forwarded-For", "启用后，将使用 HTTP X-Forwarded-For 头作为客户端地址，用于显示在状态面板上。建议仅在使用反向代理时启用。")
o.default = "0"

o = s:taboption("advanced", Flag, "video_snapshot", "视频快照", "启用视频快照功能。启用后，客户端可以通过 snapshot=1 查询参数请求视频快照")
o.default = "0"

o = s:taboption("advanced", Value, "ffmpeg_path", "FFmpeg 路径", "FFmpeg 可执行文件的路径。留空则使用系统 PATH（默认：ffmpeg）")
o.placeholder = "ffmpeg"
o:depends("video_snapshot", "1")

o = s:taboption("advanced", Value, "ffmpeg_args", "FFmpeg 参数", "生成快照时传递给 FFmpeg 的额外参数。常用选项：-hwaccel none（无硬件加速）、-hwaccel auto（自动）、-hwaccel vaapi（Intel GPU）")
o.placeholder = "-hwaccel none"
o:depends("video_snapshot", "1")

--------------------------------------------------------
-- on_after_commit 处理接口动态显示
--------------------------------------------------------
m.on_after_commit = function(self)
    http.write([[
<script>
document.addEventListener('DOMContentLoaded', function() {
    function update() {
        var adv = document.querySelector('input[name="cbid.rtp2httpd.rtp2httpd.advanced_interface_settings"]');
        var isAdv = adv && adv.checked;

        function toggle(name, show) {
            var el = document.querySelector(name);
            if (el) {
                var row = el.closest('.cbi-value');
                if (row) row.style.display = show ? '' : 'none';
            }
        }

        toggle('select[name="cbid.rtp2httpd.rtp2httpd.upstream_interface"]', !isAdv);
        toggle('select[name="cbid.rtp2httpd.rtp2httpd.upstream_interface_multicast"]', isAdv);
        toggle('select[name="cbid.rtp2httpd.rtp2httpd.upstream_interface_fcc"]', isAdv);
        toggle('select[name="cbid.rtp2httpd.rtp2httpd.upstream_interface_rtsp"]', isAdv);
    }

    update();
    var adv = document.querySelector('input[name="cbid.rtp2httpd.rtp2httpd.advanced_interface_settings"]');
    if (adv) adv.addEventListener('change', update);
});
</script>
    ]])
end

--------------------------------------------------------
-- 服务自动启停
--------------------------------------------------------
m.apply_on_parse = true
m.on_after_apply = function()
    os.execute("sed -i 's/option use_config_file .*/option use_config_file '\\''0'\\''/' /etc/config/rtp2httpd")
    uci:commit("rtp2httpd")
    uci:load("rtp2httpd")

    local file = io.open("/etc/config/rtp2httpd", "r")
    local disabled = "1"

    if file then
        for line in file:lines() do
            local v = line:match("option%s+disabled%s+'([01])'")
            if v then disabled = v end
        end
        file:close()
    end

    if disabled == "0" then
        os.execute("/etc/init.d/rtp2httpd enable")
        os.execute("/etc/init.d/rtp2httpd restart")
    else
        os.execute("/etc/init.d/rtp2httpd disable")
        os.execute("/etc/init.d/rtp2httpd stop")
    end
end

return m
