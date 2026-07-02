#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>

#define ETH_P_IPV6		0x86DD
#define TARGET_HOP_LIMIT	17

struct {
	__uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
	__uint(max_entries, 1);
	__type(key, __u32);
	__type(value, __u64);
} pass_counter SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
	__uint(max_entries, 1);
	__type(key, __u32);
	__type(value, __u64);
} drop_counter SEC(".maps");

static __always_inline void bump(void *map)
{
	__u32 key = 0;
	__u64 *v;

	v = bpf_map_lookup_elem(map, &key);
	if (v)
		*v += 1;
}

SEC("xdp")
int xdp_hoplimit_filter(struct xdp_md *ctx)
{
	void *data_end = (void *)(long)ctx->data_end;
	void *data = (void *)(long)ctx->data;
	struct ipv6hdr *ip6;
	struct ethhdr *eth;

	eth = data;
	if ((void *)(eth + 1) > data_end)
		goto pass;

	if (eth->h_proto != bpf_htons(ETH_P_IPV6))
		goto pass;

	ip6 = (void *)(eth + 1);
	if ((void *)(ip6 + 1) > data_end)
		goto pass;

	if (ip6->hop_limit == TARGET_HOP_LIMIT) {
		bump(&drop_counter);
		bpf_printk("xdp: drop hop_limit=%d", TARGET_HOP_LIMIT);
		return XDP_DROP;
	}

pass:
	bump(&pass_counter);
	return XDP_PASS;
}

char _license[] SEC("license") = "GPL";
