# rz6hkh — Home Assistant add-ons

Unofficial add-ons for Home Assistant OS. amd64 only.

| Add-on | Version | What it does |
|---|---|---|
| [AmneziaWG client](amneziawg_client/DOCS.md) | 0.1.0 | AmneziaWG 3.1 client tunnel (userspace amneziawg-go) |
| [Port steer](port_steer/DOCS.md) | 0.1.0 | Source-based port redirect: chosen LAN clients' TCP ports into another add-on |

## Install

Settings → Add-ons → Add-on store → ⋮ → Repositories → add

    https://github.com/rz6hkh/ha-addons-rz6hkh

Both add-ons then appear in the store under **rz6hkh add-ons**. Each has its
own Documentation tab (the `DOCS.md` linked above).

## AmneziaWG client

[AmneziaWG](https://docs.amnezia.org/documentation/amnezia-wg/) 3.1 **client**
tunnel. Home Assistant dials out to your AmneziaWG server (for example on a
VPS) and becomes reachable at its tunnel address. Userspace `amneziawg-go`, no
kernel module needed.

- Private key is generated inside the add-on and never leaves it; only the
  public key is printed to the log.
- Secrets never appear in the log.
- Refuses to start if the interface or a route to the tunnel networks already
  exists on the host — an existing tunnel is never touched.
- Base image pinned by digest: `amneziavpn/amneziawg-go:3.1.20260828`.

## Port steer

Redirects a TCP port into another add-on **only for chosen LAN clients**;
everyone else keeps reaching whatever owns that port on the host. Example: one
appliance goes to an add-on on 8883 while other devices stay on the MQTT
broker on the same port.

- Two `iptables` rules per entry: DNAT in `nat/PREROUTING` and ACCEPT in
  `DOCKER-USER`.
- The target add-on's container IP is read from the Supervisor on every pass,
  so rules follow its restarts.
- Rules are tagged `port_steer:<name>` and removed on stop or when the target
  add-on is not running.
- The target add-on does not need to publish its port on the host.

---

**RU.** Неофициальные аддоны для Home Assistant OS (amd64):

- **AmneziaWG client** — клиент AmneziaWG 3.1: HA сам подключается к вашему
  серверу AmneziaWG и доступен по адресу в туннеле. Приватный ключ создаётся
  внутри аддона и никуда не уходит, секреты в журнал не пишутся.
- **Port steer** — перенаправляет TCP-порт в другой аддон только для выбранных
  клиентов сети; остальные по-прежнему попадают в то, что держит порт на хосте.

Подключение — ссылка на репозиторий выше, подробности — во вкладке
«Документация» каждого аддона.

Not affiliated with Amnezia, WireGuard or Home Assistant. See
`THIRD_PARTY_NOTICES.md` for licenses of the components pulled at build time.
MIT, see `LICENSE`.
