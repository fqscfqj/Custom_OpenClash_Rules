# Custom OpenClash Rules

个人用。路由器 OpenWrt 25.12.5 (x86/64) + OpenClash 0.47.171 + Mihomo Meta。

## DNS 防泄漏

- 两个订阅入口 `cfg/Custom_Clash.ini` 与 `cfg/Custom_Clash_IPv6.ini` 内容完全一致，都引用唯一的基础模板 `cfg/Custom_Clash_Base.yaml`；IPv4/IPv6 的差异完全由路由器 UCI（`ipv6_dns`）决定，模板不再分两份。两套配置生成时均启用 Fake-IP。
- 默认与境外域名使用 Cloudflare/Google DoH，并由 `respect-rules` 与域名规则经代理连接；国内域名和命中 `DIRECT` 的目标使用国内 DNS，优先获得本地 CDN 结果。
- **DoH 解析器已固定为 IPv4 字面量**：`https://1.1.1.1/dns-query` / `https://8.8.8.8/dns-query`（`nameserver` 与 `nameserver-policy` 全部如此）。好处是不再需要为 DoH 域名做 bootstrap 解析、DNS 查询固定走 IPv4（不会因为节点侧解析出 AAAA 而把 DNS 走到境外 IPv6），也规避了 `cloudflare-dns.com` 被污染的可能。这两个 IP 在 `rule/Custom_Proxy_Classical_IP.yaml` 中，`respect-rules` 下依旧经代理连接。
- 代理节点与 Provider 域名使用运营商 DNS 与阿里 DNS 直连解析，确保 Mihomo 冷启动、Provider 缓存为空时也能先取得节点，避免 DoH 自举回环。
- **防回归约束：**不要把 `default-nameserver` 或 `proxy-server-nameserver` 全部替换成依赖代理的 DoH；历史提交 `1a09574` 曾因此造成冷启动自举回环，`05aaed2` 已恢复可靠的直连解析链路。
- 新生成配置的“🚀 手动选择”默认使用“♻️ 自动选择”；“🎯 全球直连”保留为手工回退选项。Provider 首次加载失败时可先手动切至直连排障。
- OpenClash 建议使用 Meta/Mihomo 内核。本仓库对应的 Kwrt/OpenClash 环境使用**「防火墙转发」**（`enable_redirect_dns=2`）：LAN 的 IPv4 `53/TCP+UDP` 由 nftables 直接 redirect 到 Mihomo `7874`，Dnsmasq 不再参与 IPv4 解析（只剩 DHCP，以及 IPv6 地址上的 DNS 兜底，见下文）；关闭“追加上游 DNS”和“追加默认 DNS”。
- 如使用配置文件内置 DNS，请关闭 OpenClash 覆写设置里的“自定义上游 DNS 服务器”，不要只关闭“追加上游 DNS”。
- 如必须启用“自定义上游 DNS 服务器”，需在下方“设置自定义上游 DNS 服务器”中至少添加一条 `NameServer` 组服务器，否则 OpenClash 会提示 `配置文件 DNS 选项下的 Nameserver 必须设置服务器`。
- 端口直连规则已排除 53/784/853/5353/8853，避免 DNS/DoT/DoQ 被直连放行。
- 浏览器或系统如果启用了“安全 DNS”，请关闭，或确保对应 DoH 域名/IP 会命中代理规则。

## 原生覆写模块（替代配置脚本）

原先用 `script/openclash_custom_overwrite.sh`（ruby 解析回写 YAML）在配置生成后注入几处设置。现在改为 **OpenClash 原生「覆写模块」** `cfg/overwrite/Custom_Clash.conf`：不需要往路由器部署任何脚本，语法与 OpenClash 自带的 `res/overwrite/default` 同源。

`[YAML]` 段在 `yml_change.sh` / `yml_rules_change.sh` 之后合并，因此能覆盖订阅转换与插件脚本的输出。它做三件事：

| 目标 | 覆写写法 | 作用 |
| --- | --- | --- |
| `dns.fake-ip-range6` | `fake-ip-range6-:` | 删键。防回归：一旦有值，境外域名会拿到无法路由的 fake IPv6 |
| 自动选择组 | `proxy-groups*` + `where.name: '/下载自动选择/'` | 注入 `max-failed-times: 2` / `lazy: false` / `timeout: 3000`，掉线后尽快切走 |
| proxy-provider | `proxy-providers*` + `where.key: '/^.+$/'` | 注入 `health-check.timeout: 3000`（5s → 3s），强制健康检查更快判掉死节点 |

**部署（二选一，改完必须重启 OpenClash；`reload` 不会重跑覆写）**

LuCI（推荐，可定时更新）：运行状态页 →「覆写模块」按钮 → `+ 添加新模块` → 订阅链接 → 填入下面地址 → 保存 → 重启 OpenClash。

