#!/system/bin/sh
# FYT Improved Cold Start -- diagnostics (started by service.sh when DIAG=1)
#
# If a unit still freezes during the boot, what system_server waits for is only visible in its own
# thread stacks: which thread holds a lock, and which ones wait for it. This script dumps them at a
# few moments; the default ones cover the time the freeze used to happen (24-36 s of uptime) plus
# one after it as a control. Each dump pauses system_server for a moment, like an ANR trace does.

# ---- settings -------------------------------------------------------------------------------
# Uptimes (s) for the dumps: three inside the usual freeze, one after it as a control.
DIAG_TIMES="26 29 32 36"
# Where copies go once shared storage is there.
DIAG_COPY_DIR=${DIAG_COPY_DIR:-/sdcard/Download}
# ---------------------------------------------------------------------------------------------

MODDIR=${MODDIR:-${0%/*}}
LOGFILE=${LOGFILE:-$MODDIR/boot.log}
DIAG_DIR=${DIAG_DIR:-$MODDIR/diag}
DEBUGGERD=${DEBUGGERD:-/system/bin/debuggerd}
LOGCMD=${LOGCMD:-/system/bin/log}
UPTIME_FILE=${UPTIME_FILE:-/proc/uptime}
SLEEP=${SLEEP:-sleep}
PIDOF=${PIDOF:-pidof}

uptime_s() {
    cut -d. -f1 "$UPTIME_FILE"
}

say() {
    echo "[$(uptime_s)s] diag: $*" >> "$LOGFILE"
    "$LOGCMD" -p i -t FytColdStart "diag: $*" 2>/dev/null
}

nap() {
    "$SLEEP" "$1" 2>/dev/null || "$SLEEP" 1
}

mkdir -p "$DIAG_DIR"
rm -f "$DIAG_DIR"/*.txt

for t in $DIAG_TIMES; do
    while [ "$(uptime_s)" -lt "$t" ]; do
        nap 0.2
    done
    pid=$("$PIDOF" system_server 2>/dev/null | awk '{ print $1 }')
    if [ -z "$pid" ]; then
        say "system_server not found at ${t}s"
        continue
    fi
    out="$DIAG_DIR/system_server_${t}s.txt"
    started=$(uptime_s)
    timeout 30 "$DEBUGGERD" -j "$pid" > "$out" 2>&1
    say "system_server stacks at ${started}s: $(wc -c < "$out") bytes, done at $(uptime_s)s"
done

# Copies next to the launcher's logs, so they can be taken with a file manager.
if mkdir -p "$DIAG_COPY_DIR" 2>/dev/null; then
    stamp=$(date +%d-%m-%Y_%H-%M-%S)
    for f in "$DIAG_DIR"/*.txt; do
        [ -f "$f" ] && cp "$f" "$DIAG_COPY_DIR/diag_${stamp}_${f##*/}"
    done
    cp "$LOGFILE" "$DIAG_COPY_DIR/diag_${stamp}_boot.log"
    say "copied to $DIAG_COPY_DIR (diag_${stamp}_*)"
else
    say "cannot write to $DIAG_COPY_DIR; the dumps stay in $DIAG_DIR"
fi
