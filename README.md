# Custom OpenClash Rules

个人用。路由器 OpenWrt 25.12.5 (x86/64) + OpenClash 0.47.168 + Mihomo Meta。

## DNS 防泄漏

- 默认无 IPv6 入口 `cfg/Custom_Clash.ini` 引用 `cfg/Custom_Clash_Base.yaml`；IPv6 入口 `cfg/Custom_Clash_IPv6.ini` 引用 `cfg/Custom_Clash_Base_IPv6.yaml`。两套配置生成时均启用 Fake-IP。
- 默认与境外域名使用 Cloudflare/Google DoH，并由 `respect-rules` 与域名规则经代理连接；国内域名和命中 `DIRECT` 的目标使用国内 DNS，优先获得本地 CDN 结果。
- **DoH 解析器已固定为 IPv4 字面量**：`https://1.1.1.1/dns-query` / `https://8.8.8.8/dns-query`（`nameserver` 与 `nameserver-policy` 全部如此）。好处是不再需要为 DoH 域名做 bootstrap 解析、DNS 查询固定走 IPv4（不会因为节点侧解析出 AAAA 而把 DNS 走到境外 IPv6），也规避了 `cloudflare-dns.com` 被污染的可能。这两个 IP 在 `rule/Custom_Proxy_Classical_IP.yaml` 中，`respect-rules` 下依旧经代理连接。
- 代理节点与 Provider 域名使用运营商 DNS 与阿里 DNS 直连解析，确保 Mihomo 冷启动、Provider 缓存为空时也能先取得节点，避免 DoH 自举回环。
- **防回归约束：**不要把 `default-nameserver` 或 `proxy-server-nameserver` 全部替换成依赖代理的 DoH；历史提交 `1a09574` 曾因此造成冷启动自举回环，`05aaed2` 已恢复可靠的直连解析链路。
- 新生成配置的“🚀 手动选择”默认使用“♻️ 自动选择”；“🎯 全球直连”保留为手工回退选项。Provider 首次加载失败时可先手动切至直连排障。
- OpenClash 建议使用 Meta/Mihomo 内核。本仓库对应的 Kwrt/OpenClash 环境已验证使用“Dnsmasq 转发”：Dnsmasq 只把请求转发到 Mihomo `7874`，同时保留本地域名解析；关闭“追加上游 DNS”和“追加默认 DNS”。
- 如使用配置文件内置 DNS，请关闭 OpenClash 覆写设置里的“自定义上游 DNS 服务器”，不要只关闭“追加上游 DNS”。
- 如必须启用“自定义上游 DNS 服务器”，需在下方“设置自定义上游 DNS 服务器”中至少添加一条 `NameServer` 组服务器，否则 OpenClash 会提示 `配置文件 DNS 选项下的 Nameserver 必须设置服务器`。
- 端口直连规则已排除 53/784/853/5353/8853，避免 DNS/DoT/DoQ 被直连放行。
- 浏览器或系统如果启用了“安全 DNS”，请关闭，或确保对应 DoH 域名/IP 会命中代理规则。

## IPv6 分流：国内原生 IPv6，境外一律 IPv4

### 设计目标

- **国内服务**：返回真实 A + 真实 AAAA，终端优先走运营商原生 IPv6，完全不经过内核与代理（省 CPU、延迟最低）。
- **翻墙流量**：只返回 `198.18.0.0/16` 的 fake IPv4，**AAAA 为空**；终端只能走 IPv4 → 透明代理 → 节点 IPv4 出口。国外 IPv6 线路质量差且不可控，因此翻墙流量不碰 IPv6。
- **IPv6 透明代理保持关闭**（`ipv6_enable=0`）：IPv6 流量不进入内核，既避免 IPv6 被节点以 IPv6 出口送出，也避免多一套 tproxy6/规则开销。

### 实测记录（Mihomo alpha-g88dcbf7 / OpenClash 0.47.168，2026-10）

在路由器上用独立端口起临时内核实测 `A` / `AAAA`（不改动线上配置）：

| `ipv6` | `dns.ipv6` | `fake-ip-range6` | 国内域名 AAAA | 境外域名 AAAA | 结论 |
| --- | --- | --- | --- | --- | --- |
| true | true | 不写 | 真实（如 `2408:871a:...`） | 空 | ✅ 目标形态 |
| true | true | `fd00::/112` | 真实 | `fd00::x`（fake ULA） | ❌ 境外拿到无法路由的地址 |
| true | true | `fdfe:dcba:9876::1/126` | — | — | ❌ 内核 fatal：`ipnet don't have valid ip`，起不来 |
| false | true | 不写 | 空 | 空 | ❌ 国内也失去 IPv6 |
| true | false | 不写 | 空 | 空 | ❌ 同上 |

