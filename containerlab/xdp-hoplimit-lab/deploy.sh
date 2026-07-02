#!/bin/bash
LAB_NAME="xdp-hoplimit-lab"
IMAGE="clab-softnet-xdp-hoplimit:latest"
TOPOLOGY="xdp-hoplimit-lab.clab.yml"
NODES="node1 node2"
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${LAB_DIR}/../lib/deploy.sh"
