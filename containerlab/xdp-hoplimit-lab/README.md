# XDP IPv6 Hop-Limit Filter Lab

## Overview

Two-node point-to-point lab that loads an XDP program parsing the L2/L3
headers and dropping IPv6 packets whose `hop_limit` equals **17**. All other
traffic (non-IPv6, or IPv6 with any other hop limit) is passed.

The two packet counters (`pass_counter`, `drop_counter`) are
**`BPF_MAP_TYPE_PERCPU_ARRAY`** maps. This is the central pedagogical point
of the lab — see [§ Per-CPU maps and no atomics](#per-cpu-maps-and-no-atomics)
below.

`src/hoplimit_filter.bpf.c` defines an `xdp_hoplimit_filter` program that:

- Parses the Ethernet header and checks `h_proto == ETH_P_IPV6` (`0x86DD`)
- If non-IPv6: increments `pass_counter` and returns `XDP_PASS`
- If IPv6 and `hop_limit == 17`: increments `drop_counter`, emits a
  `bpf_printk` trace line, returns `XDP_DROP`
- Otherwise: increments `pass_counter` and returns `XDP_PASS`

The program is attached on **node1** in the exercises below. Attach it on
node2 with the same command to enforce the filter in the opposite direction
as well.

## Architecture

```
node1 (10.0.4.1/24, fc00:4::1/64) ── eth1 (veth) ── eth1 ── node2 (10.0.4.2/24, fc00:4::2/64)
```

Both nodes have:
- `/sys/kernel/debug` bind-mounted from the host (BPF trace access via
  `trace_pipe`)
- A **private** `bpffs` mounted *inside* the container at `/sys/fs/bpf`
  by the entrypoint (`mount -t bpf bpf /sys/fs/bpf`). The host's `bpffs`
  is **not** bind-mounted in — see
  [§ Private bpf filesystem per container](#private-bpf-filesystem-per-container)
- `src/` bind-mounted read-only at `/work/bpf/` (compiled BPF objects)
- `bin/entrypoint.sh` bind-mounted at `/entrypoint.sh` (run by `exec`)
- `bin/sum-percpu.sh` bind-mounted at `/usr/local/bin/sum-percpu` (helper)

The Docker image (`clab-softnet-xdp-hoplimit:latest`) only carries the
*dependencies* (`iproute2`, `iputils-ping`, `bpftool`, `jq`); all scripts
live on the host and are bind-mounted.

## Prerequisites

- containerlab v0.73+
- Docker
- Host kernel with BTF: `/sys/kernel/btf/vmlinux`

## Student Workflow

All commands assume you are in this lab directory
(`containerlab/xdp-hoplimit-lab/`).

### 1. Compile the BPF program

```bash
cd src
make
cd ..
```

On first run this generates `vmlinux.h` from the host kernel BTF and then
compiles `hoplimit_filter.bpf.c` → `hoplimit_filter.bpf.o` inside the
`bpf-builder` container.

Expected output:
```
[INFO] vmlinux.h missing, generating automatically...
[INFO] Compiling hoplimit_filter.bpf.c...
[OK] Compiled: hoplimit_filter.bpf.c -> hoplimit_filter.bpf.o
```

### 2. Deploy the topology

```bash
./deploy.sh
```

The deploy script builds `clab-softnet-xdp-hoplimit:latest` (first time only)
and then runs `containerlab deploy`. At the end you should see both nodes in
state `running`:

```
│ clab-xdp-hoplimit-lab-node1 │ ... │ running │
│ clab-xdp-hoplimit-lab-node2 │ ... │ running │
```

### 3. Attach the XDP program on node1

```bash
docker exec clab-xdp-hoplimit-lab-node1 \
  ip link set dev eth1 xdp obj /work/bpf/hoplimit_filter.bpf.o sec xdp
```

Successful load is silent (no output). A verifier failure would print the
verifier log to stderr.

### 4. Verify XDP is attached

```bash
docker exec clab-xdp-hoplimit-lab-node1 bpftool net show dev eth1
```

Expected output (the `id` value will differ on each load):
```
xdp:
eth1(16) driver id 52

tc:

flow_dissector:

netfilter:
```

You can also list the two maps the program owns. Note the **`percpu_array`**
type:

```bash
docker exec clab-xdp-hoplimit-lab-node1 bash -c \
  'bpftool map show | grep -E "(pass_counter|drop_counter)"'
```

Expected (IDs differ):
```
22: percpu_array  name pass_counter  flags 0x0
23: percpu_array  name drop_counter  flags 0x0
```

### 5. Pin the BPF maps in the container's bpffs

`ip link set xdp obj ...` loads the program but does **not** auto-pin its
maps. Pin them by name into the container's private `bpffs` (see
[§ Private bpf filesystem per container](#private-bpf-filesystem-per-container)):

```bash
docker exec clab-xdp-hoplimit-lab-node1 \
  bpftool map pin name pass_counter /sys/fs/bpf/pass
docker exec clab-xdp-hoplimit-lab-node1 \
  bpftool map pin name drop_counter /sys/fs/bpf/drop
docker exec clab-xdp-hoplimit-lab-node1 ls /sys/fs/bpf/
```

Expected:
```
drop  ip  pass  tc  xdp
```

The `pass` and `drop` entries are your pinned maps; `ip`/`tc`/`xdp` are
auto-created by `iproute2` in the local bpffs.

> Note: pin-by-name works here because only node1 has XDP loaded. If you
> later attach the program on node2 as well, two kernel maps will share
> the same name and pin-by-name becomes ambiguous — use the pin-by-id
> approach shown in the bpffs-isolation demo at the end.

### 6. Generate traffic

Traffic is sent from node2 toward node1. XDP runs on the **ingress** side, so
the filter takes effect on node1's `eth1`.

#### 6a. IPv4 ping (should PASS — not IPv6, filter is bypassed)

```bash
docker exec clab-xdp-hoplimit-lab-node2 ping -c 3 10.0.4.1
```

Expected: `3 packets transmitted, 3 received, 0% packet loss`. Each request
increments `pass_counter` on some CPU.

#### 6b. Baseline IPv6 ping (default hop limit, should PASS)

```bash
docker exec clab-xdp-hoplimit-lab-node2 ping -6 -c 3 fc00:4::1
```

Expected: `3 packets transmitted, 3 received, 0% packet loss`. Default
`hop_limit` is `64`, not `17`, so the filter passes them.

#### 6c. IPv6 ping with hop_limit == 17 (should be DROPPED)

```bash
docker exec clab-xdp-hoplimit-lab-node2 ping -6 -c 3 -W 1 -t 17 fc00:4::1
```

Expected: `3 packets transmitted, 0 received, 100% packet loss`. The packets
reach node1's NIC, XDP runs before the network stack and drops them — node1
never sees them at all.

`-W 1` caps the per-reply wait at 1 second; without it `ping` keeps waiting
for replies that never arrive and the command takes ~12 s to return.

### 7. Read BPF map counters with `sum-percpu`

The helper `sum-percpu` (bind-mounted from `bin/sum-percpu.sh`) dumps a
per-CPU map by its pinned bpffs path, lists the CPUs that touched it, and
prints the total:

```bash
docker exec clab-xdp-hoplimit-lab-node1 sum-percpu /sys/fs/bpf/pass
docker exec clab-xdp-hoplimit-lab-node1 sum-percpu /sys/fs/bpf/drop
```

After running tests 6a + 6b + 6c, `drop_counter` should be **exactly 3**
(only the 6c packets match the filter). `pass_counter` is a lower bound of 6
(3 ICMPv4 echo + 3 ICMPv6 echo); IPv6 neighbor discovery on the link can
add a few more.

### 8. Watch the per-CPU distribution

To make the per-CPU spread visible, push more traffic so the kernel
schedules RX-softirq processing on multiple CPUs:

```bash
for i in $(seq 1 4); do
  docker exec clab-xdp-hoplimit-lab-node2 ping -6 -c 3 -i 0.02 -t 17 fc00:4::1 \
    > /dev/null 2>&1 || true
  docker exec clab-xdp-hoplimit-lab-node2 ping -6 -c 3 -i 0.02 fc00:4::1 \
    > /dev/null 2>&1
done
docker exec clab-xdp-hoplimit-lab-node1 sum-percpu /sys/fs/bpf/drop
```

Example output (CPU IDs, count of online CPUs and totals depend on your
host; on a 64-CPU host with the above traffic):
```
map: /sys/fs/bpf/drop  (64 CPUs)
non-zero per-CPU values:
  cpu 34: 3
  cpu 42: 3
  cpu 45: 3
  cpu 46: 3
----
total: 12
```

Four different CPUs touched the counter, each storing its own value. The BPF
program never used an atomic — see the next section.

### 9. Inspect trace_pipe (bpf_printk output for drops)

`trace_pipe` blocks until new trace data arrives, so use `timeout`:

```bash
# Terminal 1: start reading trace_pipe (background or separate terminal)
docker exec clab-xdp-hoplimit-lab-node1 \
  timeout 5 cat /sys/kernel/debug/tracing/trace_pipe

# Terminal 2: generate a packet that matches the filter
docker exec clab-xdp-hoplimit-lab-node2 ping -6 -c 2 -t 17 fc00:4::1
```

Expected trace_pipe output (PIDs, CPU IDs and timestamps vary):
```
            ping-3914    [023] ..s2. 30386.893002: bpf_trace_printk: xdp: drop hop_limit=17
            ping-3914    [023] ..s2. 30387.931717: bpf_trace_printk: xdp: drop hop_limit=17
```

No `bpf_trace_printk` lines should appear for packets that pass, because the
program calls `bpf_printk` only on the drop path.

> **Note:** `bpf_printk` is for debugging only — limited to ~16 ASCII
> characters and rate-limited by the kernel. Use BPF maps for production
> counters.

### 10. Detach XDP and destroy

```bash
docker exec clab-xdp-hoplimit-lab-node1 ip link set dev eth1 xdp off
./destroy.sh
```

If you also attached the program on node2, detach there too with the same
`xdp off` command before destroying.

## Per-CPU maps and no atomics

The counters use `BPF_MAP_TYPE_PERCPU_ARRAY`, **not** `BPF_MAP_TYPE_ARRAY`.
This changes the lookup semantics in a very specific way:

```c
__u64 *v = bpf_map_lookup_elem(&pass_counter, &key);
if (v)
    *v += 1;        /* safe — no atomic, no fence */
```

`bpf_map_lookup_elem` on a per-CPU map returns a pointer to the **calling
CPU's private slot** for that key. Two CPUs running the XDP program on the
same key get two *different* pointers, so the `*v += 1` non-atomic
read-modify-write cannot race — each CPU updates its own memory. No
`__sync_fetch_and_add`, no `LOCK` prefix on the CPU bus, no cache-line
ping-pong between CPUs.

The price is that there is no single "global" value. To get the total you
read all N per-CPU values from userspace and sum them — exactly what
`bpftool map dump` returns and what `sum-percpu` formats:

```
.[0].values = [
  { "cpu": 0, "value": ... },
  { "cpu": 1, "value": ... },
  ...
]
```

If you switched the map back to `BPF_MAP_TYPE_ARRAY`, all CPUs would race on
the same `__u64`, and you would lose increments under concurrent RX. The XDP
program would have to use `__sync_fetch_and_add(v, 1)` to be correct.

## Private bpf filesystem per container

The topology file does **not** bind-mount the host's `/sys/fs/bpf` into the
containers. Instead, each container's entrypoint runs

```bash
mount -t bpf bpf /sys/fs/bpf
```

so node1 and node2 each get their **own** `bpffs` instance, separate from
each other and from the host. Three independent mounts are observable:

```bash
$ docker exec clab-xdp-hoplimit-lab-node1 findmnt -t bpf
TARGET      SOURCE FSTYPE OPTIONS
/sys/fs/bpf bpf    bpf    rw,relatime

$ docker exec clab-xdp-hoplimit-lab-node2 findmnt -t bpf
TARGET      SOURCE FSTYPE OPTIONS
/sys/fs/bpf bpf    bpf    rw,relatime

$ findmnt -t bpf            # on the host
TARGET      SOURCE FSTYPE OPTIONS
/sys/fs/bpf bpf    bpf    rw,nosuid,nodev,noexec,relatime,mode=700
```

### What the bpffs isolates, and what it does not

The bpffs only isolates **pinned filesystem paths**. BPF programs and maps
themselves are **kernel-global** objects, with kernel-assigned IDs that are
not namespaced. From any privileged container, `bpftool prog show` and
`bpftool map show` enumerate everything in the kernel — including programs
and maps owned by other containers. The capability gate is `CAP_BPF` /
`CAP_SYS_ADMIN`, which the containerlab `kind: linux` runtime has.

So if both nodes attach the XDP program, both containers see four maps:

```
$ docker exec clab-xdp-hoplimit-lab-node1 \
    bash -c 'bpftool map show | grep -E "(pass|drop)_counter"'
54: percpu_array  name pass_counter  flags 0x0
55: percpu_array  name drop_counter  flags 0x0
60: percpu_array  name pass_counter  flags 0x0
61: percpu_array  name drop_counter  flags 0x0
```

What the private bpffs *does* give you is that **pins** stay local. Pinning
the same path in both containers does not collide and is not visible to the
other side or to the host.

### Demonstration

After attaching XDP on **both** nodes (step 3, repeated on node2) and
sending some asymmetric traffic, find each container's locally-attached
prog id from `bpftool net show dev eth1` (it's the program loaded against
the local view of `eth1`):

```bash
docker exec clab-xdp-hoplimit-lab-node1 bpftool net show dev eth1
docker exec clab-xdp-hoplimit-lab-node2 bpftool net show dev eth1
```

then pin one of each container's maps to the same path `/sys/fs/bpf/local`
(replace `54` and `60` with the `pass_counter` ids you observed):

```bash
docker exec clab-xdp-hoplimit-lab-node1 bpftool map pin id 54 /sys/fs/bpf/local
docker exec clab-xdp-hoplimit-lab-node2 bpftool map pin id 60 /sys/fs/bpf/local
```

Compare the three views of `/sys/fs/bpf/`:

```
$ docker exec clab-xdp-hoplimit-lab-node1 ls /sys/fs/bpf/
ip  local  tc  xdp

$ docker exec clab-xdp-hoplimit-lab-node2 ls /sys/fs/bpf/
ip  local  tc  xdp

$ sudo ls /sys/fs/bpf/         # on the host
ip  tc  xdp
```

Both containers have a `local` entry; the host does not. The `ip`/`tc`/`xdp`
entries are auto-created by `iproute2` in each bpffs when the respective
tooling is first used — they too are independent per-mount.

Each container's `local` pin points to a *different* kernel map, so reading
through the pinned path can yield different totals — proof that the two
pins reference different kernel objects:

```bash
docker exec clab-xdp-hoplimit-lab-node1 sum-percpu /sys/fs/bpf/local
docker exec clab-xdp-hoplimit-lab-node2 sum-percpu /sys/fs/bpf/local
```

Example totals (with asymmetric traffic, only the totals shown):
```
node1: total: 5
node2: total: 4
```

`sum-percpu` accepts a pinned bpffs path precisely so it stays unambiguous
in this scenario — pinning by *name* would have been ambiguous because two
kernel maps share each name (`pass_counter`, `drop_counter`) when XDP is
loaded on both nodes. See the pin-by-id note in step 5.

## How the filter works

```
        +-------- Ethernet --------+
ctx ->  | dst MAC | src MAC | type | ...
        +--------------------------+
                              |
                              v
                   type == 0x86DD (IPv6) ?
                    /                  \
                  no                   yes
                  |                      |
                XDP_PASS         +-- IPv6 header --+
              (pass_counter++)   | ... hop_limit ...|
                                 +------------------+
                                          |
                                  hop_limit == 17 ?
                                    /          \
                                  no           yes
                                  |              |
                              XDP_PASS       XDP_DROP
                          (pass_counter++) (drop_counter++)
```

All packet accesses are bounds-checked against `ctx->data_end` so the BPF
verifier accepts the program.

## ELF objects, sections, and how libbpf loads a `.bpf.o`

This section explains, from the ground up, why the `SEC(...)` annotations
in `hoplimit_filter.bpf.c` are the way the C source talks to the BPF
loader, and what actually happens to the `.bpf.o` between `make` and
`ip link set xdp obj …`.

### What is an ELF section

When the compiler (clang, gcc) translates a `.c` file into an object
file `.o`, it does **not** produce one blob of bytes. It produces a
structured file in **ELF** format (*Executable and Linking Format* —
that is the wording used by `man 5 elf` and by the original System V
ABI specification; "Linkable" is a common modern variant).

An ELF file is divided into **sections**. A section is a contiguous
region of bytes inside the file, identified by:

| Attribute | Example | Purpose |
|---|---|---|
| **name** | `.text`, `.data`, `xdp` | human-readable label |
| **type** | `PROGBITS`, `STRTAB`, `REL`, … | what kind of content lives inside |
| **flags** | `A` (alloc), `W` (write), `X` (exec) | how the section should be treated |
| **size / offset** | size and position inside the file | where it is and how big |

All these descriptors live in a table at the end of the file called the
**Section Header Table**. Inspect it with `readelf -S file.o`.

The "classic" sections every C `.o` produces:

| Name | Contents |
|---|---|
| `.text` | executable code (function instructions) |
| `.data` | initialized globals (`int x = 42;`) |
| `.bss` | zero-initialized globals (occupy RAM, not file space) |
| `.rodata` | read-only constants (string literals, `const` tables) |
| `.symtab` / `.strtab` | symbol names and their string contents |

### Custom sections and the `SEC(...)` macro

The ELF format lets the programmer put a symbol into a section with any
name they want, via the GCC/clang attribute
`__attribute__((section("name")))`. The libbpf macro `SEC(name)` is
exactly that. Read straight from `bpf/bpf_helpers.h` inside
`bpf-builder:latest`:

```c
#define SEC(name) __attribute__((section(name), used))
```

The two attributes do:
- **`section(name)`** — emit this symbol into the ELF section called
  `name` instead of the default `.text` / `.data`.
- **`used`** — keep the symbol even if no C code references it. The
  consumer is the kernel BPF loader, not another C function, so
  without `used` the optimizer (`-O2`) might decide it's dead code
  and remove it.

### What is a relocatable file

The ELF header has a field `Type` that tells the file's role. The
three types you'll meet:

| `Type` | What it is | `execve`-able? |
|---|---|---|
| `REL` — Relocatable file | output of the compiler: the `.o` | **No** |
| `EXEC` — Executable file | linker output, ready to run | Yes |
| `DYN` — Shared object | `.so` (also PIE executables) | Yes (for PIE) |

Our `hoplimit_filter.bpf.o` is a `REL`, verbatim from `readelf -h`:

```
$ readelf -h hoplimit_filter.bpf.o
  Class:    ELF64
  Type:     REL (Relocatable file)
  Machine:  Linux BPF
```

**Why "relocatable"?** Because it contains code whose references to
external symbols (functions in other `.o`'s, shared globals, BPF maps,
…) are **placeholders** that will need to be patched with the real
value when the file is combined or loaded. The compiler doesn't know
those values yet — it leaves zero and takes a note.

The notes live in **relocation sections** (ELF type `REL` or `RELA`),
one per code/data section that has references to resolve. In our
`.bpf.o` (`readelf -r`):

```
Relocation section '.relxdp' at offset 0xd08 contains 3 entries:
  Offset          Type           Sym. Value    Sym. Name
  000000000078    R_BPF_64_64    0x0           drop_counter
  0000000000b0    R_BPF_64_64    0x0           .rodata
  000000000108    R_BPF_64_64    0x20          pass_counter
```

Two columns to read carefully:

- **`Offset`** is the location *inside the `xdp` section* where the
  placeholder lives — the spot in the bytecode that the loader will
  patch.
- **`Sym. Value`** is the value of the referenced symbol as recorded in
  the symbol table — for a global variable this is the offset of the
  symbol *inside its own section*. From `readelf -s`:
  `drop_counter` lives at offset `0x00` of `.maps`, `pass_counter` at
  offset `0x20` (the two `__u64` map structs sit back-to-back inside
  `.maps`, which is `0x40` = 64 bytes total). `.rodata` is the section
  symbol, sitting at offset `0x00` of `.rodata`.

So the three rows mean: "patch the bytecode at offsets `0x78`, `0xb0`,
`0x108` of the `xdp` section so that it refers, respectively, to the
map at `.maps + 0x00` (i.e. `drop_counter`), to `.rodata + 0x00`, and
to the map at `.maps + 0x20` (i.e. `pass_counter`)".

The actual placeholders live inside the bytecode. The BPF instruction
at each `Offset` is an `ld_imm64` (opcode `0x18`, 16 bytes long), and
its immediate-value bytes are currently zero — confirmed by
`llvm-objdump -s -j xdp` (the 4 immediate bytes at `Offset + 4` are
`00 00 00 00`). The loader will overwrite those bytes with the real
value (for a map reference: the map FD obtained from `BPF_MAP_CREATE`).

Direct consequence: **a `.o` cannot be executed directly** (not even a
plain C one). Trying:

```
$ chmod +x hoplimit_filter.bpf.o && ./hoplimit_filter.bpf.o
bash: ./hoplimit_filter.bpf.o: cannot execute binary file: Exec format error
```

The kernel ELF loader refuses: a `REL` is not a runnable program.

### The three sections of our program

`hoplimit_filter.bpf.c` uses three different `SEC(...)` annotations:

| `SEC` name | Used on | What libbpf does with it |
|---|---|---|
| `"xdp"` | `xdp_hoplimit_filter` | calls `BPF_PROG_LOAD` with `prog_type = BPF_PROG_TYPE_XDP`. The verifier then accepts XDP-specific helpers and requires `struct xdp_md *` as the first arg. |
| `".maps"` | `pass_counter`, `drop_counter` | parses the BTF-typed struct as a map declaration and calls `BPF_MAP_CREATE` with the corresponding `map_type` / `key_size` / `value_size` / `max_entries`. The section name is exposed as `MAPS_ELF_SEC` in `bpf/btf.h`. |
| `"license"` | `_license[]` | reads the string and passes it to the kernel via the `license` field of `bpf_attr` in `BPF_PROG_LOAD` (`__aligned_u64 license;` in `linux/bpf.h`). The kernel uses it to gate access to GPL-only helpers. After load, `bpftool prog show` reports it (e.g. `gpl`). |

Layout produced by the compiler, from `llvm-objdump -h` on our
`hoplimit_filter.bpf.o`:

```
Idx Name          Size     VMA              Type
  3 xdp           00000150 0000000000000000 TEXT
  5 .maps         00000040 0000000000000000 DATA
  7 license       00000004 0000000000000000 DATA
```

`xdp` (336 bytes) is the verifier-accepted BPF bytecode of
`xdp_hoplimit_filter`; `.maps` (64 bytes) is two map definitions of 32
bytes each; `license` (4 bytes) is the literal `"GPL\0"`.

### BTF (BPF Type Format)

`readelf -S` also lists two sections we have not described yet —
`.BTF` and `.BTF.ext`, both `PROGBITS`. They hold **BTF**, *BPF Type
Format*, which the kernel docs define as "the metadata format which
encodes the debug info related to BPF program/map".

| Section | Contents |
|---|---|
| `.BTF` | type info (struct, union, enum, primitive types) + string table |
| `.BTF.ext` | per-function info, per-line info, CO-RE relocations |

The kernel also exposes its *own* BTF — the types of the running
kernel — at `/sys/kernel/btf/vmlinux` (present when the kernel is
built with `CONFIG_DEBUG_INFO_BTF=y`; on the host of this lab it is
about 6 MB of binary BTF).

Where BTF matters for this lab:

- **BTF-typed map definitions.** The `__uint(type, …)` / `__type(key,
  __u32)` / `__type(value, __u64)` syntax in the `.maps` section
  works because libbpf reads the encoded type info from `.BTF` and
  calls `BPF_MAP_CREATE` with the corresponding `map_type`,
  `key_size`, `value_size`, etc.
- **Map pretty-printing.** When `bpftool map dump` returns
  `{"key": 0, "value": N}`, it knows `key` is `__u32` and `value` is
  `__u64` from the map's BTF.
- **`vmlinux.h` generation.** The `scripts/build-bpf.sh` build script
  runs `bpftool btf dump file /sys/kernel/btf/vmlinux format c >
  vmlinux.h` — it reads the kernel's BTF and translates it into a C
  header (≈ 150 000 lines on this host) carrying every kernel struct.
  That is why `hoplimit_filter.bpf.c` can `#include "vmlinux.h"` and
  use `struct ipv6hdr` and `struct ethhdr` without pulling real
  kernel headers.
- **CO-RE (Compile Once, Run Everywhere).** The CO-RE relocations in
  `.BTF.ext` let libbpf patch field-access offsets in the BPF
  bytecode at load time by comparing the program's BTF to the
  kernel's BTF (`/sys/kernel/btf/vmlinux`). The same `.bpf.o` keeps
  working when kernel struct layouts shift across versions.

### How libbpf processes the `.bpf.o`

A plain C `.o` goes to the **linker** (`ld`), which combines it with
other `.o`s to produce an `EXEC` or `DYN` — at that point all the
placeholders have been resolved, the file has everything needed to
run, and it can be `execve`'d.

A `.bpf.o` **does not pass through the linker, and not through the
kernel ELF loader either**. It is consumed by **libbpf in userspace**
(invoked indirectly by `ip link set xdp obj …`, `bpftool prog load`,
or a libbpf skeleton). The flow:

1. open the `.bpf.o` as ELF and read the Section Header Table
2. for each `.maps` entry → call `bpf(BPF_MAP_CREATE, …)` and obtain
   a *file descriptor* for the new map
3. for each program section (here `xdp`) → walk the matching
   relocation section (`.relxdp`) and, for every placeholder that
   references a map (e.g. `drop_counter`), patch the bytecode with
   the FD of the map created at step 2. **This is the relocation
   step**, done in userspace
4. for `license` → read the string (`"GPL"`)
5. call `bpf(BPF_PROG_LOAD, type=BPF_PROG_TYPE_XDP, insns=<relocated
   bytecode>, license="GPL", …)`. The kernel receives **only**
   bytecode + program type + license — it never sees an ELF

The BPF subsystem in the kernel does not know about ELF. libbpf, in
userspace, does all the ELF parsing and the relocation work, and then
talks to the kernel through a handful of `bpf_attr` fields of the
`bpf()` syscall.

## Editing the bind-mounted scripts

`bin/entrypoint.sh` and `bin/sum-percpu.sh` are bind-mounted into the
running containers, **not** baked into the image. You can edit them on the
host. There is one caveat:

Docker bind-mounts a **single file** by inode at container creation time.
Editors that save via atomic rename (vim with default backup mode, VS Code,
`sed -i`, `Write`-style tooling, etc.) replace the file with a new inode,
and the container keeps seeing the old one. After such an edit, run:

```bash
./destroy.sh && ./deploy.sh
```

to recreate the containers so the new inode is picked up. In-place edits
(e.g. `echo … >> bin/sum-percpu.sh`, or editors configured to overwrite the
original file) are visible to the container immediately.