命令行（本地文件）：

```sh
curl -sSL -o /etc/openclash/overwrite/Custom_Clash \
  https://raw.githubusercontent.com/fqscfqj/Custom_OpenClash_Rules/refs/heads/main/cfg/overwrite/Custom_Clash.conf
uci add openclash config_overwrite
uci set openclash.@config_overwrite[-1].name='Custom_Clash'
uci set openclash.@config_overwrite[-1].type='file'
uci set openclash.@config_overwrite[-1].enable='1'
uci set openclash.@config_overwrite[-1].order='3'
uci add_list openclash.@config_overwrite[-1].config='all'
uci commit openclash && /etc/init.d/openclash restart
```

验证：

```sh
grep -nE 'Overwrite Module|Load YAML Override Block' /tmp/openclash.log
# 生成配置里不应再有 fake-ip-range6，且下载组应有 max-failed-times
grep -nE 'fake-ip-range6|max-failed-times' /etc/openclash/<配置名>.yaml
```

**让模板改动生效（更新订阅）**

`custom_template_url` / `.ini` / 基础模板的改动只在**重新下载订阅**时才会被转换服务读到；重启 OpenClash 只是拿 `config/` 里已有的源配置重新生成一遍，不会重新拉取模板。命令行等价于 LuCI 配置页的「更新」按钮：

```sh
/usr/share/openclash/openclash.sh '融合'    # 参数是「配置名」，不是文件名
```

- 参数必须是订阅的**配置名**（如 `融合`）。传 `融合.yaml` 会被函数里的文件名过滤挡掉并**静默 `return 0`**：退出码 0、日志无输出、配置不变，看起来像“更新成功”。LuCI 传的同样是配置名。
- 要前台执行：BusyBox 环境**没有 `nohup`**，`nohup ... &` 只会打印 `nohup: not found` 后失败。
- 更新成功后脚本会自行重启 OpenClash，不需要再手动 `restart`。

**实测记录（2026-10-08，OpenWrt 25.12.5 + OpenClash 0.47.171 + mihomo alpha-g9f053c4）**

- **与旧脚本等价**：同一份源配置分别经原生覆写模块与 `script/openclash_custom_overwrite.sh`（旧 ruby 版）生成后逐字段比对，28 个策略组 / 3 个 proxy-provider 语义完全一致，只有下载组内注入键的书写顺序不同（YAML 映射无序，不影响结果）。
- **删键用真实引擎验证**：把 `fake-ip-range6: fd00::/112` 注入一份临时配置副本，再用 `ruby -rYAML -I /usr/share/openclash -e 'YAML.overwrite_run(ARGV[0], ARGV[1])'` 跑 `[YAML]` 段，该键被删除；线上生成配置里同样不存在。
- **组过滤按名字生效**：只有 `⬇️ 下载自动选择` 拿到 `max-failed-times: 2` / `lazy: false` / `timeout: 3000`，`♻️ 自动选择` 未被改动；3 个 provider 的 `health-check.timeout` 都变成 3000ms，`interval: 300` 保留。
- **无重复注入**：删除旧 ruby 脚本后，每轮生成日志只有一条 `Processing Overwrite Module【Custom_Clash】`，不再出现两份注入。
- **迁移后实测通过**：删掉旧脚本、只留覆写模块，冷重启后 `fake-ip-range6` 不存在、下载组四项注入齐全、国内域名拿到真实 AAAA、境外 AAAA 为空、代理链路正常（当时还挂着 IPv6 兜底脚本，该脚本于 2026-10 移除，见「IPv6 分流」）。

- 操作符速查：`key` 默认合并、`key!` 强制覆盖、`key+` 追加、`key-` 删键/删元素、`key*` 按 `where` 条件批量更新（`set` 里同样支持这些后缀）。`[YAML]` 段里以 `#` / `;` 开头的行会被忽略，不写进配置。
- 该文件的行为已按 OpenClash `YAML.rb` 覆写引擎做过等价验证：删键、按名字/键名批量更新、以及“只改目标字段、其余字段保留”均符合预期。
- 该文件按行送进 ruby 覆写引擎（`[YAML]` 段），仓库已用 `.gitattributes` 固定为 LF（`*.conf text eol=lf`），避免 Windows 检出后每行尾部带 `\r`。
- `script/` 目录已删除：原先的 IPv6 兜底脚本已随「防火墙转发」一起移除（见「IPv6 分流」）；配置生成阶段不需要任何脚本。
- **迁移提醒**：路由器上若还留着旧的 `/etc/openclash/custom/openclash_custom_overwrite.sh`（本仓库旧版脚本），请删除它或恢复成 OpenClash 自带的模板内容，否则会和覆写模块重复执行同样的注入（结果相同但日志会有两份）。
- 停用/回滚：把该模块 `enable` 置 0（`uci set openclash.@config_overwrite[N].enable='0'`）或 `uci delete openclash.@config_overwrite[N]`，再重启 OpenClash 即可；删除后不会残留任何配置改动（覆写是每次生成时重新套用，不是一次性写入）。

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
3. OpenClash 覆写里的「Fake-IP Range (IPv6 Cidr)」保持留空/Disable；原生覆写模块 `cfg/overwrite/Custom_Clash.conf` 会用 `fake-ip-range6-:` 再删一次该键作为防回归守卫（详见「原生覆写模块」）。

