#!/system/bin/sh
# FYT Improved Cold Start -- APEX prewarm (started by service.sh when PREWARM_APEX=1)
#
# The ~10 s freeze of the whole system at every boot is Android 10's ApexManager filling its APEX
# package cache on first use: it parses every APEX file and verifies its full signature, reading
# each file completely. The first use is a getInstallerPackageName() for a package that is not
# installed (FYT's carlink asks for com.txznet.smartadapter at ~24 s of uptime), and that call holds
# PackageManager's lock the whole time, so ActivityManager and WindowManager wait as well
# (system_server stack dumps, capture 29-09-2026 20:51).
#
# Listing the APEX packages as soon as PackageManager answers does the same work during the boot
# animation, before the launcher and the apps start; the later query then finds the cache filled.
# It changes nothing on disk.

# ---- settings -------------------------------------------------------------------------------
# Stop waiting for PackageManager at this uptime (s).
PREWARM_TIMEOUT_UPTIME=60
# ---------------------------------------------------------------------------------------------

MODDIR=${MODDIR:-${0%/*}}
LOGFILE=${LOGFILE:-$MODDIR/boot.log}
CMD=${CMD:-/system/bin/cmd}
LOGCMD=${LOGCMD:-/system/bin/log}
UPTIME_FILE=${UPTIME_FILE:-/proc/uptime}
SLEEP=${SLEEP:-sleep}

uptime_s() {
    cut -d. -f1 "$UPTIME_FILE"
}

# Uptime with hundredths, for the timing.
uptime_cs() {
    cut -d' ' -f1 "$UPTIME_FILE"
}

say() {
    echo "[$(uptime_s)s] $*" >> "$LOGFILE"
    "$LOGCMD" -p i -t FytColdStart "$*" 2>/dev/null
}

nap() {
    "$SLEEP" "$1" 2>/dev/null || "$SLEEP" 1
}

attempts=0
while :; do
    attempts=$((attempts + 1))
    started=$(uptime_cs)
    out=$("$CMD" package list packages --apex-only 2>&1)
    rc=$?
    case "$out" in
        *"Unknown option"*)
            say "apex prewarm: 'list packages --apex-only' not supported here: nothing done"
            exit 0
            ;;
        *"Can't find service"*)
            ;; # PackageManager not registered yet
        *)
            [ "$rc" -eq 0 ] && break
            ;;
    esac
    if [ "$(uptime_s)" -ge "$PREWARM_TIMEOUT_UPTIME" ]; then
        say "apex prewarm: PackageManager not answering by ${PREWARM_TIMEOUT_UPTIME}s: nothing done"
        exit 0
    fi
    nap 0.2
done
finished=$(uptime_cs)
count=$(printf '%s\n' "$out" | grep -c '^package:')
took=$(awk -v a="$started" -v b="$finished" 'BEGIN { printf "%.2f", b - a }')
say "apex prewarm: cache filled at ${started}s in ${took}s, ${count} APEX packages (attempt ${attempts})"
