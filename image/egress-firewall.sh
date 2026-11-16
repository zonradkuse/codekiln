#!/usr/bin/env bash
# Default-deny egress firewall for the Claude Code dev container.
# Allows: loopback, DNS, and HTTPS (tcp/443) to the domains listed in
# /etc/codekiln/egress-allowlist.txt. Everything else is rejected.
# Safe to re-run (refreshes resolved IPs): sudo /usr/local/sbin/egress-firewall
set -Eeuo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

ALLOWLIST="/etc/codekiln/egress-allowlist.txt"
SET="egress-allow"
TMPSET="egress-allow-next"
# Hosts that must NOT be reachable once the rules are in place (self-test).
BLOCKED_PROBES=("1.1.1.1" "www.wikipedia.org")

log()  { echo "[firewall] $*"; }
warn() { echo "[firewall] WARNING: $*" >&2; }

if [[ $EUID -ne 0 ]]; then
  echo "egress-firewall must run as root (use sudo)" >&2
  exit 1
fi

# If anything goes wrong, block everything rather than leave the network open.
fail_closed() {
  iptables-restore <<'RULES' || true
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT DROP [0:0]
-A INPUT -i lo -j ACCEPT
-A OUTPUT -o lo -j ACCEPT
COMMIT
RULES
}
trap 'warn "setup failed at line $LINENO - blocking ALL traffic"; fail_closed; exit 1' ERR

is_ipv4_net() { [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ ]]; }

# --- 1. Resolve the allowlist -------------------------------------------------
entries=()
want_github=0
while IFS= read -r line || [[ -n $line ]]; do
  domain="${line%%#*}"
  domain="${domain//[[:space:]]/}"
  if [[ -z $domain ]]; then continue; fi
  if [[ $domain == "github.com" ]]; then want_github=1; fi

  ips="$(getent ahostsv4 "$domain" | awk '{print $1}' | sort -u || true)"
  if [[ -z $ips ]]; then
    warn "could not resolve $domain - skipped"
    continue
  fi
  while IFS= read -r ip; do
    if is_ipv4_net "$ip"; then entries+=("$ip"); fi
  done <<<"$ips"
  log "allow $domain -> $(tr '\n' ' ' <<<"$ips")"
done <"$ALLOWLIST"

# GitHub serves from large, rotating ranges; use the published list.
if [[ $want_github -eq 1 ]]; then
  if meta="$(curl -fsS --connect-timeout 5 --max-time 20 https://api.github.com/meta)" \
     && ranges="$(jq -r '(.web + .api + .git)[]' <<<"$meta")" \
     && [[ -n $ranges ]]; then
    n=0
    while IFS= read -r r; do
      if is_ipv4_net "$r"; then entries+=("$r"); n=$((n + 1)); fi
    done <<<"$ranges"
    log "allow github.com -> $n published ranges (web/api/git)"
  else
    warn "could not fetch api.github.com/meta - github.com limited to its current DNS result"
  fi
fi

if [[ ${#entries[@]} -eq 0 ]]; then
  warn "nothing on the allowlist could be resolved - all outbound traffic will be blocked"
fi

# --- 2. Load IPs into an ipset (built aside, then swapped in atomically) ------
{
  echo "create $TMPSET hash:net family inet"
  echo "flush $TMPSET"
  for e in ${entries[@]+"${entries[@]}"}; do
    echo "add $TMPSET $e"
  done
} | ipset -exist restore
ipset -exist create "$SET" hash:net family inet
ipset swap "$TMPSET" "$SET"
ipset destroy "$TMPSET"

# --- 3. DNS: only to the configured resolvers where possible ------------------
mapfile -t nameservers < <(awk '$1=="nameserver" && $2 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {print $2}' /etc/resolv.conf)
restrict_dns=1
if [[ ${#nameservers[@]} -eq 0 ]]; then restrict_dns=0; fi
for ns in ${nameservers[@]+"${nameservers[@]}"}; do
  # Docker's embedded resolver (127.0.0.11) forwards upstream from inside this
  # network namespace, so the upstream addresses aren't known here.
  if [[ $ns == 127.* ]]; then restrict_dns=0; fi
done

dns_rules=""
if [[ $restrict_dns -eq 1 ]]; then
  for ns in "${nameservers[@]}"; do
    dns_rules+="-A OUTPUT -d $ns -p udp --dport 53 -j ACCEPT"$'\n'
    dns_rules+="-A OUTPUT -d $ns -p tcp --dport 53 -j ACCEPT"$'\n'
  done
  log "DNS restricted to: ${nameservers[*]}"
else
  dns_rules+="-A OUTPUT -p udp --dport 53 -j ACCEPT"$'\n'
  dns_rules+="-A OUTPUT -p tcp --dport 53 -j ACCEPT"$'\n'
  warn "DNS (port 53) allowed to any destination (embedded/unknown resolver)"
fi

# --- 4. Apply the IPv4 filter table atomically (nat table is left untouched) --
iptables-restore <<RULES
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT DROP [0:0]
-A INPUT -i lo -j ACCEPT
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
-A OUTPUT -o lo -j ACCEPT
-A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
${dns_rules}-A OUTPUT -p tcp --dport 443 -m set --match-set $SET dst -j ACCEPT
-A OUTPUT -p tcp -j REJECT --reject-with tcp-reset
-A OUTPUT -j REJECT
COMMIT
RULES

# --- 5. IPv6: block entirely --------------------------------------------------
if command -v ip6tables-restore >/dev/null && ip6tables-restore 2>/dev/null <<'RULES'
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT DROP [0:0]
-A INPUT -i lo -j ACCEPT
-A OUTPUT -o lo -j ACCEPT
-A OUTPUT -j REJECT
COMMIT
RULES
then
  log "IPv6 blocked"
elif [[ -r /proc/net/if_inet6 ]] && awk '$4=="00"{found=1} END{exit !found}' /proc/net/if_inet6; then
  warn "container has a global IPv6 address but ip6tables is unusable - IPv6 is NOT filtered"
  fail_closed
  exit 1
else
  log "IPv6 not routable in this container (nothing to block)"
fi

# --- 6. Verify ----------------------------------------------------------------
reach() { curl -s -o /dev/null --connect-timeout 5 --max-time 10 "https://$1"; }

for probe in "${BLOCKED_PROBES[@]}"; do
  if reach "$probe"; then
    warn "$probe is reachable although it is not on the allowlist - rules are not effective"
    fail_closed
    exit 1
  fi
done
log "self-test: ${BLOCKED_PROBES[*]} blocked as expected"

if reach api.anthropic.com; then
  log "self-test: api.anthropic.com reachable"
else
  warn "api.anthropic.com is NOT reachable - Claude Code will not work"
fi
if [[ $want_github -eq 1 ]]; then
  if reach github.com; then
    log "self-test: github.com reachable"
  else
    warn "github.com is NOT reachable"
  fi
fi

log "done: ${#entries[@]} allowlist entries active"
