# Custom OpenClash Rules

个人用。

## DNS 防泄漏

- `cfg/Custom_Clash.ini` 已通过 `clash_rule_base` 引用 `cfg/Custom_Clash_Base.yaml`，生成配置时启用 Fake-IP。
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

- `cfg/Custom_Clash_Base.yaml` 故意不写 `find-process-mode`。请在 OpenClash 覆写设置中明确选择 `OFF`，不要选择仅表示“不覆写”的“禁用/0”。
- 不要直接在基础 YAML 中写未加引号的 `find-process-mode: off`；YAML 1.1/中间转换器可能把 `off` 当作布尔值，历史提交 `5d33e5c` 至 `6c5cfc0` 已验证该问题会使最终配置失效。
- 关闭 OpenClash 的“仅代理命中规则流量/Rule Match Proxy Mode”。本模板已有明确的 BT/PT 端口策略，该功能会重复插入对路由器透明代理无意义的进程名规则。
- 固定 BT/Homelab 主机建议在 OpenClash“来源流量访问列表”中按源 IP、TCP+UDP、目标 `RETURN` 绕过纯 IP 流量。Fake-IP 域名流量仍可进入核心并按规则代理。
- `rule/Custom_Port_Direct.yaml` 有意对整个 LAN 生效：未被更高优先级规则命中的非 80/443 流量默认直连，保证任意内网设备使用 BT/PT 时都能直接连接对等端。
- 上述端口策略会让其他未识别的自定义端口流量一并直连；这是下载兼容性优先的取舍。

## 运行开销

- 核心日志默认使用 `error`；排障时可临时切换到 `warning` 或 `info`，完成后恢复。
- 常规与地区 `url-test` 间隔为 600 秒，下载专用组为 300 秒，避免 Provider 健康检查与多个策略组重复高频测速。

## IPv6 兼容模式

- 当前 `cfg/Custom_Clash_Base.yaml` 默认启用顶层 `ipv6: true`、`dns.ipv6: true` 和 `fake-ip-range6`，用于保留国内原生 IPv6，同时让 OpenClash 统一处理 AAAA 解析。
- OpenClash 覆写建议同时开启 `IPv6`、`IPv6 DNS`、`China IPv6 Route` 与 `respect-rules`；DNS 劫持沿用本环境已验证的“Dnsmasq 转发”，并关闭“追加上游 DNS”“追加默认 DNS”。
- OpenWrt / ImmortalWrt 的 LAN 口建议优先设置为：`RA 服务 = 服务器模式`、`DHCPv6 服务 = 关闭`、`NDP 代理 = 关闭`、`本地 IPv6 DNS 服务器 = 勾选`。如果个别客户端拿不到 IPv6，再把 `DHCPv6 服务` 调整为“服务器模式”，不要直接上“混合模式”。
- 该模式的目标是“国内 IPv6 直连 + OpenClash 双栈分流”，因此建议配合 OpenClash 的 `China IPv6 Route` 使用；否则国外 AAAA 目标也可能被直接放行，体验会比较放飞自我。
- 如果你的 WAN 没有稳定 IPv6，或更在意省心而不是双栈，可以把 `cfg/Custom_Clash_Base.yaml` 里的顶层 `ipv6` 与 `dns.ipv6` 改回 `false`，并在 OpenClash 覆写里同时关闭 IPv6 相关选项。