### 生效链路

前提：LAN 的 IPv4 DNS 请求会先被 nftables 重定向到内核 `7874`（`enable_redirect_dns=2`，见「已移除 IPv6 兜底脚本」一节），Dnsmasq 不参与解析。

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
| 插件设置 → DNS | `enable_redirect_dns` | `2` | 防火墙转发：LAN 的 `53` 直接 redirect 到内核 `7874`，Dnsmasq 不参与解析 |
| 访问控制 → WAN 绕过端口 | `wan_ac_black_ports` | `53` | 让境外 UDP 53 落到 DNS 劫持，而不是被 `openclash_mangle` 的透明 UDP 代理接走 |
| 配置文件订阅 | `custom_template_url` | `.../cfg/Custom_Clash.ini` | 推荐入口；与 `Custom_Clash_IPv6.ini` 内容完全一致，两者可互换 |
| 配置文件订阅 | `chnr6_custom_url` | 可保留或删除 | 原供 IPv6 兜底脚本取“中国大陆 IPv6”白名单；脚本已移除，留着无副作用 |

切换方式（命令行，改完重启 OpenClash 即会重新生成配置）：

```sh
uci set openclash.config.ipv6_dns='1'
uci set openclash.config.ipv6_enable='0'
uci set openclash.config.enable_rule_proxy='0'
uci delete openclash.config.fakeip_range6 2>/dev/null
uci set openclash.@config_subscribe[0].custom_template_url='https://raw.githubusercontent.com/fqscfqj/Custom_OpenClash_Rules/refs/heads/main/cfg/Custom_Clash.ini'
uci commit openclash
/etc/init.d/openclash restart
```

### 已移除 IPv6 兜底脚本（2026-10）

切到「防火墙转发」后 Dnsmasq 不再转发到 Mihomo，原先挂在 `/etc/openclash/custom/openclash_custom_firewall_rules.sh` 里的两条规则（把内网 IPv6 DNS 劫持到 dnsmasq、拒绝非中国大陆 IPv6 出网）都失去了原有作用，因此整份脚本已删除：仓库里 `script/openclash_custom_firewall_rules.sh` 移除，路由器上的同名文件也已删除（备份在 `/root/oc-backup-20261018/`）。

**当前 DNS 路径：** LAN 的 IPv4 `53/TCP+UDP` 全部由 nftables（`openclash_dns_redirect` 链）redirect 到 `:7874`，所以国内域名拿到真实 A/AAAA、境外域名只拿到 fake IPv4、AAAA 为空。

- **必须把 53 加进 `wan_ac_black_ports`（「WAN 绕过端口」）**：`openclash_mangle` 里有一条泛化的透明 UDP 代理（`tproxy :7895`，`enable_udp_proxy=1`），它在 dstnat 之前执行，会把发往境外地址的 UDP 53（`8.8.8.8`、`1.1.1.1` 等）当成普通 UDP 流量接走 → 表现为 dig 超时。加上 53 后该链提前 `return`，查询才能落到 DNS 劫持链；实测 `dig @8.8.8.8`、`dig @1.1.1.1` 都返回 `198.18.x.x`。
- **IPv6 地址上的 DNS** 仍不在 OpenClash 原生劫持范围内（规则只匹配 `nfproto ipv4`），这类查询由 dnsmasq/上游直接解析。

局域网主机名（DHCP 租约名）由 `nameserver-policy` 的 `"+.lan": 127.0.0.1:53` 交回 dnsmasq：防火墙转发模式下 dnsmasq 已不再指向 7874，不会形成回环；实测 `m910s.lan` 解析正常。

**代价（2026-10-18 切换后实测）：**

