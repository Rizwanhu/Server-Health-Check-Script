#!/usr/bin/env bash
# health_check.sh - basic server health report (disk, memory, CPU load)
# Prints OK or WARN per check. Exit code: 0 = all OK, 1 = at least one WARN.
# Read-only: reads /proc and runs df. Needs no root, no network, no secrets.

set -u

# ---- Thresholds (override with environment variables) ----
DISK_WARN_PCT="${DISK_WARN_PCT:-80}"       # WARN if used disk % >= this
MEM_WARN_PCT="${MEM_WARN_PCT:-85}"         # WARN if used memory % >= this
LOAD_WARN_PER_CORE="${LOAD_WARN_PER_CORE:-0.80}"  # WARN if 1-min load / cores >= this
DISK_PATH="${DISK_PATH:-/}"                # filesystem to check

WARN_COUNT=0

report() {  # report <label> <status> <detail>
  printf '%-8s %-5s %s\n' "$1" "$2" "$3"
  [ "$2" = "WARN" ] && WARN_COUNT=$((WARN_COUNT + 1))
}

# ---- Disk ----
check_disk() {
  local used
  used=$(df -P "$DISK_PATH" 2>/dev/null | awk 'NR==2 {gsub("%","",$5); print $5}')
  if [ -z "$used" ]; then
    report "DISK" "WARN" "cannot read usage for $DISK_PATH"
    return
  fi
  local detail="$DISK_PATH at ${used}% used (warn >= ${DISK_WARN_PCT}%)"
  if [ "$used" -ge "$DISK_WARN_PCT" ]; then report "DISK" "WARN" "$detail"
  else report "DISK" "OK" "$detail"; fi
}

# ---- Memory (uses MemAvailable, so cache is not counted as used) ----
check_memory() {
  local total avail used_pct
  total=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
  avail=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
  if [ -z "$total" ] || [ -z "$avail" ] || [ "$total" -eq 0 ]; then
    report "MEMORY" "WARN" "cannot read /proc/meminfo"
    return
  fi
  used_pct=$(( (total - avail) * 100 / total ))
  local detail="${used_pct}% used, $((avail / 1024)) MB free of $((total / 1024)) MB (warn >= ${MEM_WARN_PCT}%)"
  if [ "$used_pct" -ge "$MEM_WARN_PCT" ]; then report "MEMORY" "WARN" "$detail"
  else report "MEMORY" "OK" "$detail"; fi
}

# ---- CPU load (1-minute load average divided by core count) ----
check_cpu() {
  local load1 cores per_core
  load1=$(awk '{print $1}' /proc/loadavg)
  cores=$(nproc 2>/dev/null || echo 1)
  per_core=$(awk -v l="$load1" -v c="$cores" 'BEGIN {printf "%.2f", l / c}')
  local detail="load ${load1} on ${cores} core(s) = ${per_core}/core (warn >= ${LOAD_WARN_PER_CORE})"
  if awk -v p="$per_core" -v t="$LOAD_WARN_PER_CORE" 'BEGIN {exit !(p >= t)}'; then
    report "CPU" "WARN" "$detail"
  else
    report "CPU" "OK" "$detail"
  fi
}

echo "== Server health: $(hostname) | $(date '+%Y-%m-%d %H:%M:%S %Z') =="
check_disk
check_memory
check_cpu

if [ "$WARN_COUNT" -eq 0 ]; then
  echo "RESULT: OK - all checks passed"
  exit 0
else
  echo "RESULT: WARN - ${WARN_COUNT} check(s) need attention"
  exit 1
fi
