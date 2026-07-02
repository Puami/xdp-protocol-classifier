#include "vmlinux.h"
#include <bpf/bpf_helpers.h>

struct {
    __uint(type, BPF_MAP_TYPE_ARRAY);
    __uint(max_entries, 1);
    __type(key, __u32);
    __type(value, __u64);
} packets_map SEC(".maps");

SEC("xdp")
int xdp_counter(struct xdp_md *ctx)
{
    __u32 key = 0;
    __u64 *count;
    
    count = bpf_map_lookup_elem(&packets_map, &key);
    if (count) {
        *count += 1;
        bpf_printk("xdp: packet %llu", *count);
    }

    return XDP_PASS;
}

char _license[] SEC("license") = "GPL";
