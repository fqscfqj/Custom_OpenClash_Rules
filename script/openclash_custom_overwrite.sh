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
# 2) 加固自动选择组的掉线切换（下载组为主）
#    注意：OpenClash 生成的配置里，url-test 组是 `use: Provider_xxxx` + `filter:`
#    形式（机场订阅被转成 proxy-providers），此时组自己的 interval / timeout / lazy
#    全部无效：mihomo 只为 `proxies:` 里的内联节点建组级健康检查，而组级 URL 与
#    provider 的 health-check URL 相同时，组注册的健康检查任务会被直接忽略。
#    实测（2026-10-08）：节点探测历史严格每 300s 一次 = provider 的
#    health-check.interval，组里的 interval: 30 完全没生效。
#    所以这里改的是真正生效的两处：
#      a. 组：max-failed-times: 2
#         连续 2 次拨号失败（默认 5 次）即立刻强制一次 provider 健康检查，
#         节点掉线后不必干等下一个 300s 周期。
#      b. provider：health-check.timeout: 3000
#         探测超时 5s → 3s，强制健康检查时更快把死节点判定为不可用。
#    另外给组补 lazy: false / timeout: 3000：它们对 provider 型组是空操作，
#    但若哪天换成内联节点（proxies:）的模板就生效，属于无害的前瞻设置。
#
# 关于 ruby：这一步用 ruby 解析并回写 YAML，与 OpenClash 自身的做法一致——
#   /usr/share/openclash/yml_change.sh 与 yml_rules_change.sh 在本脚本运行之前，
#   已经用 YAML.load_file + YAML.dump 把同一份配置整体重写过；ruby 是 OpenClash
#   的硬依赖，因此这里再用一次不会引入新的解析风险。回写前会再校验一次能否解析。
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
# 2) 自动选择组 + provider 健康检查加固
#    目标组：组名里包含下列任一子串的 url-test / fallback / load-balance 组
#    （逗号分隔；例如改成 "下载自动选择,自动选择" 可覆盖全部自动选择组）
# ------------------------------------------------------------
TARGET_GROUPS="下载自动选择"
PROVIDER_HC_TIMEOUT="3000"   # provider health-check 超时（毫秒），留空则不动
PROVIDER_HC_LAZY=""          # 填 false 让 provider 空闲时也测速；留空保持 OpenClash 的默认（lazy）

command -v ruby >/dev/null 2>&1 || { log "ruby not found, skip group hardening"; exit 0; }

patched="$config.ocnew"
patch_log="/tmp/openclash_custom_overwrite.out"

if ruby -ryaml -E UTF-8 -e '
	begin
		path, targets, out = ARGV[0], ARGV[1].to_s.split(","), ARGV[2]
		hc_timeout, hc_lazy = ARGV[3].to_s, ARGV[4].to_s
		doc = YAML.respond_to?(:unsafe_load_file) ? YAML.unsafe_load_file(path) : YAML.load_file(path)
		raise "not a mapping" unless doc.is_a?(Hash)
		hit = []

		groups = doc["proxy-groups"]
		if groups.is_a?(Array)
			groups.each do |g|
				next unless g.is_a?(Hash)
				name = g["name"].to_s
				next if name.empty?
				next unless targets.any? { |t| !t.empty? && name.include?(t) }
				next unless %w[url-test fallback load-balance].include?(g["type"].to_s)
				g["lazy"] = false
				g["max-failed-times"] = 2
				g["timeout"] = 3000
				hit << "group:#{name}"
			end
		end

		providers = doc["proxy-providers"]
		if providers.is_a?(Hash) && !hc_timeout.empty?
			providers.each do |name, p|
				next unless p.is_a?(Hash)
				hc = p["health-check"]
				next unless hc.is_a?(Hash) && hc["enable"]
				hc["timeout"] = hc_timeout.to_i
				hc["lazy"] = (hc_lazy == "false" ? false : true) unless hc_lazy.empty?
				hit << "provider:#{name}"
			end
		end

		raise "nothing matched" if hit.empty?
		File.write(out, YAML.dump(doc))
		puts hit.join(" | ")
	rescue Exception => e
		STDERR.puts "ERROR: #{e.class}: #{e.message}"
		exit 1
	end
' "$config" "$TARGET_GROUPS" "$patched" "$PROVIDER_HC_TIMEOUT" "$PROVIDER_HC_LAZY" >"$patch_log" 2>&1; then
	# 回写前先确认新文件仍能被解析，避免把配置写坏
	if ruby -ryaml -E UTF-8 -e 'YAML.respond_to?(:unsafe_load_file) ? YAML.unsafe_load_file(ARGV[0]) : YAML.load_file(ARGV[0])' "$patched" >/dev/null 2>&1; then
		cat "$patched" >"$config"
		log "hardened: $(cat "$patch_log" 2>/dev/null)"
	else
		log "hardening skipped: patched config unparsable"
	fi
else
	log "hardening failed: $(cat "$patch_log" 2>/dev/null)"
fi

rm -f "$patched" "$patch_log"

exit 0
