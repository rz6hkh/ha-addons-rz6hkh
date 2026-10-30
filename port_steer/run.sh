#!/usr/bin/env bash
# Port steer: source-based DNAT from LAN clients into another add-on.
#
# For every rule: TCP from <source> to <port> on this host is redirected to
# <target_port> of add-on <addon>, and only that flow is allowed through the
# Docker FORWARD chain. Everyone else keeps reaching whatever owns <port> on the
# host. The add-on IP is asked from the Supervisor on every pass, so a restart
# of the target add-on (new container IP) is followed automatically. All rules
# carry the comment "port_steer:<name>" and are removed on stop.
set -uo pipefail

OPT=/data/options.json
TAG=port_steer
INTERVAL=$(jq -r '.interval // 30' "$OPT")
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
    for spec in "nat PREROUTING" "filter DOCKER-USER"; do
        read -r table chain <<<"$spec"
        iptables -t "$table" -S "$chain" 2>/dev/null | grep -E -- "$re" | while read -r line; do
            line=${line//\"/}   # names have no spaces, quotes can go
            # shellcheck disable=SC2086  # the rule spec must split into words
            iptables -t "$table" ${line/-A /-D } \
                || log "WARNING: could not remove: $line"
        done
    done
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
declare -A STATE
log "Started: ${#RULES[@]} rule(s), check every ${INTERVAL} s"

while true; do
    for r in "${RULES[@]}"; do
        name=$(jq -r .name <<<"$r"); src=$(jq -r .source <<<"$r")
        port=$(jq -r .port <<<"$r"); addon=$(jq -r .addon <<<"$r")
        tport=$(jq -r .target_port <<<"$r")
        cip=$(addon_ip "$addon")
        c="${TAG}:${name}"
        if [[ -z $cip ]]; then
            if [[ ${STATE[$name]:-} != down ]]; then
                log "Rule $name: add-on $addon is not running - rule removed"
                drop_rules "$name"; STATE[$name]=down
            fi
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
    sleep "$INTERVAL" &
    wait $! || true
done
