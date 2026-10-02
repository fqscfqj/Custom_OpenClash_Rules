#!/bin/sh
# ============================================================
# 配置生成后的最后一道防回归守卫
#
# 部署路径: /etc/openclash/custom/openclash_custom_overwrite.sh
# 调用方  : /etc/init.d/openclash，参数为本次生成的临时配置文件
#
# 唯一职责: 删除 fake-ip-range6。
#   OpenClash 覆写里「Fake-IP Range (IPv6 Cidr)」一旦被填上，
#   境外域名就会拿到一个无法路由的 fake IPv6（如 fd00::x / fdfe:dcba:9876::x），
#   终端会优先尝试该地址并卡住，直接破坏“境外走 IPv4 代理”的设计。
#   本脚本用 sed 精确删除该行，不做 YAML 重排，避免引入额外解析风险。
#   （历史上此脚本用 ruby 做整份 YAML 重写，已不再需要 ruby 依赖。）
# ============================================================

config="$1"
[ -n "$config" ] && [ -f "$config" ] || exit 0

sed -i '/^[[:space:]]*fake-ip-range6:[[:space:]]*/d' "$config"

exit 0