由此得到三条硬约束：

1. `ipv6: true` 与 `dns.ipv6: true` **必须同时为 true**。任缺其一，AAAA 会被整体清空，国内也会退化成纯 IPv4。
2. **绝对不要设置 `fake-ip-range6`**。它一旦有值，境外域名就会拿到 fake IPv6，终端会优先尝试这个无法路由的地址。“境外没有 AAAA”正是靠“不写这个键”实现的。
3. OpenClash 覆写里的「Fake-IP Range (IPv6 Cidr)」保持留空/Disable；`script/openclash_custom_overwrite.sh` 会再删一次该行作为防回归守卫（用 `sed` 精确删行，不再依赖 ruby）。

### 生效链路

1. OpenClash 在 `dns.fake-ip-filter` 中自动注入 `rule-set:oc-cn-domain`（需要 `china_ip_route` 非 0），国内域名因此跳过 fake-IP。
2. 这些域名按 `nameserver-policy` 的 `geosite:cn` 用国内 DNS 解析 → 得到真实 A + 真实 AAAA。
3. 其余（境外）域名进入 fake-IP 池只分配 IPv4，`AAAA` 查询返回空。
4. 终端拿到真实 AAAA → 直接走原生 IPv6，内核完全不参与；拿到 fake IPv4 → 被 `openclash` 链 redirect 进内核 → 按规则走代理。
5. 境外域名的 IPv4 fake-IP 只能在内核里映射回域名，因此域名规则（`GEOSITE`/`RULE-SET`）依然生效。

### 路由器侧必须一致的设置

| LuCI 位置 | UCI | 应为 | 说明 |
| --- | --- | --- | --- |
| 覆写设置 → IPv6 | `ipv6_dns` | `1` | 同时写出 `ipv6: true` + `dns.ipv6: true`；这是国内拿到 AAAA 的前提 |
| 覆写设置 → IPv6 | `ipv6_enable` | `0` | IPv6 不进内核，避免境外 IPv6 被代理/被节点以 IPv6 送出 |
| 覆写设置 → IPv6 | `fakeip_range6` / `fake_ip_range6_enable` | 留空 / `0` | 见上面硬约束 2、3 |
| 覆写设置 → 规则 | `enable_rule_proxy` | `0` | 见「路由器与 BT/PT」中的说明 |
| 配置文件订阅 | `custom_template_url` | `.../cfg/Custom_Clash_IPv6.ini` | 使用 IPv6 版模板入口 |
| 配置文件订阅 | `chnr6_custom_url` | `https://ispip.clang.cn/all_cn_ipv6.txt` | 兜底脚本用它做“中国大陆 IPv6”白名单 |

切换方式（命令行，改完重启 OpenClash 即会重新生成配置）：

```sh
uci set openclash.config.ipv6_dns='1'
uci set openclash.config.ipv6_enable='0'
uci set openclash.config.enable_rule_proxy='0'
uci delete openclash.config.fakeip_range6 2>/dev/null
uci set openclash.@config_subscribe[0].custom_template_url='https://raw.githubusercontent.com/fqscfqj/Custom_OpenClash_Rules/refs/heads/main/cfg/Custom_Clash_IPv6.ini'
uci commit openclash
/etc/init.d/openclash restart
```

### 防火墙兜底脚本（IPv6 防绕过）

`dns.ipv6` 只能管住“通过路由器 DNS 解析”的终端。终端自带 DoH、或硬编码 IPv6 DNS 时仍可能拿到境外真实 AAAA 并直连境外 IPv6。因此把 `script/openclash_custom_firewall_rules.sh` 部署到 `/etc/openclash/custom/openclash_custom_firewall_rules.sh`（OpenClash 每次启动后自动调用），它做两件事：

1. **劫持内网 IPv6 DNS**：`53/TCP+UDP` 到任意 IPv6 地址的请求 redirect 到本机 dnsmasq → Mihomo，于是自带 IPv6 DNS 的终端同样拿不到境外 AAAA。
2. **拒绝非中国大陆 IPv6 出网**：对「从内网进入（`iifname` 内网口）+ 经 WAN 出去（`oifname` WAN 口）+ 目的为 `2000::/3` 且不在 `china_ip6_route` 集合」的流量直接拒绝。TCP 必须用 `reject with tcp reset`，UDP 用 ICMPv6 `admin-prohibited`。实测三种写法的终端表现：