| 场景 | 有脚本时 | 现在 |
| --- | --- | --- |
| 终端硬编码境外 IPv6 DNS（如 `2001:4860:4860::8888`） | 被 53 劫持到 Mihomo，境外无 AAAA | 直接经上游递归解析，可能拿到真实/污染 AAAA（实测 `www.google.com` → `2001::1`） |
| 终端用路由器的 IPv6 地址做 DNS | 同样被劫持到 Mihomo | 由 dnsmasq 用运营商 DNS 解析，结果同上 |
| 终端拿到境外可用 AAAA | 内网→WAN 的境外 IPv6 被 `reject with tcp reset`，约 2s 回落 IPv4 | 不再拦截：能通的站直连（绕过代理），不通的站挂到超时（实测 `curl -6` 到 Cloudflare 8s 超时） |
| 局域网主机名（DHCP 租约名，如 `m910s.lan`） | 由 dnsmasq 解析 | 由 `nameserver-policy` 指回 dnsmasq，解析正常 |

需要恢复其中任一条能力时，从 git 历史取回脚本即可（`git show <commit>:script/openclash_custom_firewall_rules.sh`），也可以只保留「拒绝境外 IPv6」那一段；恢复时注意把 IPv6 DNS 劫持的目标从 `:53` 改成 `:7874`，否则规则会落到已不转发 Mihomo 的 dnsmasq 上。

局域网主机名如需继续解析，可在基础模板的 `dns.nameserver-policy` 里把 `+.lan` 指到 `127.0.0.1:53`（租约仍在 dnsmasq 里；防火墙转发模式下 dnsmasq 不再指向 7874，不会形成回环）。

### 验证方法

```sh
# 1) 生成配置里应有 ipv6: true / dns.ipv6: true，且没有 fake-ip-range6
grep -nE '^ipv6:|^  ipv6:|fake-ip-range6' /etc/openclash/<配置名>.yaml

# 2) 国内域名要有真实 AAAA，境外域名必须为空（地址用路由器 IPv4）
nslookup -type=AAAA www.baidu.com 192.168.2.1     # 期望 2408:... 真实地址
nslookup -type=AAAA www.qq.com    192.168.2.1     # 期望 2408:... 真实地址
nslookup -type=AAAA www.google.com 192.168.2.1    # 期望无 Address（为空）
nslookup -type=A    www.google.com 192.168.2.1    # 期望 198.18.x.x

# 3) 确认劫持方式是防火墙转发，且 Dnsmasq 已退出解析链路
uci get openclash.config.enable_redirect_dns          # 期望 2
uci get openclash.config.wan_ac_black_ports           # 期望 53
nft list chain inet fw4 openclash_dns_redirect        # 期望 redirect to :7874
nft list set inet fw4 wan_ac_black_ports              # 期望 elements = { 53 }
uci show dhcp | grep '127.0.0.1#7874'                 # 期望为空

# 4) 境外 UDP DNS 与局域网主机名
dig @8.8.8.8 www.google.com A                         # 期望 198.18.x.x（境外 UDP 53 也被接管）
dig <主机名>.lan                                      # 期望对应 LAN IP
```

终端侧：`curl -6 https://www.taobao.com/` 应通；境外 IPv6 不再被快速拒绝（直连或超时），这是移除脚本后的预期行为。

2026-10-18 在本环境实测结果（`192.168.2.0/24`，DNS 指向路由器；已切防火墙转发并移除脚本）：

| 测试 | 结果 |
| --- | --- |
| `nslookup -type=AAAA www.baidu.com / www.taobao.com` | 真实 `2408:871a:...` / `2408:8719:...` |
| `nslookup -type=AAAA www.google.com / github.com` | 无 AAAA |
| 用路由器 IPv6 地址查 `www.google.com` AAAA | `2001::1`（上游污染应答，脚本移除后的已知缺口） |
| `curl -6 https://www.taobao.com/` | 200，约 0.1s |
| `curl -6 https://[2606:4700:4700::1111]/` | 不再 RST，约 8s 超时（无脚本兜底） |
| `curl -4 https://www.google.com/` | 200（经代理，约 0.5s） |

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

**结论：“境外一律走 IPv4 代理、不碰境外 IPv6”是有数据支撑的取舍**；现在靠“境外域名不返回 AAAA”实现，不再额外拦截 IPv6 出网。

- 吞吐没有优势：境外原生 IPv6 与代理几乎持平（7.6 vs 7.1 MB/s），TLS 反而更慢（0.42–0.88s vs ≈0.5s）。
- 行为不可预测：被墙站点即使拿到真实 AAAA 也完全不通（TCP 443 被阻断/黑洞），而未屏蔽站点能通 —— 结果是同一台设备上“有的站走 IPv6、有的站走 IPv4 代理”，排障困难。
- 明文 DNS 的 AAAA 会被污染：实测 AliDNS 对 `www.google.com` 返回 `2001::1`，连上去就是 6–12s 黑洞超时。本配置对 `geosite:google` 等走加密 DNS 不受影响，但任何自带明文 DNS 的终端都会踩坑——脚本移除前靠 53 端口劫持 + 兜底拒绝兜住，现在只能靠终端侧不用明文/境外 DNS。
- 国内 IPv6 收益明显（taobao 首字节 16ms、整页 70ms），因此 **国内保留 IPv6 + 境外一律 IPv4** 是当前线路下的最优组合。

