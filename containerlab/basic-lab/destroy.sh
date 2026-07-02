#!/bin/bash
LAB_NAME="basic-lab"
IMAGE="clab-softnet-basic:latest"
TOPOLOGY="basic-lab.clab.yml"
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${LAB_DIR}/../lib/destroy.sh"
