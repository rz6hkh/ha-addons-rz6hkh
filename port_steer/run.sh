#!/usr/bin/env bash
# Port steer: source-based DNAT from LAN clients into another add-on.
#
# For every rule: TCP from <source> to <port> on this host is redirected to
# <target_port> of add-on <addon>, and only that flow is allowed through the
# Docker FORWARD chain. Everyone else keeps reaching whatever owns <port> on the
# host. The add-on IP is asked from the Supervisor on every pass, so a restart
# of the target add-on (new container IP) is followed automatically. All rules
# carry the comment "port_steer:<name>" and are removed on stop.
#
# While the target add-on is not running, the client is HELD for up to <hold>
# seconds: its connections are refused (TCP reset) instead of falling through
# to whatever owns <port> on the host. A client that meets a foreign service
# during a short restart (an appliance doing TLS against the host's MQTT
# broker) may give up for good; a refused connection is an ordinary retry.
# While a rule is held, the Supervisor is asked every FAST seconds, so the
# redirect is back as soon as the target is. After <hold> the rule is removed
# and the client gets the host port again (hold: 0 = remove at once).
set -uo pipefail

OPT=/data/options.json
TAG=port_steer
INTERVAL=$(jq -r '.interval // 30' "$OPT")
HOLD=$(jq -r '.hold // 300' "$OPT")
FAST=2
NAME_RE='^[a-z0-9_]{1,20}$'
IP_RE='^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$'

log() { echo "[$(date '+%F %T')] $*"; }

addon_ip() {
    # Only a running add-on with a real address; a stopped one reports 0.0.0.0.
    curl -fsS --max-time 10 -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        "http://supervisor/addons/$1/info" 2>/dev/null \
        | jq -r 'select(.data.state == "started") | .data.ip_address // empty' \
        | grep -v '^0\.0\.0\.0$' || true
}

# Delete every rule with our comment for <name> (or all of ours without a name).
drop_rules() {
    # iptables -S prints the comment in quotes: --comment "port_steer:name".
    # With a name: exact match; without: every rule of ours.
    local re="--comment \"?${TAG}:"
    [[ -n ${1:-} ]] && re="${re}${1}\"?( |$)"
    local table chain line
    for spec in "nat PREROUTING" "filter DOCKER-USER" "filter INPUT"; do
        read -r table chain <<<"$spec"
        iptables -t "$table" -S "$chain" 2>/dev/null | grep -E -- "$re" | while read -r line; do
            line=${line//\"/}   # names have no spaces, quotes can go
            # shellcheck disable=SC2086  # the rule spec must split into words
            iptables -t "$table" ${line/-A /-D } \
                || log "WARNING: could not remove: $line"
        done
    done
}

# Refuse <src> on <port> while the target is away: RETURN in nat/PREROUTING keeps
# the packet from Docker's own DNAT (it stays local), REJECT in INPUT answers
# it with a TCP reset before any host listener sees it.
hold_rules() {
    local name=$1 src=$2 port=$3 c="${TAG}:$1"
    drop_rules "$name"
    iptables -t nat -I PREROUTING 1 -s "$src" -p tcp --dport "$port" -m addrtype --dst-type LOCAL \
        -m comment --comment "$c" -j RETURN \
        && iptables -t filter -I INPUT 1 -s "$src" -p tcp --dport "$port" \
            -m comment --comment "$c" -j REJECT --reject-with tcp-reset
}

cleanup() {
    log "Stopping: removing all ${TAG} rules"
    drop_rules ""
    exit 0
}
trap cleanup TERM INT

# Validate rules once; a bad rule stops the add-on with a clear message.
mapfile -t RULES < <(jq -c '.rules[]?' "$OPT")
[[ ${#RULES[@]} -gt 0 ]] || log "No rules configured - nothing to do"
for r in "${RULES[@]}"; do
    name=$(jq -r .name <<<"$r"); src=$(jq -r .source <<<"$r")
    [[ $name =~ $NAME_RE ]] || { log "ERROR: rule name '$name': a-z, 0-9, _ only"; exit 1; }
    [[ $src =~ $IP_RE ]] || { log "ERROR: rule $name: source must be an IPv4 address or CIDR"; exit 1; }
done

drop_rules ""   # leftovers from a crash
declare -A STATE HELD_AT
log "Started: ${#RULES[@]} rule(s), check every ${INTERVAL} s, hold ${HOLD} s"

while true; do
    holding=0
    for r in "${RULES[@]}"; do
        name=$(jq -r .name <<<"$r"); src=$(jq -r .source <<<"$r")
        port=$(jq -r .port <<<"$r"); addon=$(jq -r .addon <<<"$r")
        tport=$(jq -r .target_port <<<"$r")
        cip=$(addon_ip "$addon")
        c="${TAG}:${name}"
        if [[ -z $cip ]]; then
            # Not running: hold (refuse) for HOLD seconds, then remove. A rule
            # never seen up (add-on started before its target) is held too.
            case ${STATE[$name]:-} in
                down) ;;
                hold)
                    if (( $(date +%s) - ${HELD_AT[$name]} >= HOLD )); then
                        log "Rule $name: add-on $addon still not running after ${HOLD} s - rule removed"
                        drop_rules "$name"; STATE[$name]=down
                    else
                        holding=1
                    fi ;;
                *)
                    if (( HOLD > 0 )) && hold_rules "$name" "$src" "$port"; then
                        log "Rule $name: add-on $addon is not running - $src refused on :$port for up to ${HOLD} s"
                        STATE[$name]=hold; HELD_AT[$name]=$(date +%s); holding=1
                    else
                        (( HOLD > 0 )) && log "ERROR: rule $name could not be held"
                        log "Rule $name: add-on $addon is not running - rule removed"
                        drop_rules "$name"; STATE[$name]=down
                    fi ;;
            esac
            continue
        fi
        nat=(-t nat PREROUTING -s "$src" -p tcp --dport "$port" -m addrtype --dst-type LOCAL
             -m comment --comment "$c" -j DNAT --to-destination "$cip:$tport")
        flt=(-t filter DOCKER-USER -s "$src" -d "$cip" -p tcp --dport "$tport"
             -m comment --comment "$c" -j ACCEPT)
        if ! iptables "${nat[0]}" "${nat[1]}" -C "${nat[@]:2}" 2>/dev/null \
            || ! iptables "${flt[0]}" "${flt[1]}" -C "${flt[@]:2}" 2>/dev/null; then
            drop_rules "$name"
            iptables "${nat[0]}" "${nat[1]}" -I "${nat[@]:2:1}" 1 "${nat[@]:3}" \
                && iptables "${flt[0]}" "${flt[1]}" -I "${flt[@]:2:1}" 1 "${flt[@]:3}" \
                && log "Rule $name: $src -> :$port => $addon ($cip:$tport)" \
                || log "ERROR: rule $name could not be applied"
            STATE[$name]=up
        fi
    done
    sleep "$( (( holding )) && echo "$FAST" || echo "$INTERVAL")" &
    wait $! || true
done
