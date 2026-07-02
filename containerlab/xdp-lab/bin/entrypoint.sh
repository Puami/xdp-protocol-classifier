#!/bin/bash
set -euo pipefail

HOSTNAME=$(hostname)
CFG_FILE="/etc/nodes/${HOSTNAME}.cfg"
ETH1_INTERFACE="eth1"

echo "=== Node entrypoint: ${HOSTNAME} ==="

if [[ ! -f "${CFG_FILE}" ]]; then
    echo "[FATAL] Configuration file missing: ${CFG_FILE}"
    exit 1
fi

source "${CFG_FILE}"

ip link set lo up
ip link set "${ETH1_INTERFACE}" up mtu 1500
ip addr flush dev "${ETH1_INTERFACE}" 2>/dev/null || true
ip addr add "${NODE_IP}/${NODE_PREFIX}" dev "${ETH1_INTERFACE}"
ip -6 addr add "${NODE_IP6}/${NODE_PREFIX6}" dev "${ETH1_INTERFACE}" nodad

echo "[OK] IPv4: ${NODE_IP}/${NODE_PREFIX}"
echo "[OK] IPv6: ${NODE_IP6}/${NODE_PREFIX6}"
echo ""
ip addr show
echo ""
echo "[INFO] Node ${HOSTNAME} ready."