当前没有 IPv6 拒绝规则，因此不需要白名单。若从历史版本恢复兜底脚本，白名单仍在脚本顶部：

```sh
NON_CN_IPV6_ALLOW="2606:4700::/32 2a06:98c1::/32"   # 例：Cloudflare
```

改完 `sh /etc/openclash/custom/openclash_custom_firewall_rules.sh` 立即生效（脚本每次 OpenClash 启动都会按此重建规则，不会残留旧条件）。

### 国内 IPv4 / IPv6 未受影响（实测确认）

- 国内域名 A 与 AAAA 都是**真实地址**（如 `www.taobao.com` → 真实 A + `2408:8719:...`），不是 `198.18.x.x`。
- 10 轮连续查询 + 20 次 5 秒间隔采样，结果完全一致（baidu=2、taobao=2、bilibili=4、163=1 条 AAAA），没有出现 AAAA 抖动；国内 IPv4 连通性正常（taobao/jd 200，0.10–0.19s）。
- 本次切换只改 DNS 劫持方式与 IPv6 兜底规则，IPv4 分流、端口直连与 BT/PT 的 IPv4 策略均不受影响（转发链仍只对 fake-IP 目标做 redirect）。

### IPv6 相关常见坑

- 启动日志里出现 `[Warning] Please Note That Network May Abnormal With IPv6's DHCP Server` 属**预期现象**：OpenClash 只要看到「IPv6 代理流量=关闭」且 LAN 的 DHCPv6 服务未禁用就会提示。本方案正是要“有 IPv6 地址、但 IPv6 不进内核”，忽略即可（该提示出现在 `/etc/init.d/openclash` 的 `ipv6_enable=0 && dhcp.lan.dhcpv6 != disabled` 分支）。
- **不要把 LAN 的 DHCPv6 服务一刀切关掉**。本环境存在下级设备做 DHCPv6-PD（`ip -6 route` 里能看到 `2408:...::/62 via fe80::x dev br-lan` 这类经 br-lan 的委派路由），关掉 DHCPv6 会直接断掉下级网段的 IPv6。只在“确认没有下级 IPv6 路由器/Mesh”时才考虑 `RA=server + DHCPv6=off` 的极简组合。
- 终端上的 DNS 指向路由器 IPv4 即可（DHCPv4 下发的就是它）。如果终端额外配置了路由器的 IPv6 地址或境外 IPv6 DNS，查询会绕过 OpenClash 的 IPv4 劫持、由 dnsmasq/上游直接解析，境外域名可能拿到真实或污染 AAAA——脚本移除后已无兜底，请优先保证终端只用 IPv4 DNS。
- 修改 IPv6 相关设置后，务必让终端重新获取地址并清 DNS 缓存，否则旧 AAAA 会干扰判断。
- 只改 Clash YAML 不会关闭 OpenWrt 系统 IPv6。要彻底关掉公网 IPv6，需要停用 WAN6 的地址/前缀获取与委派，并把 LAN 的 `RA 服务`、`DHCPv6 服务`、`NDP 代理` 全部设为关闭，使终端不再获得可公网路由的 IPv6 地址（`fe80::/10` 链路本地地址仍会存在，属正常现象）。

### 两个订阅入口（内容一致，开关在 UCI）

- 两个订阅入口 `cfg/Custom_Clash.ini` 与 `cfg/Custom_Clash_IPv6.ini` 内容完全一致（只有首行注释互相指认），都引用同一份基础模板 `cfg/Custom_Clash_Base.yaml`。
- 基础模板顶层写死 `ipv6: false`：`ipv6_dns=0` 时它就是最终值（AAAA 全空、国内外全走 IPv4）；`ipv6_dns=1` 时 `yml_change.sh` 会强制改写成 `ipv6: true` + `dns.ipv6: true`（国内原生 IPv6 + 境外 IPv4）。因此**真正的开关在 UCI，不在模板**。
- **推荐入口是 `cfg/Custom_Clash.ini`**——名字不再暗示 IPv4-only，两个入口产物完全一致。`cfg/Custom_Clash_IPv6.ini` 内容与它相同（只有首行注释互相指认），仅为不打断历史 `custom_template_url` 配置而保留，可以随时互换或删除。
- 切换入口（改完重新下载订阅才会生效，见「原生覆写模块」里的更新订阅命令）：`uci set openclash.@config_subscribe[0].custom_template_url='.../cfg/Custom_Clash.ini' && uci commit openclash`；因为两个入口产物一致，切换本身不会改变任何行为。
- 两个入口模板均不使用 `fallback`；域名 DNS 分流完全由 `nameserver-policy` 负责，避免未知域名回落到运营商明文 DNS。

