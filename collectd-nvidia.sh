#!/bin/bash

HOSTNAME="${COLLECTD_HOSTNAME:-$(hostname)}"
INTERVAL="${COLLECTD_INTERVAL:-60}"

while sleep "$INTERVAL"; do
  /usr/bin/nvidia-smi --query-gpu=utilization.gpu,utilization.memory,memory.used,memory.total,temperature.gpu,power.draw \
    --format=csv,noheader,nounits | \
  while IFS=', ' read -r gpu_util mem_util mem_used mem_total temp power; do
	echo "PUTVAL \"$HOSTNAME/gpu/gauge-gpu_util\" interval=$INTERVAL N:$gpu_util"
	echo "PUTVAL \"$HOSTNAME/gpu/gauge-mem_util\" interval=$INTERVAL N:$mem_util"
	echo "PUTVAL \"$HOSTNAME/gpu/gauge-mem_used\" interval=$INTERVAL N:$mem_used"
	echo "PUTVAL \"$HOSTNAME/gpu/gauge-mem_total\" interval=$INTERVAL N:$mem_total"
	echo "PUTVAL \"$HOSTNAME/gpu/gauge-temp\" interval=$INTERVAL N:$temp"
	echo "PUTVAL \"$HOSTNAME/gpu/gauge-power\" interval=$INTERVAL N:$power"
  done
done
