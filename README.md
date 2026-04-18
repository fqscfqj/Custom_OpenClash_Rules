# Custom OpenClash Rules

个人用。

## DNS 防泄漏

- `cfg/Custom_Clash.ini` 已通过 `clash_rule_base` 引用 `cfg/Custom_Clash_Base.yaml`，生成配置时启用 Fake-IP 与 DoH。
- 国外域名默认使用 Cloudflare/Google DoH，并依赖 `respect-rules` 与自定义公共 DNS 代理规则走代理；国内与代理节点域名使用阿里/腾讯 DoH 直连。
- OpenClash 建议使用 Meta/Mihomo 内核，并开启 DNS 劫持 UDP/TCP 53；关闭会追加运营商 DNS 的选项。
- 如使用配置文件内置 DNS，请关闭 OpenClash 覆写设置里的“自定义上游 DNS 服务器”，不要只关闭“追加上游 DNS”。
- 如必须启用“自定义上游 DNS 服务器”，需在下方“设置自定义上游 DNS 服务器”中至少添加一条 `NameServer` 组服务器，否则 OpenClash 会提示 `配置文件 DNS 选项下的 Nameserver 必须设置服务器`。
- 浏览器或系统如果启用了“安全 DNS”，请关闭，或确保对应 DoH 域名/IP 会命中代理规则。
