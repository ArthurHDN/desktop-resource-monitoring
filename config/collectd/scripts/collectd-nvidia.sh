#!/usr/bin/env bash

HOSTNAME="${COLLECTD_HOSTNAME:-$(hostname)}"
INTERVAL="${COLLECTD_INTERVAL:-15}"
NVIDIA_SMI="${NVIDIA_SMI:-$(command -v nvidia-smi || true)}"

trim() {
	local value="$1"
	value="${value#"${value%%[![:space:]]*}"}"
	value="${value%"${value##*[![:space:]]}"}"
	printf '%s' "$value"
}

emit_metric() {
	local metric_name="$1"
	local metric_value
	metric_value="$(trim "$2")"

	if [[ "$metric_value" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
		printf 'PUTVAL "%s/gpu/gauge-%s" interval=%s N:%s\n' "$HOSTNAME" "$metric_name" "$INTERVAL" "$metric_value"
	fi
}

if [[ -z "$NVIDIA_SMI" || ! -x "$NVIDIA_SMI" ]]; then
	printf 'collectd-nvidia: nvidia-smi not found; GPU metrics disabled\n' >&2
	while sleep "$INTERVAL"; do :; done
fi

while true; do
	"$NVIDIA_SMI" --query-gpu=utilization.gpu,utilization.memory,memory.used,memory.total,temperature.gpu,power.draw \
		--format=csv,noheader,nounits 2>/dev/null | \
	while IFS=',' read -r gpu_util mem_util mem_used mem_total temp power; do
		emit_metric "gpu_util" "$gpu_util"
		emit_metric "mem_util" "$mem_util"
		emit_metric "mem_used" "$mem_used"
		emit_metric "mem_total" "$mem_total"
		emit_metric "temp" "$temp"
		emit_metric "power" "$power"
	done

	sleep "$INTERVAL"
done