| 拒绝写法 | 终端表现 |
| --- | --- |
| `reject with tcp reset` | **约 2s 内报 Connection refused** 并回落 IPv4 ✅ |
| `reject`（默认 ICMPv6 port-unreachable） | Windows 一直重传，拖到 20s 超时 ❌ |
| `reject with icmpv6 no-route` | Windows 完全不理会，死等到 connect timeout（10s+）❌ |

不会误伤的原因：

- 规则带 `iifname` + `oifname` 限定，只管“内网主动出网”方向；公网主动连入内网（BT/PT 入站、IPv6 直连访问内网服务）完全不匹配，ICMPv6 差错报文（PMTU）也不受影响。
- 国内 IPv6 目的地在 `china_ip6_route` 白名单内（已实测覆盖 `2408:8214::/31` 这一本机 WAN/LAN 前缀、`2408:871a::/31` 百度、`2408:8711:10::/30` 腾讯、`240e::/20` 电信等），国内 IPv6 直连不受影响。
- 集合文件缺失或为空时脚本会跳过该规则并告警，不会把国内 IPv6 一起掐掉。
- 脚本幂等（按注释判断是否已注入）；`fw4 reload` 会清掉这些规则，OpenClash 下次启动会重新写入。

脚本顶部两个开关（`ENABLE_IPV6_DNS_HIJACK` / `ENABLE_NON_CN_IPV6_REJECT`）置 0 即可分别关闭；不需要时直接删除该文件。

### 验证方法

```sh
# 1) 生成配置里应有 ipv6: true / dns.ipv6: true，且没有 fake-ip-range6
grep -nE '^ipv6:|^  ipv6:|fake-ip-range6' /etc/openclash/<配置名>.yaml

# 2) 国内域名要有真实 AAAA，境外域名必须为空
nslookup -type=AAAA www.baidu.com 127.0.0.1     # 期望 2408:... 真实地址
nslookup -type=AAAA www.qq.com    127.0.0.1     # 期望 2408:... 真实地址
nslookup -type=AAAA www.google.com 127.0.0.1    # 期望无 Address（为空）
nslookup -type=A    www.google.com 127.0.0.1    # 期望 198.18.x.x

# 3) 兜底规则是否注入
nft list chain inet fw4 dstnat  | grep -i 'IPv6 DNS Hijack'
nft list chain inet fw4 forward | grep -i 'Non-CN IPv6 Reject'
nft list set inet fw4 china_ip6_route | head -3
```

终端侧建议用 `curl -6` / `nslookup ... 2001:4860:4860::8888` 各测一次：国内 IPv6 应能连通，境外 IPv6 应快速失败并回落 IPv4。

2026-10 在本环境实测结果（Windows 终端，`192.168.2.0/24`，DNS 指向路由器）：

| 测试 | 结果 |
| --- | --- |
| `nslookup -type=AAAA www.baidu.com / www.taobao.com` | 真实 `2408:871a:...` / `2408:8719:...` |
| `nslookup -type=AAAA www.google.com / github.com` | 无 AAAA |
| 用境外 IPv6 DNS `2001:4860:4860::8888` 查询 | 被劫持，返回 Mihomo 结果（`198.18.x.x`，无境外 AAAA） |
| `curl -6 https://www.taobao.com/` | 200，走 `2408:8719:...`，约 0.1s |
| `curl -6 https://[2606:4700:4700::1111]/` | 约 2s 内 `Connection refused`（被 RST 拒绝，随即回落 IPv4） |
| `curl -4 https://www.google.com/` | 200（经代理，约 1.2s） |

### 国外 IPv6 vs 代理 IPv4 实测对比（2026-10，本线路）

测试要点：**必须用字面 IPv6 地址 + `--resolve` 指定 SNI**，否则会被“境外域名本来就不返回 AAAA”的设计挡住，测不到线路真实质量。

