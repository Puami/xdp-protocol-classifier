#!/bin/bash
LAB_NAME="bind-entrypoint-lab"
IMAGE="clab-softnet-bind-ep:latest"
TOPOLOGY="bind-entrypoint-lab.clab.yml"
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${LAB_DIR}/../lib/destroy.sh"
