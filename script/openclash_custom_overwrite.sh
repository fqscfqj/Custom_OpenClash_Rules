#!/bin/sh
# ============================================================
# 配置生成后的最后一道守卫
#
# 部署路径: /etc/openclash/custom/openclash_custom_overwrite.sh
# 调用方  : /etc/init.d/openclash，参数为本次生成的临时配置文件
#
# 本脚本做两件事：
#
# 1) 删除 fake-ip-range6（防回归）
#    OpenClash 覆写里「Fake-IP Range (IPv6 Cidr)」一旦被填上，境外域名就会拿到
#    一个无法路由的 fake IPv6（如 fd00::x / fdfe:dcba:9876::x），终端会优先尝试
#    该地址并卡住，直接破坏“境外走 IPv4 代理”的设计。
#    这里用 sed 精确删除该行，不做 YAML 重排。
#
# 2) 给“下载自动选择”这类 url-test 策略组补上订阅转换写不出来的字段
#      lazy: false           组没被使用时也照常测速。默认 lazy: true 表示“没人用这个组
#                            就不测”，于是组空闲一段时间后，你一开始下载它可能还握着
#                            已经掉线的旧节点。
#      max-failed-times: 2   连续 2 次拨号失败（默认 5 次）就立刻强制一次健康检查，
#                            掉线后不必干等下一个测速周期。
#      timeout: 3000         健康检查超时 3s（默认 5s），更快判定节点不可用。
#    subconverter 的 custom_proxy_group 只能写出 url / interval / tolerance，
#    这三个字段只能在配置生成后注入（见 README「策略组自动切换」）。
#
# 关于 ruby：这一步用 ruby 解析并回写 YAML，与 OpenClash 自身的做法一致——
#   /usr/share/openclash/yml_change.sh 与 yml_rules_change.sh 在本脚本运行之前，
#   已经用 YAML.load_file + YAML.dump 把同一份配置整体重写过（含 provider path 修正），
#   ruby 是 OpenClash 的硬依赖，因此这里再用一次不会引入新的解析风险。
#   ruby 不可用时跳过第 2 步，只做第 1 步。
#
# 失败一律不阻断启动：任何异常都只写日志、保留原配置。
# ============================================================

config="$1"
[ -n "$config" ] && [ -f "$config" ] || exit 0

LOG_FILE="/tmp/openclash.log"
log() {
	[ -f "$LOG_FILE" ] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Custom Overwrite] $*" >>"$LOG_FILE" 2>/dev/null
	return 0
}

# ------------------------------------------------------------
# 1) 删除 fake-ip-range6
# ------------------------------------------------------------
sed -i '/^[[:space:]]*fake-ip-range6:[[:space:]]*/d' "$config"

# ------------------------------------------------------------
# 2) url-test / fallback 组加固
#    目标：组名里包含下列任一子串的自动选择组（逗号分隔，改这里即可扩大范围）
#    例：TARGET_GROUPS="下载自动选择,自动选择" 可覆盖全部自动选择组
# ------------------------------------------------------------
TARGET_GROUPS="下载自动选择"

command -v ruby >/dev/null 2>&1 || { log "ruby not found, skip group hardening"; exit 0; }

patched="$config.ocnew"
patch_log="/tmp/openclash_custom_overwrite.out"

if ruby -ryaml -E UTF-8 -e '
	begin
		path, targets, out = ARGV[0], ARGV[1].to_s.split(","), ARGV[2]
		doc = YAML.respond_to?(:unsafe_load_file) ? YAML.unsafe_load_file(path) : YAML.load_file(path)
		groups = doc.is_a?(Hash) ? doc["proxy-groups"] : nil
		raise "proxy-groups missing" unless groups.is_a?(Array)
		hit = []
		groups.each do |g|
			next unless g.is_a?(Hash)
			name = g["name"].to_s
			next if name.empty?
			next unless targets.any? { |t| !t.empty? && name.include?(t) }
			next unless %w[url-test fallback load-balance].include?(g["type"].to_s)
			g["lazy"] = false
			g["max-failed-times"] = 2
			g["timeout"] = 3000
			hit << name
		end
		raise "no target group matched" if hit.empty?
		File.write(out, YAML.dump(doc))
		puts hit.join(" | ")
	rescue Exception => e
		STDERR.puts "ERROR: #{e.class}: #{e.message}"
		exit 1
	end
' "$config" "$TARGET_GROUPS" "$patched" >"$patch_log" 2>&1; then
	# 回写前先确认新文件仍能被解析，避免把配置写坏
	if ruby -ryaml -E UTF-8 -e 'YAML.respond_to?(:unsafe_load_file) ? YAML.unsafe_load_file(ARGV[0]) : YAML.load_file(ARGV[0])' "$patched" >/dev/null 2>&1; then
		cat "$patched" >"$config"
		log "group hardened: $(cat "$patch_log" 2>/dev/null)"
	else
		log "group hardening skipped: patched config unparsable"
	fi
else
	log "group hardening failed: $(cat "$patch_log" 2>/dev/null)"
fi

rm -f "$patched" "$patch_log"

exit 0