| 目标 | 原生 IPv6 直连 | 经代理 IPv4 |
| --- | --- | --- |
| Cloudflare 站点（未被墙） | 200；connect 0.18–0.22s，TLS 0.42–0.88s，total 1.8–2.9s | 200；TLS ≈0.5s，total 1.2–1.9s |
| Google（被墙，真实 AAAA `2001:4860:482d:7700::`） | **12s 无响应直接超时** | 200（≈1.0s） |
| 20MB 下载 `speed.cloudflare.com` | 7.6 MB/s（61 Mbps） | 7.1 MB/s（57 Mbps） |
| 明文 DNS 查 Google AAAA | AliDNS 返回 `2001::1`（污染应答，连上就是黑洞） | — |
| ping6 RTT（CF/Google/Quad9） | 185–224 ms，0% 丢包 | ICMP 对照：8.8.8.8 199ms、9.9.9.9 296ms、1.1.1.1 不通 |
| 国内 IPv6（taobao） | 200；connect 0.016s，total 0.07s | 国内 IPv4 同样 200（0.10–0.19s） |
| 国内镜像 38MB 吞吐（TUNA） | IPv6 **48 MB/s** | IPv4 72 MB/s |

**结论：默认“拒绝境外 IPv6、回落 IPv4 代理”是有数据支撑的取舍。**

- 吞吐没有优势：境外原生 IPv6 与代理几乎持平（7.6 vs 7.1 MB/s），TLS 反而更慢（0.42–0.88s vs ≈0.5s）。
- 行为不可预测：被墙站点即使拿到真实 AAAA 也完全不通（TCP 443 被阻断/黑洞），而未屏蔽站点能通 —— 结果是同一台设备上“有的站走 IPv6、有的站走 IPv4 代理”，排障困难。
- 明文 DNS 的 AAAA 会被污染：实测 AliDNS 对 `www.google.com` 返回 `2001::1`，连上去就是 6–12s 黑洞超时。本配置对 `geosite:google` 等走加密 DNS 不受影响，但任何自带明文 DNS 的终端都会踩坑——这也正是需要 53 端口劫持 + 兜底拒绝的原因。
- 国内 IPv6 收益明显（taobao 首字节 16ms、整页 70ms），因此 **国内保留 IPv6 + 境外一律 IPv4** 是当前线路下的最优组合。

需要放行特定境外 IPv6（例如只有 IPv6 入口的服务）时，编辑 `script/openclash_custom_firewall_rules.sh` 顶部的白名单：

```sh
NON_CN_IPV6_ALLOW="2606:4700::/32 2a06:98c1::/32"   # 例：Cloudflare
```

改完执行 `sh /etc/openclash/custom/openclash_custom_firewall_rules.sh` 立即生效（脚本每次 OpenClash 启动都会按此重建规则，不会残留旧条件）。已实测：白名单内目标放行、白名单外仍然 2s 内被 RST 拒绝、国内 IPv6 全程不受影响。

### 国内 IPv4 / IPv6 未受影响（实测确认）

- 国内域名 A 与 AAAA 都是**真实地址**（如 `www.taobao.com` → 真实 A + `2408:8719:...`），不是 `198.18.x.x`。
- 10 轮连续查询 + 20 次 5 秒间隔采样，结果完全一致（baidu=2、taobao=2、bilibili=4、163=1 条 AAAA），没有出现 AAAA 抖动；国内 IPv4 连通性正常（taobao/jd 200，0.10–0.19s）。
- IPv6 兜底规则只匹配 `ip6`（IPv6）且只作用于“内网主动出网”方向，不触碰任何 IPv4 流量与端口直连规则，BT/PT 的 IPv4 直连策略不受影响。

### IPv6 相关常见坑

- 启动日志里出现 `[Warning] Please Note That Network May Abnormal With IPv6's DHCP Server` 属**预期现象**：OpenClash 只要看到「IPv6 代理流量=关闭」且 LAN 的 DHCPv6 服务未禁用就会提示。本方案正是要“有 IPv6 地址、但 IPv6 不进内核”，忽略即可（该提示出现在 `/etc/init.d/openclash` 的 `ipv6_enable=0 && dhcp.lan.dhcpv6 != disabled` 分支）。
- **不要把 LAN 的 DHCPv6 服务一刀切关掉**。本环境存在下级设备做 DHCPv6-PD（`ip -6 route` 里能看到 `2408:...::/62 via fe80::x dev br-lan` 这类经 br-lan 的委派路由），关掉 DHCPv6 会直接断掉下级网段的 IPv6。只在“确认没有下级 IPv6 路由器/Mesh”时才考虑 `RA=server + DHCPv6=off` 的极简组合。
- 终端上的 DNS 必须是路由器地址（IPv4 + IPv6 都要有）。若 `odhcpd` 通告的上游/第三方 IPv6 DNS 被终端采用，境外域名会拿到真实 AAAA → 由兜底脚本拒绝（会回落 IPv4），但这属于“靠兜底救回来”，不是正常状态。
- 修改 IPv6 相关设置后，务必让终端重新获取地址并清 DNS 缓存，否则旧 AAAA 会干扰判断。
- 只改 Clash YAML 不会关闭 OpenWrt 系统 IPv6。要彻底关掉公网 IPv6，需要停用 WAN6 的地址/前缀获取与委派，并把 LAN 的 `RA 服务`、`DHCPv6 服务`、`NDP 代理` 全部设为关闭，使终端不再获得可公网路由的 IPv6 地址（`fe80::/10` 链路本地地址仍会存在，属正常现象）。

