# Changelog

## 0.2.0

- While the target add-on is not running, the client is held for `hold` seconds
  (default 300): its connections get a TCP reset instead of reaching the service
  that owns the port on the host. An LG washer that met the host MQTT broker
  during a 30 s restart window dropped off Wi-Fi until its power button was pressed.
- While a rule is held, the Supervisor is asked every 2 s, so the redirect returns
  as soon as the target does. `hold: 0` keeps the old behaviour.

## 0.1.0

- Source-based DNAT into another add-on (nat/PREROUTING + DOCKER-USER ACCEPT).
- Target add-on IP is read from the Supervisor every pass; rules follow restarts.
- Rules are tagged `port_steer:<name>` and removed on stop.
