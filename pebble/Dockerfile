FROM ubuntu:focal
RUN export DEBIAN_FRONTEND=noninteractive \
    && apt-get update -y \
    && apt install git golang -y
RUN git clone https://github.com/canonical/pebble \
    && cd pebble \
    && git checkout set-child-subreaper \
    && go build ./cmd/pebble

FROM test-patroni
USER root
COPY --from=0 /pebble/pebble /usr/bin/pebble
RUN mkdir /home/postgres/pebble
ENV PEBBLE /home/postgres/pebble
COPY 001-layer.yaml /home/postgres/pebble/layers/001-layer.yaml
ENTRYPOINT ["/usr/bin/pebble", "run"]