### 两个版本的差异

- 默认无 IPv6 版本使用 `cfg/Custom_Clash.ini` + `cfg/Custom_Clash_Base.yaml`：顶层 `ipv6` 与 `dns.ipv6` 均为 `false`，AAAA 全部返回空，终端只能用 IPv4（国内也走 IPv4）。
- 支持 IPv6 版本使用 `cfg/Custom_Clash_IPv6.ini` + `cfg/Custom_Clash_Base_IPv6.yaml`：顶层 `ipv6` 与 `dns.ipv6` 均为 `true`，按上文实现“国内 IPv6 + 境外 IPv4”。
- 注意：`ipv6` / `dns.ipv6` 会被 OpenClash 覆写项覆盖——勾选「IPv6 DNS Resolve」时 `yml_change.sh` 会强制写入两个 `true`。所以两个模板的差异主要是文档与默认值，真正的开关在 UCI。
- 两个版本均不使用 `fallback`；域名 DNS 分流完全由 `nameserver-policy` 负责，避免未知域名回落到运营商明文 DNS。

## 客户端自带 SSRF 校验时报「resolves to a non-public IP address」

现象：DeepSeek Harness 的 `web_fetch`（以及任何自带 SSRF 保护的工具、部分 MCP/爬虫）在抓 `raw.githubusercontent.com`、`api.tavily.com` 等境外地址时报：

```
Error: URL hostname "raw.githubusercontent.com" resolves to a non-public IP address
```

根因（已定位到代码）：本方案用 fake-IP 模式，境外域名在**路由器 DNS** 上解析成 `198.18.0.0/16`；而这类工具在发请求前会用 `node:dns` 本地解析并逐个校验地址必须是「公网单播」。`198.18.0.0/15` 在 `ipaddr.js` 中归类为 `benchmarking`，不是 `unicast`，于是直接被 `WEB_BLOCKED_URL` 拦掉——**网络其实是通的，是客户端的地址校验过不去**。

```sh
nslookup raw.githubusercontent.com        # 修复前：198.18.0.8（fake-IP，被判定非公网）
```

两种解法（可任选，也可同时用）：

**解法 A（推荐给“某个域名老是报错”的场景，本仓库已内置）**：把这些域名放进 `fake-ip-filter`，让它们返回真实公网 IP。流量仍是 IPv4 被 redirect 进内核，再由 TLS SNI 嗅探命中 `GEOSITE,github` / `Download`（含 `githubusercontent.com`）等域名规则走代理，分流不受影响。

```yaml
# cfg/Custom_Clash_Base_IPv6.yaml 与 cfg/Custom_Clash_Base.yaml 的 dns.fake-ip-filter
- "+.github.com"
- "+.githubusercontent.com"
- "+.githubassets.com"
- "+.tavily.com"
```

同时在路由器 `/etc/openclash/custom/openclash_custom_fake_filter.list` 追加同样四行（本地列表立即生效，不依赖订阅转换与 GitHub raw 的 CDN 缓存）。
注意：这些域名会连带拿到真实 AAAA，双栈终端可能先试一次 IPv6；本方案的 IPv6 兜底规则会立刻拒绝并回落 IPv4（浏览器/curl 有 Happy Eyeballs，实测 github.com 总耗时仍是正常的 ~1.5s）。

