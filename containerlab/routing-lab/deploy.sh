#!/bin/bash
LAB_NAME="routing-lab"
IMAGE="clab-softnet-routing:latest"
TOPOLOGY="routing-lab.clab.yml"
NODES="hs1 rt1 hs2"
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${LAB_DIR}/../lib/deploy.sh"
