# Changelog

## 0.1.0

- Source-based DNAT into another add-on (nat/PREROUTING + DOCKER-USER ACCEPT).
- Target add-on IP is read from the Supervisor every pass; rules follow restarts.
- Rules are tagged `port_steer:<name>` and removed on stop.
