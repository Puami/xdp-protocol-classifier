#!/bin/bash
LAB_NAME="xdp-lab"
IMAGE="clab-softnet-xdp:latest"
TOPOLOGY="xdp-lab.clab.yml"
NODES="node1 node2"
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${LAB_DIR}/../lib/deploy.sh"
