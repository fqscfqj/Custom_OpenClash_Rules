# Custom OpenClash Rules

个人用。

## DNS 防泄漏

- `cfg/Custom_Clash.ini` 已通过 `clash_rule_base` 引用 `cfg/Custom_Clash_Base.yaml`，生成配置时启用 Fake-IP 与 DoH。
- 国外域名默认使用 `🚀 手动选择` 策略组访问 Cloudflare/Google DoH，国内与代理节点域名使用阿里/腾讯 DoH 直连。
- OpenClash 建议使用 Meta/Mihomo 内核，并开启 DNS 劫持 UDP/TCP 53；关闭会追加运营商 DNS 的选项。
- 浏览器或系统如果启用了“安全 DNS”，请关闭，或确保对应 DoH 域名/IP 会命中代理规则。