**解法 B（通用解，适合“任意网址都可能被抓”的场景）**：让工具走代理，代理侧解析域名时该工具会**跳过**公网校验（其源码注释原文：*"A proxied hop skips those checks because the proxy resolves the origin"*）。DeepSeek Harness 读取代理环境变量，且**只有 Harness home 目录下的 `.env`** 允许设置代理名（`HTTP_PROXY`/`HTTPS_PROXY`/`ALL_PROXY`/`NO_PROXY`，在工作区 `.env` 里设会被拒绝），所以写在 `~/.dsh/.env`（Windows：`C:\Users\<用户>\.dsh\.env`）：

```ini
HTTP_PROXY=http://Clash:<面板密码>@192.168.2.1:7890
HTTPS_PROXY=http://Clash:<面板密码>@192.168.2.1:7890
NO_PROXY=localhost,127.0.0.1,::1
```

改完**重启 DSH** 生效（启动时读取一次）。取舍：整个 DSH 进程（含模型 API 与 bash 子进程）都走这个代理——国内域名由 OpenClash 规则直连、境外走节点，行为与透明代理一致，但**路由器/OpenClash 不可用时 DSH 的网络也会不可用**；删掉该文件并重启即恢复直连。

## 路由器与 BT/PT

- BT 搜索站点（如 BTDigg、Snowfl、Torrentz2 等）单独归入“🔎 BT搜索”策略组；遇到锁区时可在该组手动切换节点。该组只控制搜索网站访问，不改变 BT/PT 下载端口的直连策略。
- `cfg/Custom_Clash_Base.yaml` 故意不写 `find-process-mode`。请在 OpenClash 覆写设置中明确选择 `OFF`，不要选择仅表示“不覆写”的“禁用/0”。
- 不要直接在基础 YAML 中写未加引号的 `find-process-mode: off`；YAML 1.1/中间转换器可能把 `off` 当作布尔值，历史提交 `5d33e5c` 至 `6c5cfc0` 已验证该问题会使最终配置失效。
- **「Rule Match Proxy Mode / 仅代理命中规则流量」（`enable_rule_proxy`）必须为 `0`。** 开启时 OpenClash 会在生成配置时改写规则：把 `GEOIP,<两位国家码>` 改成 `DIRECT`、把 `FINAL` 改成 `MATCH,DIRECT`，并追加一批 `PROCESS-NAME` 规则。实测后果是“🐟 漏网之鱼”整组失效、未匹配流量直接直连，与本文档设计相悖。
- 关闭“仅代理命中规则流量”后，本模板已经用 `rule/Custom_Port_Direct.yaml` 显式处理了 BT/PT 端口，不需要该功能重复插入对路由器透明代理无意义的进程名规则（`find-process-mode=off` 时这些进程规则本来也永远不匹配）。
- 固定 BT/Homelab 主机建议在 OpenClash“来源流量访问列表”中按源 IP、TCP+UDP、目标 `RETURN` 绕过纯 IP 流量。Fake-IP 域名流量仍可进入核心并按规则代理。
- `rule/Custom_Port_Direct.yaml` 有意对整个 LAN 生效：未被更高优先级规则命中的非 80/443 流量默认直连，保证任意内网设备使用 BT/PT 时都能直接连接对等端。
- 上述端口策略会让其他未识别的自定义端口流量一并直连；这是下载兼容性优先的取舍。
- IPv6 侧的 BT/PT 入站不受兜底脚本影响（规则只匹配内网主动出网方向），对等连接仍可用原生 IPv6。

## 运行开销

- 核心日志默认使用 `error`；排障时可临时切换到 `warning` 或 `info`，完成后恢复。
- 常规与地区 `url-test` 间隔为 600 秒，下载专用组为 300 秒，避免 Provider 健康检查与多个策略组重复高频测速。
- 广告拦截仅保留广告联盟、中国区补充和劫持规则；不默认加载大规模 EasyPrivacy，以降低登录、统计和应用功能误杀。广告规则优先于自定义直连规则。
- 不整套叠加 Loyalsoldier 的 `direct`、`proxy`、`cncidr` 等列表：现有 Geosite/GeoIP 已覆盖其主要用途。遇到漏网域名时，再从其列表按需补充到本地规则。
- 实测核心常驻内存约 120MB RSS（HWM 约 370MB），3.8GB 内存的 x86 软路由无压力；若长期运行出现内存缓慢增长，可再开 OpenClash 的「自动重启」。

## 目录结构

```
cfg/     OpenClash 订阅转换模板（.ini 入口 + 基础 YAML 模板）
rule/    自定义规则集（rule-provider，clash-classic 格式）
script/  需要部署到路由器的自定义脚本（防绕过防火墙规则、配置生成守卫）
```
