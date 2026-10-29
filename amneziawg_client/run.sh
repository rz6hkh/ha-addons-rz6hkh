#!/usr/bin/env bash
# AmneziaWG client for Home Assistant OS.
#
# Builds the tunnel config from the add-on options, brings the interface up
# on the host network and watches it. Secrets (private key, preshared key,
# header protection key) are never written to the log: the config lives only
# inside the container, and tool output is masked before it is printed.
set -euo pipefail
umask 077

OPTIONS=/data/options.json
KEYFILE=/data/private_key
CONFDIR=/etc/amnezia/amneziawg

# Interface keys that may be set through the "obfuscation" list (amneziawg-tools
# v3.1.20260812, src/config.c). HeaderProtectionKey is a secret and has its own
# password option, so it is not accepted here.
IFACE_KEYS='Jc|Jmin|Jmax|S1|S2|S3|S4|H1|H2|H3|H4|I1|I2|I3|I4|I5|ContentPaddingAddition|RekeyAfterTime|RekeyTimeout|RejectAfterTime|KeepaliveTimeout|MaxHandshakeAttempts|RandomTrailers|DisableCookies'

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
fail() { log "ERROR: $*"; exit 1; }
opt() { jq -r "$1 // empty" "$OPTIONS"; }
# Anything that looks like a key (43 base64 chars + "=") is hidden in tool output.
mask() { sed -E 's#[A-Za-z0-9+/]{42,43}=#<hidden>#g'; }

# ---------------------------------------------------------------- options ---
IFACE=$(opt '.interface')
[[ -n $IFACE ]] || IFACE=awg0
[[ $IFACE =~ ^[a-z][a-z0-9]{0,14}$ ]] || fail "interface: only a-z and 0-9, up to 15 chars"
CONF="$CONFDIR/$IFACE.conf"

