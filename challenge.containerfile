FROM ghcr.io/jm-lemmi/netlab/clab-base:latest

COPY double-tagging.clab.yaml /app/topo.clab.yml

COPY config.json /root/.docker/config.json
RUN /app/prepull-images.sh
