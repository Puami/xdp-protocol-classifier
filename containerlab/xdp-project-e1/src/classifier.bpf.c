#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>

// Macro to convert host byte order to network byte order
// #define bpf_htons(x) __builtin_bswap16(x)
// #define bpf_ntohs(x) __builtin_bswap16(x)

// Protocol Definitions
#define ETH_P_IP    0x0800  // IPv4
#define ETH_P_IPV6  0x86DD  // IPv6
#define IPPROTO_TCP 6
#define IPPROTO_UDP 17

#define IDX_HTTP 0
#define IDX_SSH  1
#define IDX_DNS  2


struct {
    __uint(type, BPF_MAP_TYPE_ARRAY);
    __uint(max_entries, 3);
    __type(key, __u32);
    __type(value, __u64);
} pkt_counts SEC(".maps");

SEC("xdp")
int protocol_classifier(struct xdp_md *ctx) {
    void *data_end = (void *)(long)ctx->data_end;
    void *data     = (void *)(long)ctx->data;
    
    __u32 index = 0;
    int matched = 0;
    __u64 *value;

    // 1. Parse Ethernet Header
    struct ethhdr *eth = data;
    if ((void *)(eth + 1) > data_end) {
        return XDP_PASS;
    }

    __u8 l4_protocol = 0;
    void *transport_hdr = NULL;

    // 2. Identify IP Version and locate Layer 4 header
    if (eth->h_proto == bpf_htons(ETH_P_IP)) {
        // --- IPv4 Processing ---
        struct iphdr *ip = (void *)(eth + 1);
        if ((void *)(ip + 1) > data_end) {
            return XDP_PASS;
        }
        
        __u32 ip_hdr_len = ip->ihl * 4;
        if ((void *)ip + ip_hdr_len > data_end) {
            return XDP_PASS;
        }

        l4_protocol = ip->protocol;
        transport_hdr = (void *)ip + ip_hdr_len;

    } else if (eth->h_proto == bpf_htons(ETH_P_IPV6)) {
        // --- IPv6 Processing ---
        struct ipv6hdr *ipv6 = (void *)(eth + 1);
        if ((void *)(ipv6 + 1) > data_end) {
            return XDP_PASS;
        }

        l4_protocol = ipv6->nexthdr;
        // In a basic implementation, we assume no IPv6 Extension Headers
        transport_hdr = (void *)(ipv6 + 1);

    } else {
        // Not IPv4 or IPv6 (e.g., ARP)
        return XDP_PASS;
    }

    // 3. Inspect Layer 4 (TCP / UDP) for both IPv4 and IPv6
    if (l4_protocol == IPPROTO_TCP) {
        struct tcphdr *tcp = transport_hdr;
        if ((void *)(tcp + 1) > data_end) {
            return XDP_PASS;
        }

        __u16 src_port  = bpf_ntohs(tcp->source);
        __u16 dest_port = bpf_ntohs(tcp->dest);

        if (src_port == 80 || dest_port == 80) {
            index = IDX_HTTP;
            matched = 1;
            bpf_printk("HTTP packet detected (TCP port 80)\\n");
        } else if (src_port == 22 || dest_port == 22) {
            bpf_printk("SSH packet detected (TCP port 22)\\n");
            index = IDX_SSH;
            matched = 1;
        }

    } else if (l4_protocol == IPPROTO_UDP) {
        struct udphdr *udp = transport_hdr;
        if ((void *)(udp + 1) > data_end) {
            return XDP_PASS;
        }

        __u16 src_port  = bpf_ntohs(udp->source);
        __u16 dest_port = bpf_ntohs(udp->dest);

        if (src_port == 53 || dest_port == 53) {
            bpf_printk("DNS packet detected (UDP port 53)\\n");
            index = IDX_DNS;
            matched = 1;
        }
    }
    if (matched) {
        value = bpf_map_lookup_elem(&pkt_counts, &index);
        if (value) {
            __sync_fetch_and_add(value, 1);
        }
    }    

    return XDP_PASS;
}

char _license[] SEC("license") = "GPL";
