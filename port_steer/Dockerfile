# Official Home Assistant base image from ghcr.io (Alpine 3.20). Its s6 init is
# not used: tini (init: true) runs run.sh directly.
ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base:3.20
FROM ${BUILD_FROM}

# iptables here is the nft backend - the same one Docker uses on HA OS
RUN apk add --no-cache iptables jq curl bash

COPY run.sh /run.sh
RUN chmod a+x /run.sh

ENTRYPOINT []
CMD ["/run.sh"]
