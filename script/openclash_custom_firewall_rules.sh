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
#      对「从内网进入 + 经 WAN 出去 + 目的为非中国大陆 GUA」的 TCP/UDP 直接 reject。
#      reject 而非 drop，客户端立刻收到 ICMPv6 不可达并回落到 IPv4 → 走代理。
#
# 为什么不会误伤：
#   - 规则带 iifname(内网) + oifname(WAN) 限定，只约束"内网主动出网"方向；
#     公网主动连入内网（BT/PT 入站、ICMPv6 差错报文）完全不匹配。
#   - 国内 IPv6 目的地由 china_ip6_route 集合放行，国内 IPv6 直连不受影响。
#   - 不匹配 IPv6 的 ULA(fc00::/7)、链路本地、组播（非 2000::/3 前缀）。
#
# 关闭方式: 把下面两个开关置 0 后重启 OpenClash；或删除本文件。
#           注意：已注入内核的规则要等 `fw4 reload` 或重启路由器才会消失。
# ============================================================

. /usr/share/openclash/log.sh 2>/dev/null
command -v LOG_TIP >/dev/null 2>&1 || LOG_TIP() { logger -t openclash "$*" 2>/dev/null || echo "$*"; }
command -v LOG_WARN >/dev/null 2>&1 || LOG_WARN() { logger -t openclash "$*" 2>/dev/null || echo "$*"; }

# ---- 开关 ----
ENABLE_IPV6_DNS_HIJACK=1      # 劫持内网 IPv6 DNS(53) 到本机 dnsmasq
ENABLE_NON_CN_IPV6_REJECT=1   # 拒绝内网经 WAN 访问非中国大陆 IPv6

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
         counter redirect to :53 comment "OpenClash IPv6 DNS Hijack (custom)" 2>/dev/null \
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
      LOG_WARN "China IPv6 route set is missing or empty, skip Non-CN IPv6 Reject rule (避免误伤国内 IPv6)."
   elif nft list chain inet fw4 forward 2>/dev/null | grep -q "OpenClash Non-CN IPv6 Reject (custom)"; then
      LOG_TIP "Non-CN IPv6 Reject rule already exists, skip."
   else
      nft insert rule inet fw4 forward position 0 \
         meta nfproto ipv6 iifname "$LAN_IF" oifname "$WAN_IF" meta l4proto { tcp, udp } \
         ip6 daddr 2000::/3 ip6 daddr != @$CN6_SET \
         counter reject comment "OpenClash Non-CN IPv6 Reject (custom)" 2>/dev/null \
         && LOG_TIP "Add Non-CN IPv6 Reject rule successful (LAN=$LAN_IF WAN=$WAN_IF)." \
         || LOG_WARN "Add Non-CN IPv6 Reject rule failed."
   fi
fi

exit 0
