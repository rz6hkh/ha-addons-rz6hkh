# Home Assistant add-on: AmneziaWG client

Unofficial [AmneziaWG](https://docs.amnezia.org/documentation/amnezia-wg/) 3.1
**client** tunnel for Home Assistant OS. Home Assistant dials out to your
AmneziaWG server (for example on a VPS) and becomes reachable at its tunnel
address. Userspace `amneziawg-go`, no kernel module needed.

- Private key is generated inside the add-on and never leaves it; only the
  public key is printed to the log.
- Secrets never appear in the log.
- Refuses to start if the interface or a route to the tunnel networks already
  exists on the host.
- Base image pinned by digest: `amneziavpn/amneziawg-go:3.1.20260828`.
- amd64 only (the official image is published for amd64).

## Also in this repository: Port steer

`port_steer` — source-based port redirect: chosen LAN clients' TCP ports go
into another add-on, everyone else keeps the host port (for example one
appliance to an add-on on 8883 while other devices stay on the MQTT broker).
Rules follow the target add-on's container IP and are removed on stop. See
`port_steer/DOCS.md`.

## Install

Settings → Add-ons → Add-on store → ⋮ → Repositories → add
`https://github.com/rz6hkh/ha-addon-amneziawg`, then install
**AmneziaWG client**. Documentation is in the add-on's Documentation tab
(`amneziawg_client/DOCS.md`).

---

**RU.** Неофициальный аддон-клиент AmneziaWG 3.1 для Home Assistant OS: HA сам
подключается к вашему серверу AmneziaWG и доступен по адресу в туннеле.
Приватный ключ создаётся внутри аддона и никуда не уходит, секреты в журнал не
пишутся. Подробности — во вкладке «Документация» аддона.

Not affiliated with Amnezia or WireGuard. See `THIRD_PARTY_NOTICES.md` for
licenses of the components pulled at build time. MIT, see `LICENSE`.
