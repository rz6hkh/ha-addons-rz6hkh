# Official AmneziaWG image (Alpine 3.19 + amneziawg-go + amneziawg-tools 3.1),
# pinned by digest: a tag on Docker Hub can be re-pushed, a digest cannot.
# The image is pulled on the user's device when the Supervisor builds the
# add-on; this repository does not redistribute any binaries.
FROM amneziavpn/amneziawg-go:3.1.20260828@sha256:cbafc02b8373a83f428272db6d8001b37bc02e6211cbd8c0cb4e2e3759b12b72

RUN apk add --no-cache jq=1.7.1-r0

COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD ["/run.sh"]
