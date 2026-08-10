# Custom OpenClash Rules

个人用。

## DNS 防泄漏

- 默认无 IPv6 入口 `cfg/Custom_Clash.ini` 引用 `cfg/Custom_Clash_Base.yaml`；IPv6 入口 `cfg/Custom_Clash_IPv6.ini` 引用 `cfg/Custom_Clash_Base_IPv6.yaml`。两套配置生成时均启用 Fake-IP。
- 常规域名优先使用运营商 DNS 与阿里 DNS，境外域名使用 Cloudflare/Google UDP DNS；依赖 `respect-rules` 与自定义公共 DNS 代理规则控制解析流量走向。
- 代理节点与 Provider 域名使用运营商 DNS 与阿里 DNS 直连解析，确保 Mihomo 冷启动、Provider 缓存为空时也能先取得节点，避免 DoH 自举回环。
- **防回归约束：**不要把 `default-nameserver` 或 `proxy-server-nameserver` 全部替换成依赖代理的 DoH；历史提交 `1a09574` 曾因此造成冷启动自举回环，`05aaed2` 已恢复可靠的直连解析链路。
- 新生成配置的“🚀 手动选择”默认先使用“🎯 全球直连”；确认 Provider 节点加载完成后，可在面板中切换为“♻️ 自动选择”。
- OpenClash 建议使用 Meta/Mihomo 内核。本仓库对应的 Kwrt/OpenClash 环境已验证使用“Dnsmasq 转发”：Dnsmasq 只把请求转发到 Mihomo `7874`，同时保留本地域名解析；关闭“追加上游 DNS”和“追加默认 DNS”。
- 如使用配置文件内置 DNS，请关闭 OpenClash 覆写设置里的“自定义上游 DNS 服务器”，不要只关闭“追加上游 DNS”。
- 如必须启用“自定义上游 DNS 服务器”，需在下方“设置自定义上游 DNS 服务器”中至少添加一条 `NameServer` 组服务器，否则 OpenClash 会提示 `配置文件 DNS 选项下的 Nameserver 必须设置服务器`。
- 端口直连规则已排除 53/784/853/5353/8853，避免 DNS/DoT/DoQ 被直连放行。
- 浏览器或系统如果启用了“安全 DNS”，请关闭，或确保对应 DoH 域名/IP 会命中代理规则。

## 路由器与 BT/PT

- BT 搜索站点（如 BTDigg、Snowfl、Torrentz2 等）单独归入“🔎 BT搜索”策略组；遇到锁区时可在该组手动切换节点。该组只控制搜索网站访问，不改变 BT/PT 下载端口的直连策略。
- `cfg/Custom_Clash_Base.yaml` 故意不写 `find-process-mode`。请在 OpenClash 覆写设置中明确选择 `OFF`，不要选择仅表示“不覆写”的“禁用/0”。
- 不要直接在基础 YAML 中写未加引号的 `find-process-mode: off`；YAML 1.1/中间转换器可能把 `off` 当作布尔值，历史提交 `5d33e5c` 至 `6c5cfc0` 已验证该问题会使最终配置失效。
- 关闭 OpenClash 的“仅代理命中规则流量/Rule Match Proxy Mode”。本模板已有明确的 BT/PT 端口策略，该功能会重复插入对路由器透明代理无意义的进程名规则。
- 固定 BT/Homelab 主机建议在 OpenClash“来源流量访问列表”中按源 IP、TCP+UDP、目标 `RETURN` 绕过纯 IP 流量。Fake-IP 域名流量仍可进入核心并按规则代理。
- `rule/Custom_Port_Direct.yaml` 有意对整个 LAN 生效：未被更高优先级规则命中的非 80/443 流量默认直连，保证任意内网设备使用 BT/PT 时都能直接连接对等端。
- 上述端口策略会让其他未识别的自定义端口流量一并直连；这是下载兼容性优先的取舍。

## 运行开销

- 核心日志默认使用 `error`；排障时可临时切换到 `warning` 或 `info`，完成后恢复。
- 常规与地区 `url-test` 间隔为 600 秒，下载专用组为 300 秒，避免 Provider 健康检查与多个策略组重复高频测速。

## IPv6 版本选择

### 默认无 IPv6 版本

- 使用 `cfg/Custom_Clash.ini`，其基础模板为 `cfg/Custom_Clash_Base.yaml`；顶层 `ipv6` 与 `dns.ipv6` 均为 `false`。
- OpenClash 覆写中同时关闭 `IPv6` 代理流量、`IPv6 DNS`、`China IPv6 Route` 等 IPv6 相关选项，避免覆写模板值或继续保留 IPv6 绕行路径。
- 仅修改 Clash/Mihomo YAML 不会关闭 OpenWrt 系统 IPv6。如需彻底关闭公网 IPv6，应停用 WAN6 的 IPv6 地址/前缀获取与委派，并把 LAN 的 `RA 服务`、`DHCPv6 服务`、`NDP 代理` 设为关闭，使终端不再获得可公网路由的 IPv6 地址。
- OpenWrt 和终端上仍可能存在 `fe80::/10` 链路本地地址；该地址只用于本地链路，不代表仍有公网 IPv6 出口。

### 支持 IPv6 版本

- 使用 `cfg/Custom_Clash_IPv6.ini`，其基础模板为 `cfg/Custom_Clash_Base_IPv6.yaml`；顶层 `ipv6` 与 `dns.ipv6` 均为 `true`。
- IPv6 基础模板故意不配置 `fake-ip-range6`：国内域名返回真实 AAAA 并走运营商原生 IPv6，境外域名继续使用 IPv4 fake-IP。
- 目标模式是“IPv4 代理 + 国内 IPv6 原生直连”：OpenClash 覆写中关闭 `IPv6` 代理流量，开启 `IPv6 DNS`，保留 `China IPv6 Route` 与 `respect-rules`；DNS 劫持沿用“Dnsmasq 转发”，并关闭“追加上游 DNS”“追加默认 DNS”。
- OpenWrt / ImmortalWrt 的 LAN 口建议使用：`RA 服务 = 服务器模式`、`DHCPv6 服务 = 关闭`、`NDP 代理 = 关闭`、`本地 IPv6 DNS 服务器 = 勾选`。如果网络中存在下级 IPv6 路由器、Mesh 或 NDP 代理需求，则保留对应的 DHCPv6/NDP 配置。

### 切换后检查

- 切换 INI 后重新执行订阅转换、更新并应用 OpenClash 配置，同时确认 OpenClash 覆写项与所选版本一致。
- 让 LAN 客户端重新连接网络或续租地址，并清理旧 DNS 缓存；否则旧 AAAA 记录、IPv6 地址或路由可能影响测试结果。
- `fallback-filter.geosite` 已被 Mihomo 标记为废弃，两个版本的域名分流均由 `nameserver-policy` 负责。
