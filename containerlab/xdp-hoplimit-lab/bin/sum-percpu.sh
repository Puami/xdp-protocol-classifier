#!/bin/bash
# sum-percpu — pretty-print and sum the per-CPU values of a
# BPF_MAP_TYPE_PERCPU_ARRAY map (key 0 only), referenced by its
# *pinned* bpffs path.
#
# Using a pinned path instead of the map name avoids ambiguity when
# more than one kernel map shares a name (e.g. XDP loaded on both
# nodes of the lab, each owning its own pass_counter / drop_counter
# instance). The container's bpffs is private, so each path is
# unambiguous within that container.
#
# Example:
#   docker exec clab-xdp-hoplimit-lab-node1 sum-percpu /sys/fs/bpf/pass
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: sum-percpu <pinned-path>" >&2
    echo "  e.g.  sum-percpu /sys/fs/bpf/pass" >&2
    exit 1
fi

PIN="$1"
if [[ ! -e "$PIN" ]]; then
    echo "[ERROR] no such pinned object: $PIN" >&2
    exit 2
fi

DUMP="$(bpftool map dump pinned "$PIN")"

# Sanity check: must be a per-CPU map (has .values; non-percpu uses .value).
if ! jq -e '.[0].values' <<< "$DUMP" > /dev/null; then
    echo "[ERROR] $PIN is not a per-CPU map (no .values field)" >&2
    exit 3
fi

NUM_CPUS=$(jq '.[0].values | length' <<< "$DUMP")
TOTAL=$(jq '[.[0].values[].value] | add' <<< "$DUMP")

echo "map: $PIN  ($NUM_CPUS CPUs)"
echo "non-zero per-CPU values:"
jq -r '.[0].values | map(select(.value != 0))[] | "  cpu \(.cpu): \(.value)"' <<< "$DUMP" \
    | grep -v '^$' || echo "  (all zero)"
echo "----"
echo "total: $TOTAL"
