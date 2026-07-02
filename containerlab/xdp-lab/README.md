# XDP Packet Counter Lab

## Overview

Two-node point-to-point lab demonstrating eBPF XDP loading, traffic counting,
and debugging. The topology consists of two containers joined by a virtual
ethernet link (`eth1`). The source in `src/test_xdp.bpf.c` defines an
`xdp_counter` program that:

- Increments a BPF map counter for every packet seen on `eth1`
- Emits a `bpf_printk` message per packet to the kernel trace buffer

The exercises below load the program on **node1**. Load it on node2 with the
same command to observe counters on both interfaces.

## Architecture

```
node1 (10.0.3.1/24) ── eth1 (veth, mtu 1500) ── eth1 ── node2 (10.0.3.2/24)
```

Both nodes have:
- `/sys/kernel/debug` — BPF trace access (`trace_pipe`)
- `/sys/fs/bpf` — BPF filesystem (mounted for future use; maps are NOT
  auto-pinned and are accessed via `bpftool map` instead)
- `src/` bind-mounted read-only at `/work/bpf/`

## Prerequisites

- containerlab v0.73+
- Docker
- Host kernel with BTF: `/sys/kernel/btf/vmlinux`

## Student Workflow

All commands assume you are in the project root
(`/home/ubuntu/clab-softnet`).

### 1. Compile the BPF program

```bash
cd containerlab/xdp-lab/src
make
```

Generates `vmlinux.h` from host kernel BTF (on first run) and compiles
`test_xdp.bpf.c` → `test_xdp.bpf.o` inside the `bpf-builder` container.

```bash
cd ..
```

### 2. Deploy the topology

```bash
./deploy.sh
```

### 3. Attach the XDP program on node1

```bash
docker exec clab-xdp-lab-node1 bash -c 'ip link set dev eth1 xdp obj /work/bpf/test_xdp.bpf.o sec xdp'
```

(Repeat on node2 with `clab-xdp-lab-node2` to also attach there.)

### 4. Verify XDP is attached

```bash
docker exec clab-xdp-lab-node1 bash -c 'bpftool net show dev eth1'
```

### 5. Generate traffic (bidirectional)

```bash
# node2 → node1
docker exec clab-xdp-lab-node2 bash -c 'ping -c 5 10.0.3.1'

# node1 → node2
docker exec clab-xdp-lab-node1 bash -c 'ping -c 5 10.0.3.2'
```

### 6. Read BPF map counter

`ip link set xdp obj ...` loads the program but does **NOT** pin its maps to
`/sys/fs/bpf`. The map lives in kernel memory and is accessed by name or ID.

```bash
# List all maps to find packets_map
docker exec clab-xdp-lab-node1 bash -c 'bpftool map show'

# Dump by name (works without pinning)
docker exec clab-xdp-lab-node1 bash -c 'bpftool map dump name packets_map'
```

### 7. Pin the BPF map to /sys/fs/bpf (optional)

To persist the map as a filesystem entry for later access:

```bash
# Get the map ID (e.g., 565)
docker exec clab-xdp-lab-node1 bash -c 'bpftool map show name packets_map'

# Pin it (replace 565 with the actual ID)
docker exec clab-xdp-lab-node1 bash -c 'bpftool map pin id 565 /sys/fs/bpf/packets_map'

# Now you can dump via the pinned path
docker exec clab-xdp-lab-node1 bash -c 'bpftool map dump pinned /sys/fs/bpf/packets_map'
```

### 8. Inspect trace_pipe (bpf_printk output)

`trace_pipe` blocks until new trace data arrives, so use `timeout`:

```bash
# In a first terminal, start reading trace_pipe
docker exec clab-xdp-lab-node1 bash -c 'timeout 5 cat /sys/kernel/debug/tracing/trace_pipe'

# In a second terminal, generate traffic to produce trace entries
docker exec clab-xdp-lab-node2 bash -c 'ping -c 3 10.0.3.1'
```

Expected trace_pipe output (process names and PIDs vary):

```
            ping-12345 [005] ..s2  123.456789: bpf_trace_printk: xdp: packet 1
            ping-12345 [005] ..s2  123.456790: bpf_trace_printk: xdp: packet 2
```

> **Note:** `bpf_printk` is for debugging only. It is limited to 16 ASCII
> characters and rate-limited. For production counters, use BPF maps.

### 9. Detach XDP and destroy

```bash
docker exec clab-xdp-lab-node1 bash -c 'ip link set dev eth1 xdp off'

# Repeat for node2 if loaded there too

cd containerlab/xdp-lab
./destroy.sh
```
