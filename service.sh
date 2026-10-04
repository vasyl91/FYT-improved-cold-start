#!/system/bin/sh
# FYT Improved Cold Start -- service script (Magisk late_start service)
#
# Android 10 fills its cache of APEX packages the first time something needs it, and holds
# PackageManager's lock while doing so. On FYT units that first query comes at ~24 s of uptime,
# just when the launcher and the apps start, and system_server then freezes for ~10 s (see
# apex_prewarm.sh and README.md). This script has the cache filled earlier, during the boot
# animation. And when a cold start left the clock at the ROM's build date, it sets the clock as soon
# as the network answers, so HTTPS works (see time_sync.sh). It changes no file: removing the module
# restores the stock behaviour on the next boot.
#
# What happened is written to boot.log next to this script and to logcat (tag FytColdStart).

# ---- settings -------------------------------------------------------------------------------
# 1 = fill the APEX cache as soon as PackageManager answers (apex_prewarm.sh).
PREWARM_APEX=1
# 1 = set the clock from the network when a cold start left it at the ROM's build date (time_sync.sh).
SYNC_TIME=1
# 1 = also run diag.sh: stack dumps of system_server at a few moments of the boot (see diag.sh).
DIAG=0
# Where a copy of boot.log goes, once shared storage is there.
COPY_DIR=${COPY_DIR:-/sdcard/Download}
# Uptime (s) at which boot.log is repeated in logcat and copied to COPY_DIR: by then shared
# storage is mounted, and apps that capture logcat at boot are running.
SUMMARY_UPTIME=40
# ---------------------------------------------------------------------------------------------

MODDIR=${0%/*}
LOGFILE=${LOGFILE:-$MODDIR/boot.log}
LOGCMD=${LOGCMD:-/system/bin/log}
UPTIME_FILE=${UPTIME_FILE:-/proc/uptime}
SLEEP=${SLEEP:-sleep}

uptime_s() {
    cut -d. -f1 "$UPTIME_FILE"
}

say() {
    echo "[$(uptime_s)s] $*" >> "$LOGFILE"
    "$LOGCMD" -p i -t FytColdStart "$*" 2>/dev/null
}

nap() {
    "$SLEEP" "$1" 2>/dev/null || "$SLEEP" 1
}

: > "$LOGFILE"
say "started from ${0##*/} (uptime $(uptime_s)s)"

if [ "$PREWARM_APEX" = 1 ] && [ -f "$MODDIR/apex_prewarm.sh" ]; then
    sh "$MODDIR/apex_prewarm.sh" &
else
    say "apex prewarm off (PREWARM_APEX=$PREWARM_APEX)"
fi
if [ "$SYNC_TIME" = 1 ] && [ -f "$MODDIR/time_sync.sh" ]; then
    sh "$MODDIR/time_sync.sh" &
else
    say "time sync off (SYNC_TIME=$SYNC_TIME)"
fi
if [ "$DIAG" = 1 ] && [ -f "$MODDIR/diag.sh" ]; then
    sh "$MODDIR/diag.sh" &
fi

# boot.log once more in logcat, for logs captured after the boot, and a copy in COPY_DIR.
while [ "$(uptime_s)" -lt "$SUMMARY_UPTIME" ]; do
    nap 1
done
while IFS= read -r line; do
    "$LOGCMD" -p i -t FytColdStart "summary: $line" 2>/dev/null
done < "$LOGFILE"
mkdir -p "$COPY_DIR" 2>/dev/null
cp "$LOGFILE" "$COPY_DIR/fyt_improved_cold_start_boot.log" 2>/dev/null
