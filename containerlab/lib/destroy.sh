#!/bin/bash
# Generic destroy logic. Must be sourced by a lab-specific wrapper that sets:
#   LAB_NAME   - containerlab topology name (matches 'name:' in .clab.yml)
#   IMAGE      - docker image tag to optionally remove
#   TOPOLOGY   - topology filename (e.g. basic-lab.clab.yml)
#   LAB_DIR    - absolute path to the lab directory
set -euo pipefail

echo "=== Destroy ${LAB_NAME} ==="

cd "${LAB_DIR}"

echo ""
echo "== Step 1: Destroy topology =="
containerlab destroy -t "${TOPOLOGY}" --cleanup
echo "[OK] Topology destroyed"

echo ""
echo "== Step 2: Remove Docker image? =="
if docker images "${IMAGE}" --format '{{.Repository}}:{{.Tag}}' | grep -q "${IMAGE}"; then
    read -r -p "Remove ${IMAGE}? [y/N] " answer
    if [[ "${answer}" =~ ^[Yy]$ ]]; then
        docker rmi "${IMAGE}"
        echo "[OK] Docker image removed"
    else
        echo "[INFO] Docker image kept"
    fi
fi

echo ""
echo "=== Cleanup Complete ==="
