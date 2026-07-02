#!/bin/bash
LAB_NAME="xdp-hoplimit-lab"
IMAGE="clab-softnet-xdp-hoplimit:latest"
TOPOLOGY="xdp-hoplimit-lab.clab.yml"
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${LAB_DIR}/../lib/destroy.sh"
