# Assignment: Bind-Mount Entrypoint in ContainerLab

In the `basic-lab` topology, the entrypoint script is baked into the Docker image via `COPY`. This means every change to the script requires rebuilding the image.

Your task is to modify the lab so that the entrypoint is **not** copied into the image, but instead **bind-mounted from the host** at runtime via the containerlab topology file.

## Requirements

1. Remove the `COPY` instruction for the entrypoint from the `Dockerfile` and build a new image
2. Add a bind mount in the topology file so that `bin/entrypoint.sh` on the host is mounted at `/entrypoint.sh` inside each container
3. The `exec` directive and the network configuration must work exactly as before

## Verification

Run `./deploy.sh` and check that both nodes configure their interfaces correctly and can ping each other in IPv4 and IPv6.
