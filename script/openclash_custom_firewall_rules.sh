#!/bin/sh
# ============================================================
# OpenClash 自定义防火墙规则 —— IPv6 兜底
#
# 部署路径: /etc/openclash/custom/openclash_custom_firewall_rules.sh
# 调用方  : /etc/init.d/openclash（每次启动 OpenClash、写完自身规则之后调用）
# 前置条件: OpenClash 覆写中「IPv6 代理流量 / Proxy IPv6 Traffic」保持关闭
#           (openclash.config.ipv6_enable=0)：IPv6 不进入内核，国内 IPv6 走原生直连。
#
# 目标形态: 国内域名返回真实 AAAA → 运营商原生 IPv6 直连；
#           境外域名不返回 AAAA → 走 IPv4 fake-IP → 经代理出网。
#
# 本脚本堵住 DNS 分流之外的两条 IPv6 绕过路径：
#   1) 终端自带/硬编码 IPv6 DNS（如 2001:4860:4860::8888）：
#      把发往任意 IPv6 地址的 53 端口劫持到本机 dnsmasq（→ Mihomo 7874），
#      于是境外域名同样拿不到 AAAA。
#   2) 终端用自己的 DoH / 硬编码 IPv6 地址拿到真实 AAAA 后直连境外 IPv6：
#      对「从内网进入 + 经 WAN 出去 + 目的为非中国大陆 GUA」的流量直接 reject。
#      TCP 回 RST、UDP 回 ICMPv6 admin-prohibited，都是"立刻失败"而不是静默丢包，
#      客户端会迅速回落到 IPv4 → 走代理（实测 TCP 约 2 秒内报 Connection refused，
#      若只写普通 reject(icmpv6 port-unreachable) 则客户端会一直重传到超时）。
#
# 为什么不会误伤：
#   - 规则带 iifname(内网) + oifname(WAN) 限定，只约束"内网主动出网"方向；
#     公网主动连入内网（BT/PT 入站、ICMPv6 差错报文）完全不匹配。
#   - 国内 IPv6 目的地由 china_ip6_route 集合放行，国内 IPv6 直连不受影响。
#   - 不匹配 IPv6 的 ULA(fc00::/7)、链路本地、组播（非 2000::/3 前缀）。
#
# 关闭方式: 把下面两个开关置 0 后重启 OpenClash；或删除本文件。
#           注意：已注入内核的规则要等 `fw4 reload` 或重启路由器才会消失。
# 策略可调: NON_CN_IPV6_ALLOW 可填境外 IPv6 前缀白名单（默认空）。
#           是否该放行见 README 的实测对比；默认留空是有数据支撑的取舍。
# ============================================================

. /usr/share/openclash/log.sh 2>/dev/null
command -v LOG_TIP >/dev/null 2>&1 || LOG_TIP() { logger -t openclash "$*" 2>/dev/null || echo "$*"; }
command -v LOG_WARN >/dev/null 2>&1 || LOG_WARN() { logger -t openclash "$*" 2>/dev/null || echo "$*"; }

# ---- 开关 ----
ENABLE_IPV6_DNS_HIJACK=1      # 劫持内网 IPv6 DNS(53) 到本机 dnsmasq
ENABLE_NON_CN_IPV6_REJECT=1   # 拒绝内网经 WAN 访问非中国大陆 IPv6

# ---- 可选白名单：允许直连的境外 IPv6 前缀（留空 = 境外 IPv6 一律拒绝、回落 IPv4 代理）----
# 实测结论见 README：境外原生 IPv6 相对代理没有吞吐优势（7.6 vs 7.1 MB/s），
# TLS 反而更慢，且明文 DNS 的 AAAA 会被污染、被墙站点即使拿到真实 AAAA 也不通，
# 因此默认留空。若确有服务需要走原生 IPv6，在此按空格分隔填写前缀，例如：
#   NON_CN_IPV6_ALLOW="2606:4700::/32 2a06:98c1::/32"    # Cloudflare
NON_CN_IPV6_ALLOW=""

# ---- 接口（默认取 OpenClash UCI 中的设置）----
LAN_IF=$(uci -q get openclash.config.lan_interface_name)
[ -z "$LAN_IF" ] && LAN_IF="br-lan"
WAN_IF=$(uci -q get openclash.config.interface_name)
[ -z "$WAN_IF" ] && WAN_IF="wan"

