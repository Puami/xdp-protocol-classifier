#!/bin/bash
set -euo pipefail

HOSTNAME=$(hostname)
CFG_FILE="/etc/nodes/${HOSTNAME}.cfg"

echo "=== Node entrypoint: ${HOSTNAME} ==="

if [[ ! -f "${CFG_FILE}" ]]; then
    echo "[FATAL] Configuration file missing: ${CFG_FILE}"
    exit 1
fi

echo "[INFO] Loading config: ${CFG_FILE}"
source "${CFG_FILE}"

if [[ -z "${NODE_ROLE:-}" ]]; then  # :- prevents set -u from aborting before our explicit check
    echo "[FATAL] NODE_ROLE is not set in ${CFG_FILE}"
    exit 1
fi
if [[ "${NODE_ROLE}" != "host" && "${NODE_ROLE}" != "router" ]]; then
    echo "[FATAL] NODE_ROLE must be 'host' or 'router', got: '${NODE_ROLE}'"
    exit 1
fi

ip link set lo up
echo "[OK] Loopback up"

configure_iface() {
    local prefix6=$5
    local prefix=$3
    local iface=$1
    local ip6=$4
    local ip=$2

    ip link set "${iface}" up
    ip addr flush dev "${iface}" 2>/dev/null || true
    ip addr add "${ip}/${prefix}" dev "${iface}"
    ip -6 addr add "${ip6}/${prefix6}" dev "${iface}" nodad
    echo "[OK] ${iface}: ${ip}/${prefix}  ${ip6}/${prefix6}"
}

configure_iface eth1 "${ETH1_IP}" "${ETH1_PREFIX}" "${ETH1_IP6}" "${ETH1_PREFIX6}"

if [[ "${NODE_ROLE}" == "router" ]]; then
    configure_iface eth2 "${ETH2_IP}" "${ETH2_PREFIX}" "${ETH2_IP6}" "${ETH2_PREFIX6}"
    echo 1 > /proc/sys/net/ipv4/ip_forward
    echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
    echo "[OK] IP forwarding enabled (IPv4 + IPv6)"
elif [[ "${NODE_ROLE}" == "host" ]]; then
    ip route replace default via "${GW_IP}"
    ip -6 route replace default via "${GW_IP6}" dev eth1
    echo "[OK] Default routes: via ${GW_IP} / ${GW_IP6}"
fi

echo ""
echo "[INFO] Addresses:"
ip addr show
echo ""
echo "[INFO] Routes:"
ip route show
ip -6 route show
echo ""

# Retry loop to handle IPv6 NDP resolution delay: all node entrypoints run in
# parallel, so when this host tries to ping its gateway the neighbor cache may
# not yet be populated and the first probe gets an immediate "Address
# unreachable" instead of timing out. A few 1-second retries are enough for
# NDP to complete without adding meaningful delay to the deploy.
ping_check() {
    local label=$1
    local flag=$2
    local addr=$3
    local i

    for i in 1 2 3; do
        if ping "${flag}" -c 1 -W 1 "${addr}" >/dev/null 2>&1; then
            echo "[OK] ${label} (${addr}) reachable"
            return 0
        fi
        sleep 1
    done
    echo "[WARN] ${label} (${addr}) not reachable after 3 attempts"
}

if [[ "${NODE_ROLE}" == "host" ]]; then
    ping_check "Gateway IPv4" "-4" "${GW_IP}"
    ping_check "Gateway IPv6" "-6" "${GW_IP6}"
fi

echo "[INFO] Node ${HOSTNAME} ready"
