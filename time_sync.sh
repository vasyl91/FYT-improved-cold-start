#!/system/bin/sh
# FYT Improved Cold Start -- clock fix (started by service.sh when SYNC_TIME=1)
#
# FYT units do not keep the time across a power loss: at a cold start Android sets the clock to the
# ROM's build date (07-12-2024 on the development unit). The right time then comes from Unisoc's
# network time client, which only asks cn.ntp.org.cn in China and failed in most boots, or from a
# GPS fix. Until then every HTTPS connection fails its certificate check ("Certificate not valid
# until ... (compared to Sat Dec 07 ... 2024)"): Wi-Fi shows as connected, but apps have no
# internet -- for 40-50 s after connecting in a car, and for good without a GPS fix.
#
# This script sets the clock from the Date header of a plain HTTP request, the kind Android's own
# connectivity check makes, as soon as the network answers, and only while the clock is clearly
# wrong. Second-level accuracy is plenty for certificates; Android's network time or GPS refines it.

# ---- settings -------------------------------------------------------------------------------
# Plain-HTTP URLs whose responses carry a Date header, tried in this order.
TIME_URLS="http://connectivitycheck.gstatic.com/generate_204 http://www.google.com/generate_204 http://cp.cloudflare.com/"
# Seconds between rounds while the network does not answer yet.
RETRY_SECONDS=2
# Give up at this uptime (s).
GIVE_UP_UPTIME=600
# The clock counts as wrong while it is earlier than the ROM's build date plus this many seconds.
WRONG_CLOCK_MARGIN=172800
# ---------------------------------------------------------------------------------------------

MODDIR=${MODDIR:-${0%/*}}
LOGFILE=${LOGFILE:-$MODDIR/boot.log}
LOGCMD=${LOGCMD:-/system/bin/log}
UPTIME_FILE=${UPTIME_FILE:-/proc/uptime}
SLEEP=${SLEEP:-sleep}
GETPROP=${GETPROP:-getprop}
COPY_DIR=${COPY_DIR:-/sdcard/Download}
# Magisk's busybox (KernelSU and APatch keep theirs elsewhere).
if [ -z "$BUSYBOX" ]; then
    for b in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox; do
        [ -x "$b" ] && { BUSYBOX=$b; break; }
    done
    [ -z "$BUSYBOX" ] && BUSYBOX=$(command -v busybox)
fi

uptime_s() {
    cut -d. -f1 "$UPTIME_FILE"
}

say() {
    echo "[$(uptime_s)s] time sync: $*" >> "$LOGFILE"
    "$LOGCMD" -p i -t FytColdStart "time sync: $*" 2>/dev/null
}

nap() {
    "$SLEEP" "$1" 2>/dev/null || "$SLEEP" 1
}

# service.sh copies boot.log at 40 s; a result that comes later is copied again.
copy_log() {
    mkdir -p "$COPY_DIR" 2>/dev/null
    cp "$LOGFILE" "$COPY_DIR/fyt_improved_cold_start_boot.log" 2>/dev/null
}

if [ -z "$BUSYBOX" ] || [ ! -x "$BUSYBOX" ]; then
    say "no busybox found: nothing done"
    exit 0
fi

now() {
    "$BUSYBOX" date -u +%s
}

utc() {
    "$BUSYBOX" date -u -d "@$1" '+%Y-%m-%d %H:%M:%S UTC'
}

# Android advances a clock that is earlier than the build date to the build date at boot.
build=$("$GETPROP" ro.build.date.utc)
case "$build" in
    '' | *[!0-9]*) build=1735689600 ;; # unknown: 2025-01-01
esac
valid_after=$((build + WRONG_CLOCK_MARGIN))

t=$(now)
if [ "$t" -ge "$valid_after" ]; then
    say "clock fine ($(utc "$t")): nothing to do"
    exit 0
fi
say "clock at $(utc "$t"), before the ROM's build date: set as soon as the network answers"

round=0
while [ "$(uptime_s)" -lt "$GIVE_UP_UPTIME" ]; do
    round=$((round + 1))
    t=$(now)
    if [ "$t" -ge "$valid_after" ]; then
        say "clock set meanwhile by Android (network time or GPS): $(utc "$t")"
        copy_log
        exit 0
    fi
    for url in $TIME_URLS; do
        stamp=$("$BUSYBOX" timeout 8 "$BUSYBOX" wget -S -q -O /dev/null -T 5 "$url" 2>&1 |
            sed -n 's/^ *[Dd]ate: *\([A-Za-z]*, [0-9]* [A-Za-z]* [0-9]* [0-9:]*\) GMT.*$/\1/p' | head -n 1)
        [ -n "$stamp" ] || continue
        epoch=$("$BUSYBOX" date -u -D '%a, %d %b %Y %H:%M:%S' -d "$stamp" +%s 2>/dev/null)
        case "$epoch" in
            '' | *[!0-9]*) continue ;;
        esac
        if [ "$epoch" -lt "$valid_after" ]; then
            say "ignored $url: its date ($stamp GMT) is not plausible either"
            continue
        fi
        # Android may have set the clock while the request was under way: its network time
        # answered 0.3 s earlier in a capture of 04-10-2026, and is the more precise one.
        t=$(now)
        if [ "$t" -ge "$valid_after" ]; then
            say "clock set meanwhile by Android (network time or GPS): $(utc "$t")"
            copy_log
            exit 0
        fi
        if "$BUSYBOX" date -u -s "@$epoch" > /dev/null 2>&1; then
            say "clock set to $(utc "$epoch") from the Date header of $url (round $round)"
        else
            say "could not set the clock to $(utc "$epoch")"
        fi
        copy_log
        exit 0
    done
    nap "$RETRY_SECONDS"
done
say "no answer by ${GIVE_UP_UPTIME}s: clock left at $(utc "$(now)")"
copy_log
