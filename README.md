# Server Health Check

A single Bash script that reports basic server health on Linux: **disk, memory and CPU load**. Each check prints `OK` or `WARN`.
Read-only, no root, no network, no dependencies beyond standard tools (`bash`, `df`, `awk`, `nproc`). No secrets in this repo.

## Quick start

```bash
git clone <your-repo-url> && cd server-health-check
chmod +x health_check.sh
./health_check.sh
```

## Checks and default thresholds

| Check  | How it is measured                                   | WARN when        |
|--------|------------------------------------------------------|------------------|
| DISK   | `df -P` used % of `DISK_PATH` (default `/`)          | used >= 80%      |
| MEMORY | `(MemTotal - MemAvailable) / MemTotal` in `/proc/meminfo` | used >= 85% |
| CPU    | 1-minute load average from `/proc/loadavg` / core count | load per core >= 0.80 |

Why these numbers: 80% disk leaves time to react before it fills; 85% memory on `MemAvailable` (cache excluded) is real pressure; 0.80 load per core means the CPU is close to saturated without being a false alarm on short spikes.

## Change thresholds

Use environment variables (no code edits needed):

```bash
DISK_WARN_PCT=90 MEM_WARN_PCT=90 LOAD_WARN_PER_CORE=1.0 DISK_PATH=/var ./health_check.sh
```

Or copy `configs/health-check.env.example` to `health-check.env` and load it with `set -a; . ./health-check.env; set +a`.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | All checks OK |
| 1 | At least one WARN |

## Sample output

See `sample_output.txt` (OK run, forced WARN on disk + memory, real CPU-load WARN).

```
== Server health: vm | 2026-10-19 09:04:26 UTC ==
DISK     OK    / at 47% used (warn >= 80%)
MEMORY   OK    4% used, 3810 MB free of 3997 MB (warn >= 85%)
CPU      OK    load 0.00 on 1 core(s) = 0.00/core (warn >= 0.80)
RESULT: OK - all checks passed
```

## Runbook: what to do on WARN

| WARN | First checks | Typical fix |
|------|--------------|-------------|
| DISK | `df -h`, `du -xh / --max-depth=2 \| sort -h \| tail`, `journalctl --disk-usage` | Rotate/vacuum logs (`journalctl --vacuum-size=200M`), remove old packages/caches, extend volume |
| MEMORY | `free -h`, `ps aux --sort=-%mem \| head` | Restart the leaking service, add swap/RAM, tune the app |
| CPU | `uptime`, `top`/`htop`, `ps aux --sort=-%cpu \| head` | Find and fix the busy process, scale up cores, move batch jobs off-peak |

## Run on a schedule (optional)

See `configs/health-check.cron.example`: runs every 5 minutes and appends to `~/health_check.log`.
The script exit code can also drive monitoring (e.g. `./health_check.sh || echo "alert"`).

## Test it yourself

```bash
DISK_WARN_PCT=1 ./health_check.sh                       # forces a disk WARN
MEM_WARN_PCT=1 ./health_check.sh                        # forces a memory WARN
# create load, then check (stop with kill)
for i in $(seq "$(nproc)"); do (timeout 30 sh -c 'while :; do :; done' &) ; done
sleep 25; LOAD_WARN_PER_CORE=0.5 ./health_check.sh
```

## Files

```
health_check.sh                    the script
configs/health-check.env.example   threshold config (no secrets)
configs/health-check.cron.example  cron example
sample_output.txt                  captured test runs
```