## 客户端自带 SSRF 校验时报「resolves to a non-public IP address」

现象：自带 SSRF 保护的工具（部分 MCP/爬虫，以及 DeepSeek Harness 的 `web_fetch`）在抓 `raw.githubusercontent.com`、`api.tavily.com` 等境外地址时报：

```
Error: URL hostname "raw.githubusercontent.com" resolves to a non-public IP address
```

根因（已定位到代码）：本方案用 fake-IP 模式，境外域名在**路由器 DNS** 上解析成 `198.18.0.0/16`；而这类工具在发请求前会用 `node:dns` 本地解析并逐个校验地址必须是「公网单播」。`198.18.0.0/15` 在 `ipaddr.js` 中归类为 `benchmarking`，不是 `unicast`，于是直接被 `WEB_BLOCKED_URL` 拦掉——**网络其实是通的，是客户端的地址校验过不去**。

```sh
nslookup raw.githubusercontent.com        # 198.18.0.8（fake-IP，被判定非公网）
```

### DeepSeek Harness：插件解决，路由器不做让步

DSH 侧改用插件，路由器与订阅不再需要为它做任何特殊处理：
**[fqscfqj/dsh-web-fetch-fakeip](https://github.com/fqscfqj/dsh-web-fetch-fakeip)**

它复用上游 `dsh-web-fetch-http` 的 provider，只把地址校验放宽到配置的 `allowCidrs`
（填 `fake-ip-range` 即可），环回 / RFC1918 / link-local / CGNAT / 云元数据地址仍然全部拦死。
插件是 userland 文件 + 一段 profile 补丁，DSH 升级不覆盖。

因此本仓库**不再内置** `fake-ip-filter` 放行条目，路由器本地列表里对应的四行也已移除：
`github*` / `tavily` 重新拿到 fake-IP，流量依旧被 redirect 进内核，由 TLS SNI 嗅探命中
`GEOSITE,github` / `Download`（含 `githubusercontent.com`）等域名规则走代理，分流不受影响。

### 其它工具仍报错时：按域名单独放行

若某个没有插件机制的工具（第三方 MCP、爬虫）仍然报同样的错，再针对那一个域名放行即可：

```yaml
# cfg/Custom_Clash_Base.yaml 的 dns.fake-ip-filter
- "+.example.com"
```

并在路由器 `/etc/openclash/custom/openclash_custom_fake_filter.list` 追加同样一行
（本地列表不依赖 GitHub raw 的 CDN 缓存）。
注意：这类域名会连带拿到真实 AAAA，双栈终端可能先试一次 IPv6；兜底脚本移除后不再有快速拒绝——未屏蔽的站点可能直接走 IPv6（绕过代理），被墙站点要等 IPv6 超时才回落 IPv4。如果在意，给这类域名配 `nameserver-policy` 让它走 IPv4，或在终端侧关掉 IPv6。

### 通用兜底：让工具走代理

让工具走代理，代理侧解析域名时该工具会**跳过**公网校验（其源码注释原文：*"A proxied hop skips those checks because the proxy resolves the origin"*）。DeepSeek Harness 读取代理环境变量，且**只有 Harness home 目录下的 `.env`** 允许设置代理名（`HTTP_PROXY`/`HTTPS_PROXY`/`ALL_PROXY`/`NO_PROXY`，在工作区 `.env` 里设会被拒绝），所以写在 `~/.dsh/.env`（Windows：`C:\Users\<用户>\.dsh\.env`）：

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
- IPv6 侧的 BT/PT 入站与直连不需要任何规则（本方案从不拦截入站方向），对等连接仍可用原生 IPv6。

## 策略组自动切换（url-test）

### 内核行为（对照 mihomo 源码确认）

- `url-test` 组的语义是「**在通过健康检查的节点里选延迟最低的那个**」，健康检查失败（超时、状态码不符）的节点会被排除。**理论上**节点掉线后组就会切走，但 provider 型组实测会出现“卡在已失效节点上”的情况（见下节），所以不能只依赖它。
- `tolerance` 只决定“要不要为了几毫秒去换节点”：当前节点延迟 > 最优节点延迟 + tolerance 才切。它不会阻止掉线切换，但会掩盖“另一个节点明显更快”的情况（差得不够多就不换）。
- **在面板里点某个节点 = 把它“固定”到该组**（`PUT /proxies/<组名>`）。被固定的节点只要还能通过健康检查就一直是它，**比它快得多的节点也不会被选中**；只有它探测失败时才回落到自动选择。
- `profile.store-selected: true`（本模板默认开启）会把这种固定写进 `cache.db`，**重启内核、重新生成配置后依旧生效**——排查“老是选到某个节点上就不移开”时先看 `fixed` 字段。手工选择（`🚀 手动选择`、`⬇️ 下载专用` 这类 select 组）依赖这个开关，所以不要关，要会解固定。
- `lazy` 默认 `true`：**组与 provider 都是**——没被使用时不做健康检查。组空闲一段时间后，一开始下载它可能还握着已经掉线的旧节点。
- 204 探测只测“握手快不快”，**测不出吞吐**：能秒回 204 但下载不动的节点会一直被当作“可用且最快”。

### 本仓库的设置

| 位置 | 设置 | 说明 |
| --- | --- | --- |
| `cfg/Custom_Clash.ini` | 下载组 `30,,20` | 只保留 tolerance 20ms；interval 对 provider 节点无效（见下） |
| `cfg/Custom_Clash.ini` | 其余组 `600,,50` | 低频测速，控制流量开销 |
| `cfg/overwrite/Custom_Clash.conf` | 组 `max-failed-times: 2`、provider `health-check.timeout: 3000` | 原生覆写模块在配置生成后注入，掉线切换真正生效的两处 |

`interval[,timeout][,tolerance]` 里只有 **interval 与 tolerance 会写进 Clash 配置**（订阅转换会丢弃 timeout），而 `max-failed-times` / provider 的 `health-check.timeout` 只能在配置生成后由原生覆写模块 `cfg/overwrite/Custom_Clash.conf` 注入（`[YAML]` 段在 `yml_change.sh` / `yml_rules_change.sh` 之后合并，可覆盖订阅转换与插件脚本的输出；见「原生覆写模块」）。

### 为什么“把组里的 interval 调小”没用（2026-10 实测）

OpenClash 会把机场订阅转成 **proxy-providers**，生成的自动选择组是这种形式：

```yaml
- name: "⬇️ 下载自动选择"
  type: url-test
  url: https://www.gstatic.com/generate_204
  interval: 30            # ← 对 provider 节点无效
  tolerance: 50
  use: [Provider_5876BE, Provider_30A0C0, Provider_BCBFC6]
  filter: "(下载专用|下载专享)"
proxy-providers:
  Provider_BCBFC6:
    health-check: {enable: true, url: https://www.gstatic.com/generate_204, interval: 300}   # ← 实际周期
```

- mihomo 只为 `proxies:`（内联节点）建组级健康检查；组里全是 `use:` 引入的 provider 节点时，组自己的 `interval` / `timeout` / `lazy` 都不会生效。
- 组级 URL 与 provider 的 `health-check.url` 相同时，mihomo 直接忽略组注册的健康检查任务（`registerHealthCheckTask` 里 `url == hc.url` 即 return），所以“用组里的 interval 覆盖 provider”这条路也走不通。
- 实测：`GET /providers/proxies/Provider_BCBFC6` 里节点的探测历史严格每 **300 秒**一条（13:52:58 / 13:57:58 / 14:02:58 / 14:07:58 / 14:12:58），正好等于 provider 的 `health-check.interval`。
- provider 的健康检查默认 `lazy`（只在被使用时测），所以组空闲时状态会一直陈旧。

### 实测到的“卡在死节点上”

2026-10-08 14:0x 在路由器上查 `⬇️ 下载自动选择`：

```json
{"now":"🇯🇵 日本S05 | 下载专用 | x0.01","fixed":"","type":"URLTest"}
```

- `fixed` 为空 ⇒ **不是被手动固定**，是组自己选的。
- 同一时刻 `GET /group/<组>/delay` 只有 `RN自建-下载专用-洛杉矶` 返回 223ms，S05/S06 都没返回；`Provider_BCBFC6` 里 S05/S06 的历史全是 `delay: 0`（不可用）。
- 即：**组会停在已经不可用的节点上**，直到内核重载。这与 mihomo 的两个已知 issue 描述一致（[#1758](https://github.com/MetaCubeX/mihomo/issues/1758)、[#1298](https://github.com/MetaCubeX/mihomo/issues/1298)：provider 型 url-test 组在当前节点失效后不切换）。

所以在这种结构下“掉线立刻切换”只能做到**尽量快**，做不到**保证**：

1. `max-failed-times: 2`：下载中途节点掉线 → 连续 2 次拨号失败（默认 5 次）立刻强制一次 provider 健康检查，几秒内把死节点判掉（脚本已注入）。
2. `health-check.timeout: 3000`：强制健康检查里每个死节点少等 2 秒（脚本已注入）。注意 provider 健康检查以 10 并发跑完全部节点，节点多时一轮本身就要几十秒。
3. 想缩短 provider 周期：`uci set openclash.config.urltest_interval_mod='120' && uci commit openclash`——OpenClash 会同时改写所有 provider 的 `health-check.interval` 和所有自动组的 `interval`。实测每轮 96 个节点，改成 120s 约等于把探测流量提到 2.5 倍。
4. 卡住时的手动补救：`DELETE /proxies/<组名>`（见下）或重启内核。

**最可靠的做法是不让这两个节点参与自动选择**：把 `cfg/Custom_Clash.ini` 里 `⬇️ 下载自动选择` 换成下面注释掉的那行（排除名字含“日本”的节点），需要时再到 `⬇️ 下载专用`（select 组）里手动指定它们。

### 排查与解除“固定节点”

```sh
# 路由器上执行。面板密码：uci get openclash.config.dashboard_password
PW=$(uci get openclash.config.dashboard_password)
G='%E2%AC%87%EF%B8%8F%20%E4%B8%8B%E8%BD%BD%E8%87%AA%E5%8A%A8%E9%80%89%E6%8B%A9'   # ⬇️ 下载自动选择

# now=当前使用；fixed=被固定的节点（非空即被固定）；all=组内节点
curl -s -H "Authorization: Bearer $PW" "http://127.0.0.1:9090/proxies/$G" \
  | sed 's/,/\n/g' | grep -E '"now"|"fixed"|"type"'

# 解除固定（仅 url-test / fallback 这类自动组支持，select 组会返回 400）
curl -s -X DELETE -H "Authorization: Bearer $PW" "http://127.0.0.1:9090/proxies/$G" -o /dev/null -w '%{http_code}\n'
```

面板（metacubexd）里点节点就是固定，点“自动 / 取消固定”或上面的 `DELETE` 即解除。若 `fixed` 为空而 `now` 仍是某个节点，那就是它确实延迟最低（此时要么接受，要么用下面的过滤排除它）。

### 三个容易踩的点

- **`⬇️ 下载专用` 是 select 组，永远不会自动切换。** 如果下载流量走的是它、而它指向某个单节点（或指向 `🚀 手动选择` 而不是 `⬇️ 下载自动选择`），那“自动切换”根本不会发生。要自动切换，请让它指向 `⬇️ 下载自动选择`。
- **切换只影响新连接**：已建立的连接（正在下载的任务）会继续挂在旧节点上直到自己断开，卡住的下载需要重试或重新开始。
- **瓶颈是吞吐而不是延迟时，204 探测无能为力**：想让某些节点彻底不参与下载自动选择，用 `cfg/Custom_Clash.ini` 中注释掉的那行 filter（排除名字含“日本”的节点），或改用 select 组手动指定。

## 运行开销

- 核心日志默认使用 `error`；排障时可临时切换到 `warning` 或 `info`，完成后恢复。
- 自动选择组在 `.ini` 里写的 `interval` 只对内联节点生效；本环境全是 provider 节点，实际周期是 provider 的 `health-check.interval`（OpenClash 生成 300 秒，可用 `urltest_interval_mod` 统一改短）。
- 广告拦截只保留「广告联盟 + 轻量精确广告 + 中国区补充 + 反劫持」四条小列表，不加载 EasyPrivacy / Advertising_Classical 这类十万级列表，以降低登录、统计和应用功能误杀。广告规则优先于自定义直连规则。各列表当前状态（2026-10）：

| 列表 | 条数 | 维护情况 |
| --- | --- | --- |
| ACL4SSR `BanAD`（广告联盟/关键词） | ~600 | 仍维护，但更新较慢；内容保守、无副作用 |
| AWAvenue 秋风广告规则（精确 DOMAIN） | ~965 | **更新频繁**（2026-09 仍在改），轻量、低误杀，适合移动端/家用 |
| ACL4SSR `BanEasyListChina`（中国区补充） | ~5000 | 仍维护 |
| blackmatrix7 `Hijacking`（反劫持） | ~228 | 内容稳定，基本不需要更新 |

- 想更省心可以删掉 `BanAD` 与 `BanEasyListChina` 两行、只留秋风广告规则；想更激进（更强拦截）可以把秋风那行换成 blackmatrix7 `Advertising/Advertising_Classical.yaml`（约 28 万条，含 EasyPrivacy，误杀会明显变多）。
- 不整套叠加 Loyalsoldier 的 `direct`、`proxy`、`cncidr` 等列表：现有 Geosite/GeoIP 已覆盖其主要用途。遇到漏网域名时，再从其列表按需补充到本地规则。
- 实测核心常驻内存约 120MB RSS（HWM 约 370MB），3.8GB 内存的 x86 软路由无压力；若长期运行出现内存缓慢增长，可再开 OpenClash 的「自动重启」。

## 目录结构

```
cfg/            OpenClash 订阅转换模板（.ini 入口 + 基础 YAML 模板）
cfg/overwrite/  OpenClash 原生覆写模块（替代原先的配置生成脚本）
rule/           自定义规则集（rule-provider，clash-classic 格式）
```
