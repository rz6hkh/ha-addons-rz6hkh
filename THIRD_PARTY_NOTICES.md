# Third-party software

This repository contains only the add-on definition and its start script
(MIT, see `LICENSE`). It does **not** ship binaries. When the Home Assistant
Supervisor builds the add-on on your device, it pulls these components:

| Component | Source | License |
|---|---|---|
| amneziawg-go | `amneziavpn/amneziawg-go:3.1.20260828` (Docker Hub), <https://github.com/amnezia-vpn/amneziawg-go> | MIT |
| amneziawg-tools (`awg`, `awg-quick`) | same image, <https://github.com/amnezia-vpn/amneziawg-tools> tag `v3.1.20260812` | GPL-2.0 |
| Alpine Linux 3.19 base, `bash`, `iproute2`, `iptables`, `jq` | same image + Alpine packages | various open-source licenses |

If you publish a prebuilt image of this add-on, you redistribute the GPL-2.0
tools and must follow their license (provide the corresponding source).

"WireGuard" is a registered trademark of Jason A. Donenfeld. "AmneziaWG" and
"Amnezia" belong to their owners. This project is not affiliated with or
endorsed by either.