mapfile -t ADDRESSES < <(jq -r '.address[]? // empty' "$OPTIONS")
[[ ${#ADDRESSES[@]} -gt 0 ]] || fail "address: set at least one tunnel address, e.g. 10.0.0.3/32"

PEER_PUB=$(opt '.peer.public_key')
[[ $PEER_PUB =~ ^[A-Za-z0-9+/]{43}=$ ]] || fail "peer.public_key: not a valid key"
PEER_PSK=$(opt '.peer.preshared_key')
[[ -z $PEER_PSK || $PEER_PSK =~ ^[A-Za-z0-9+/]{43}=$ ]] || fail "peer.preshared_key: not a valid key"
ENDPOINT=$(opt '.peer.endpoint')
ENDPOINT_RE='^[][A-Za-z0-9.:-]+:[0-9]{1,5}$'
[[ $ENDPOINT =~ $ENDPOINT_RE ]] || fail "peer.endpoint: expected host:port"
mapfile -t ALLOWED < <(jq -r '.peer.allowed_ips[]? // empty' "$OPTIONS")
[[ ${#ALLOWED[@]} -gt 0 ]] || fail "peer.allowed_ips: set at least one network, e.g. 10.0.0.0/24"
KEEPALIVE=$(opt '.peer.persistent_keepalive')
ADV_SEC=$(opt '.peer.advanced_security')
[[ -z $ADV_SEC || $ADV_SEC =~ ^[A-Za-z0-9_-]+$ ]] || fail "peer.advanced_security: unexpected value"
MTU=$(opt '.mtu')
TABLE=$(opt '.table')
[[ -z $TABLE || $TABLE =~ ^(off|auto|[0-9]+)$ ]] || fail "table: off, auto or a number"
HPK=$(opt '.header_protection_key')
STALE_MIN=$(opt '.restart_if_no_handshake_min')
STALE_MIN=${STALE_MIN:-0}

# Obfuscation lines: one "Key = Value" per item, only whitelisted keys, no
# line breaks inside a value (that would let an item inject its own section).
if [[ $(jq '[.obfuscation[]? | select(test("[\\n\\r]"))] | length' "$OPTIONS") != 0 ]]; then
    fail "obfuscation: line breaks are not allowed inside an item"
fi
mapfile -t OBFUSCATION < <(jq -r '.obfuscation[]? // empty' "$OPTIONS")
for line in "${OBFUSCATION[@]}"; do
    [[ $line =~ ^[[:space:]]*($IFACE_KEYS)[[:space:]]*=[[:space:]]*[^[:space:]] ]] \
        || fail "obfuscation: unsupported line (allowed keys: ${IFACE_KEYS//|/, })"
done

# ------------------------------------------------------- safety checks ---
# Never touch an interface or routes that someone else on the host owns.
if ip link show "$IFACE" >/dev/null 2>&1; then
    fail "interface $IFACE already exists on the host - refusing to touch it"
fi
for net in "${ALLOWED[@]}"; do
    if [[ -n $(ip route show "$net" 2>/dev/null) ]]; then
        fail "a route to $net already exists on the host - refusing to override it"
    fi
done

# --------------------------------------------------------------- key ---
if [[ ! -s $KEYFILE ]]; then
    log "No private key yet - generating one. It stays in this add-on's /data."
    awg genkey > "$KEYFILE"
fi
chmod 600 "$KEYFILE"
log "Public key of this client (give it to the server admin): $(awg pubkey < "$KEYFILE")"

# ------------------------------------------------------------ config ---
mkdir -p "$CONFDIR"
{
    echo "[Interface]"
    echo "PrivateKey = $(cat "$KEYFILE")"
    for a in "${ADDRESSES[@]}"; do echo "Address = $a"; done
    [[ -n $MTU ]] && echo "MTU = $MTU"
    [[ -n $TABLE ]] && echo "Table = $TABLE"
    for line in "${OBFUSCATION[@]}"; do echo "$line"; done
    [[ -n $HPK ]] && echo "HeaderProtectionKey = $HPK"
    echo
    echo "[Peer]"
    echo "PublicKey = $PEER_PUB"
    [[ -n $PEER_PSK ]] && echo "PresharedKey = $PEER_PSK"
    echo "Endpoint = $ENDPOINT"
    echo "AllowedIPs = $(IFS=,; echo "${ALLOWED[*]}")"
    [[ -n $KEEPALIVE && $KEEPALIVE != 0 ]] && echo "PersistentKeepalive = $KEEPALIVE"
    [[ -n $ADV_SEC ]] && echo "AdvancedSecurity = $ADV_SEC"
    :
} > "$CONF"

log "Config: interface $IFACE, ${#ADDRESSES[@]} address(es), peer $ENDPOINT," \
    "allowed ${ALLOWED[*]}, ${#OBFUSCATION[@]} obfuscation line(s)," \
    "psk $([[ -n $PEER_PSK ]] && echo set || echo none)," \
    "header protection key $([[ -n $HPK ]] && echo set || echo none)"

# --------------------------------------------------------------- run ---
down() {
    log "Stopping: bringing $IFACE down"
    awg-quick down "$CONF" 2>&1 | mask || true
    exit 0
}
trap down TERM INT

log "Bringing $IFACE up"
if ! awg-quick up "$CONF" 2>&1 | mask; then
    fail "awg-quick up failed (see above)"
fi

# Watch: the interface and the userspace daemon must stay alive; optionally
# restart when the peer has been silent for too long. Exiting non-zero lets the
# Supervisor watchdog restart the add-on.
state=""
while true; do
    sleep 30 &
    wait $! || true
    ip link show "$IFACE" >/dev/null 2>&1 || fail "interface $IFACE disappeared"
    pgrep -x amneziawg-go >/dev/null || fail "amneziawg-go is not running"
    last=$(awg show "$IFACE" latest-handshakes 2>/dev/null | awk '{print $2; exit}')
    age=$(( $(date +%s) - ${last:-0} ))
    if [[ ${last:-0} -eq 0 ]]; then
        new="no handshake yet"
    elif (( age <= 180 )); then
        new="handshake ok"
    else
        new="no handshake for $((age / 60)) min"
    fi
    if [[ $new != "$state" ]]; then
        log "Peer: $new"
        state=$new
    fi
    if (( STALE_MIN > 0 && ${last:-0} > 0 && age > STALE_MIN * 60 )); then
        awg-quick down "$CONF" 2>&1 | mask || true
        fail "no handshake for more than $STALE_MIN min - exiting so the watchdog restarts the tunnel"
    fi
done
