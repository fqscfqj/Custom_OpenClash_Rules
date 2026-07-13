# Custom OpenClash Rules

个人用。

## DNS 防泄漏

- `cfg/Custom_Clash.ini` 已通过 `clash_rule_base` 引用 `cfg/Custom_Clash_Base.yaml`，生成配置时启用 Fake-IP。
- 常规域名优先使用运营商 DNS 与阿里 DNS，境外域名使用 Cloudflare/Google UDP DNS；依赖 `respect-rules` 与自定义公共 DNS 代理规则控制解析流量走向。
- 代理节点与 Provider 域名使用运营商 DNS 与阿里 DNS 直连解析，确保 Mihomo 冷启动、Provider 缓存为空时也能先取得节点，避免 DoH 自举回环。
- 新生成配置的“🚀 手动选择”默认先使用“🎯 全球直连”；确认 Provider 节点加载完成后，可在面板中切换为“♻️ 自动选择”。
- OpenClash 建议使用 Meta/Mihomo 内核。本仓库对应的 Kwrt/OpenClash 环境已验证使用“Dnsmasq 转发”：Dnsmasq 只把请求转发到 Mihomo `7874`，同时保留本地域名解析；关闭“追加上游 DNS”和“追加默认 DNS”。
- 如使用配置文件内置 DNS，请关闭 OpenClash 覆写设置里的“自定义上游 DNS 服务器”，不要只关闭“追加上游 DNS”。
- 如必须启用“自定义上游 DNS 服务器”，需在下方“设置自定义上游 DNS 服务器”中至少添加一条 `NameServer` 组服务器，否则 OpenClash 会提示 `配置文件 DNS 选项下的 Nameserver 必须设置服务器`。
- 端口直连规则已排除 53/784/853/5353/8853，避免 DNS/DoT/DoQ 被直连放行。
- 浏览器或系统如果启用了“安全 DNS”，请关闭，或确保对应 DoH 域名/IP 会命中代理规则。

## 路由器与 BT/PT

- Mihomo 在路由器上不启用进程匹配，避免无意义的进程探测开销。
- `rule/Custom_Port_Direct.yaml` 有意对整个 LAN 生效：未被更高优先级规则命中的非 80/443 流量默认直连，保证任意内网设备使用 BT/PT 时都能直接连接对等端。
- 上述端口策略会让其他未识别的自定义端口流量一并直连；这是下载兼容性优先的取舍。

## IPv6 兼容模式

- 当前 `cfg/Custom_Clash_Base.yaml` 默认启用顶层 `ipv6: true`、`dns.ipv6: true` 和 `fake-ip-range6`，用于保留国内原生 IPv6，同时让 OpenClash 统一处理 AAAA 解析。
- OpenClash 覆写建议同时开启 `IPv6`、`IPv6 DNS`、`China IPv6 Route` 与 `respect-rules`；DNS 劫持继续使用“防火墙转发”，并关闭“追加上游 DNS”“追加默认 DNS”。
- OpenWrt / ImmortalWrt 的 LAN 口建议优先设置为：`RA 服务 = 服务器模式`、`DHCPv6 服务 = 关闭`、`NDP 代理 = 关闭`、`本地 IPv6 DNS 服务器 = 勾选`。如果个别客户端拿不到 IPv6，再把 `DHCPv6 服务` 调整为“服务器模式”，不要直接上“混合模式”。
- 该模式的目标是“国内 IPv6 直连 + OpenClash 双栈分流”，因此建议配合 OpenClash 的 `China IPv6 Route` 使用；否则国外 AAAA 目标也可能被直接放行，体验会比较放飞自我。
- 如果你的 WAN 没有稳定 IPv6，或更在意省心而不是双栈，可以把 `cfg/Custom_Clash_Base.yaml` 里的顶层 `ipv6` 与 `dns.ipv6` 改回 `false`，并在 OpenClash 覆写里同时关闭 IPv6 相关选项。
