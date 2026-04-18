# Custom OpenClash Rules

个人用。

## DNS 防泄漏

- `cfg/Custom_Clash.ini` 已通过 `clash_rule_base` 引用 `cfg/Custom_Clash_Base.yaml`，生成配置时启用 Fake-IP 与 DoH。
- 域名解析默认使用 Cloudflare/Google DoH，并依赖 `respect-rules` 与自定义公共 DNS 代理规则走代理；代理节点域名解析使用阿里/腾讯 DoH 直连以避免回环。
- OpenClash 建议使用 Meta/Mihomo 内核，DNS 劫持模式建议使用“防火墙转发”而不是“Dnsmasq 转发”；关闭“追加上游 DNS”和“追加默认 DNS”。
- 如使用配置文件内置 DNS，请关闭 OpenClash 覆写设置里的“自定义上游 DNS 服务器”，不要只关闭“追加上游 DNS”。
- 如必须启用“自定义上游 DNS 服务器”，需在下方“设置自定义上游 DNS 服务器”中至少添加一条 `NameServer` 组服务器，否则 OpenClash 会提示 `配置文件 DNS 选项下的 Nameserver 必须设置服务器`。
- 端口直连规则已排除 53/784/853/5353/8853，避免 DNS/DoT/DoQ 被直连放行。
- 浏览器或系统如果启用了“安全 DNS”，请关闭，或确保对应 DoH 域名/IP 会命中代理规则。