CN6_SET="china_ip6_route"
CN6_FILE="/etc/openclash/china_ip6_route.ipset"

LOG_TIP "Start Add Custom Firewall Rules..."

command -v nft >/dev/null 2>&1 || { LOG_WARN "nft not found, skip custom IPv6 rules."; exit 0; }
nft list table inet fw4 >/dev/null 2>&1 || { LOG_WARN "nft table inet fw4 not found, skip custom IPv6 rules."; exit 0; }

# ---------- 1) IPv6 DNS 劫持 ----------
if [ "$ENABLE_IPV6_DNS_HIJACK" = "1" ]; then
   if nft list chain inet fw4 dstnat 2>/dev/null | grep -q "OpenClash IPv6 DNS Hijack (custom)"; then
      LOG_TIP "IPv6 DNS Hijack rule already exists, skip."
   else
      nft insert rule inet fw4 dstnat position 0 \
         meta nfproto ipv6 meta l4proto { tcp, udp } th dport 53 \
         counter redirect to :53 comment '"OpenClash IPv6 DNS Hijack (custom)"' 2>/dev/null \
         && LOG_TIP "Add IPv6 DNS Hijack rule successful." \
         || LOG_WARN "Add IPv6 DNS Hijack rule failed."
   fi
fi

# ---------- 2) 非中国大陆 IPv6 出网拒绝 ----------
if [ "$ENABLE_NON_CN_IPV6_REJECT" = "1" ]; then
   # 准备中国大陆 IPv6 地址集合；ipv6_enable=1 时 OpenClash 已自行创建并填充，这里只在缺失时加载
   if ! nft list set inet fw4 "$CN6_SET" >/dev/null 2>&1; then
      if [ -s "$CN6_FILE" ]; then
         nft -f "$CN6_FILE" 2>/dev/null
      fi
   fi

   if ! nft list set inet fw4 "$CN6_SET" 2>/dev/null | grep -q "elements = {"; then
      LOG_WARN "China IPv6 route set is missing or empty, skip Non-CN IPv6 Reject rules (避免误伤国内 IPv6)."
   else
      # 白名单前缀 → 追加为排除条件（多个 ip6 daddr != 之间是 AND 关系）
      ALLOW_EXPR=""
      for p in $NON_CN_IPV6_ALLOW; do
         ALLOW_EXPR="$ALLOW_EXPR ip6 daddr != $p"
      done
      [ -n "$ALLOW_EXPR" ] && LOG_TIP "Non-CN IPv6 allow list: $NON_CN_IPV6_ALLOW"

      # 每次启动都按本脚本的配置重建，保证白名单改动立即生效（不残留旧条件）
      for h in $(nft -a list chain inet fw4 forward 2>/dev/null | awk '/OpenClash Non-CN IPv6 Reject \(custom/{print $NF}'); do
         nft delete rule inet fw4 forward handle "$h" 2>/dev/null
      done

      # TCP 用 tcp reset：客户端立刻收到 RST（实测 ~2 秒内失败），而不是静默等待超时
      nft insert rule inet fw4 forward position 0 \
         meta nfproto ipv6 iifname "$LAN_IF" oifname "$WAN_IF" meta l4proto tcp \
         ip6 daddr 2000::/3 ip6 daddr != @$CN6_SET $ALLOW_EXPR \
         counter reject with tcp reset comment '"OpenClash Non-CN IPv6 Reject (custom tcp)"' 2>/dev/null \
         && LOG_TIP "Add Non-CN IPv6 Reject rule (tcp) successful (LAN=$LAN_IF WAN=$WAN_IF)." \
         || LOG_WARN "Add Non-CN IPv6 Reject rule (tcp) failed."

      # UDP（QUIC/DoQ 等）回 ICMPv6 administratively prohibited
      nft insert rule inet fw4 forward position 0 \
         meta nfproto ipv6 iifname "$LAN_IF" oifname "$WAN_IF" meta l4proto udp \
         ip6 daddr 2000::/3 ip6 daddr != @$CN6_SET $ALLOW_EXPR \
         counter reject with icmpv6 admin-prohibited comment '"OpenClash Non-CN IPv6 Reject (custom udp)"' 2>/dev/null \
         && LOG_TIP "Add Non-CN IPv6 Reject rule (udp) successful." \
         || LOG_WARN "Add Non-CN IPv6 Reject rule (udp) failed."
   fi
fi

exit 0
