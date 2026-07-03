# XDP Network Protocol Monitor (Intermediate Level)

## Introduction
This project builds a fast network tool using **eBPF** and **XDP**. The main goal is to watch network traffic and count packets for specific protocols like **HTTP, SSH, and DNS** without slowing down the system.

![Project Architecture Diagram](images/main.png)


## Why this project?
Instead of printing every packet to the screen (which slows down the system), our project uses **BPF Maps** to store data.
* **Very Fast:** It counts packets at high speed.
* **Low System Load:** It does not waste CPU power by printing logs.
* **Real-time Data:** It gives us accurate, up-to-date numbers for our traffic.

## Getting Started

### 1. Set up the project
Clone the repository and go to the source folder:
```bash
git clone <your-repository-url>
cd xdp-project-e1/src
```
### 2. Deploy the environment
Start the network containers:
```bash
sudo containerlab deploy -t xdp-lab.clab.yml
```

### 3. Compile and Attach
Compile the code and attach it to the network interfaces:
```bash
make
# Attach to node1 and node2
docker exec clab-xdp-lab-node1 bash -c 'ip link set dev eth1 xdp obj /work/bpf/classifier.bpf.o sec xdp'
docker exec clab-xdp-lab-node2 bash -c 'ip link set dev eth1 xdp obj /work/bpf/classifier.bpf.o sec xdp'
```
### 4. Prepare the container
Install the necessary tools inside node1 & node2:
```bash
docker exec -it clab-xdp-lab-node2 bash
apt update
apt install -y openssh-client curl dnsutils
```

### 5. Generate traffic and Monitor
After installing the tools on `node2`, you can generate traffic to the IP address of `node1` (10.0.3.1) and then check the results with other node.

1. **Generate traffic from node2 to node1:**
```bash
   # Test DNS
   dig @10.0.3.1
   
   # Test HTTP
   curl 10.0.3.1
   
   # Test SSH
   ssh 10.0.3.1
```

2. **View statistics:**
Check the counters in the eBPF map to see how many packets were caught for each protocol:
```bash
bpftool map dump name pkt_counts
```
The keys are mapped as follows: 0 for HTTP (port 80), 1 for SSH (port 22), and 2 for DNS (port 53)."









