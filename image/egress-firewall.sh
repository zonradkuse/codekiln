#!/usr/bin/env bash
# Default-deny egress firewall for the Claude Code dev container.
# Allows: loopback, DNS, and HTTPS (tcp/443) to the domains listed in
# /etc/codekiln/egress-allowlist.txt (baked into the image) and in
# /etc/codekiln/user/allowlist.txt (your own list, mounted read-only from the
# host; edit it there with `codekiln allow`). Everything else is rejected.
# Safe to re-run (refreshes resolved IPs and re-reads both lists):
#   sudo /usr/local/sbin/egress-firewall
set -Eeuo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

ALLOWLISTS=("/etc/codekiln/egress-allowlist.txt" "/etc/codekiln/user/allowlist.txt")
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
# Both families: a container with a global IPv6 address would otherwise stay
# reachable over IPv6.
fail_closed() {
  local restore
  for restore in iptables-restore ip6tables-restore; do
    "$restore" 2>/dev/null <<'RULES' || true
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT DROP [0:0]
-A INPUT -i lo -j ACCEPT
-A OUTPUT -o lo -j ACCEPT
COMMIT
RULES
  done
}
trap 'warn "setup failed at line $LINENO - blocking ALL traffic"; fail_closed; exit 1' ERR

is_ipv4_net() { [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ ]]; }
# Strict form for entries from the lists: octets 0-255 without leading zeros,
# prefix 1-32 (ipset rejects anything else, which would trip the fail-closed trap).
is_valid_net() {
  local o='(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])'
  [[ $1 =~ ^$o\.$o\.$o\.$o(/([1-9]|[12][0-9]|3[0-2]))?$ ]]
}
# Hostname syntax only (letters, digits, hyphens, dots); no wildcards, since
# the rules work on resolved addresses.
is_domain() { [[ $1 =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z][a-z0-9-]{0,61}[a-z0-9]$ ]]; }

# --- 1. Resolve the allowlists ------------------------------------------------
entries=()
want_github=0
for list in "${ALLOWLISTS[@]}"; do
  # The user list is optional: a container started from an older config has no
  # mount, and an empty or missing file just means "nothing extra".
  if [[ ! -e $list ]]; then
    if [[ $list == "${ALLOWLISTS[0]}" ]]; then warn "$list is missing"; fi
    continue
  fi
  # Actually open it: a mount can exist yet be unreadable (e.g. SELinux label),
  # and a failed read below would trip the fail-closed trap.
  if ! { : <"$list"; } 2>/dev/null; then
    warn "$list exists but cannot be read (SELinux label on the mount?) - skipped"
    continue
  fi
  log "reading $list"
  while IFS= read -r line || [[ -n $line ]]; do
    domain="${line%%#*}"
    domain="${domain//[[:space:]]/}"
    domain="${domain,,}"
    if [[ -z $domain ]]; then continue; fi

    if is_ipv4_net "$domain"; then
      if is_valid_net "$domain"; then
        entries+=("$domain")
        log "allow $domain"
      else
        warn "'$domain' is not a valid IPv4 address or network - skipped"
      fi
      continue
    fi
    if ! is_domain "$domain"; then
      warn "'$domain' is not a valid host name - skipped"
      continue
    fi
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
  done <"$list"
done

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

# A probe that resolves into the allowed set was allowed on purpose (e.g. via
# `codekiln allow`); testing it would only trip the fail-closed path.
probe_allowed() {
  local ip
  for ip in $(getent ahostsv4 "$1" | awk '{print $1}' | sort -u || true); do
    if ipset test "$SET" "$ip" 2>/dev/null; then return 0; fi
  done
  return 1
}

tested=()
for probe in "${BLOCKED_PROBES[@]}"; do
  if probe_allowed "$probe"; then
    log "self-test: skipping $probe (it is on the allowlist)"
    continue
  fi
  if reach "$probe"; then
    warn "$probe is reachable although it is not on the allowlist - rules are not effective"
    fail_closed
    exit 1
  fi
  tested+=("$probe")
done
if [[ ${#tested[@]} -gt 0 ]]; then log "self-test: ${tested[*]} blocked as expected"; fi

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
