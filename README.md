# FYT Improved Cold Start

A Magisk module for FYT head units running Android 10. It fixes two problems of every cold start:
the ~10 s freeze of the whole system, and apps having no internet for a long time although Wi-Fi is
connected.

## The problem: a 10 s freeze

About 24 s after power-on, just as the boot animation ends and the launcher and the apps start,
the unit stops responding for about 10 s. Touches are ignored, apps take that long to open, and the
launcher's list of apps arrives late. Often the audio drops as well: audioserver is killed
(`TimeCheck timeout for IAudioFlinger`) and needs another ~6 s to come back.

The cause is in Android 10 itself. Its `ApexManager` builds its cache of APEX packages lazily, on
the first query that needs it: it parses every APEX file and verifies its signature, reading each
file completely, and it does so while holding PackageManager's lock. On FYT units the first such
query is a `getInstallerPackageName()` for a package that is not installed: FYT's carlink app
(`com.syu.carlink`) asks for `com.txznet.smartadapter` about 24 s after power-on. With everything
else starting at that same moment, building the cache takes ~10 s. Meanwhile every call that needs
PackageManager waits for its lock, ActivityManager and WindowManager wait for it too, and all 31
binder threads of system_server fill up, so everything that calls into system_server stalls.

The audio drops are a consequence of the same freeze. A new audio stream opened in that window
(for example the Bluetooth hands-free link to the phone, set up at ~25 s) waits for system_server
as well. When that wait happens inside audioserver, its TimeCheck kills it after 5 s.

This was found with stack dumps of system_server taken during the freeze (see
[Diagnostics](#diagnostics)), which show the APEX scan holding PackageManager's lock, and with
boot logs in which every audio hang falls inside that window.

## The problem: no internet after a cold start

FYT units do not keep the time across a power loss. At a cold start Android sets the clock to the
ROM's build date (`Setting time of day to sec=1733543122`, 7 December 2024 on the development
unit), and the right time has to come from the network or from GPS. Until then every HTTPS
connection fails its certificate check (`Certificate not valid until … 2026 (compared to Sat Dec
07 … 2024)`): Wi-Fi shows as connected, Android's own connectivity check passes because it uses
plain HTTP, local connections such as `adb connect` work, but apps report no internet. Apps that
failed in that time often stay in their error state until they are restarted.

The network time does not help much here: Unisoc's time client (`SprdSntpClient`) only asks
`cn.ntp.org.cn`, servers in China, and in the development unit's logs it failed in 13 of 20 boots,
at home and over a phone's hotspot. In two boots in the car, HTTPS only started working when GPS had
a fix, 38 s and 50 s after Wi-Fi had connected; indoors, without a fix, it can take much longer.

## What the module does

**Freeze.** As soon as PackageManager answers (~16 s after power-on, during the boot animation), the module
lists the APEX packages once: `cmd package list packages --apex-only`. This read-only query fills
the cache in ~1.7 s, while nothing else is waiting for PackageManager. The query at ~24 s then gets
its answer from the cache at once.

**Clock.** If the clock is earlier than the ROM's build date plus two days, the module sets it as
soon as the network answers, from the `Date` header of a plain HTTP request
(`http://connectivitycheck.gstatic.com/generate_204`, then `http://www.google.com/generate_204` and
`http://cp.cloudflare.com/`) -- the kind of request Android's own connectivity check makes, so it
works wherever that check passes, also where NTP is blocked. It tries every 2 s, and stops as soon as
Android's network time or GPS has set the clock -- also when that happens during its own request, so
Android's more precise time is kept -- or after 10 minutes. Second-level accuracy is
plenty for certificates; Android refines the time later. When the clock is already right (a restart
without a power loss), it does nothing at all.

**Tip: a nearby NTP server.** Unisoc's time client takes its server from Android's `ntp_server`
setting when one is set. With

```
adb shell settings put global ntp_server pool.ntp.org
```

(or a country zone such as `pl.pool.ntp.org`), the development unit's own network time answered
0.6 s after the unit got its IP address, where `cn.ntp.org.cn` failed in most boots. The module does
not change this setting; its clock fix works either way, but with it Android's own time usually
comes first.

It is systemless: no file is replaced and no setting is changed, and outside its own folder it
writes nothing but a copy of its log. Besides the clock, which it only sets while it is clearly
wrong. Removing the module restores the stock behaviour on the next
boot.

## Results

Measured on the development unit (UMS512, Android 10) from its boot logs: six stock boots, and
three boots with this version, with a phone connecting over Bluetooth during each boot.

| | Stock | With the module |
|---|---|---|
| system_server's binder pool exhausted | 9.6–10.9 s, in every boot | never |
| Launcher's app query (`queryIntentActivities`) | 9.5–10.3 s, in 5 of 6 boots | 23–44 ms |
| audioserver killed by TimeCheck | in 4 of 6 boots | never |
| First Bluetooth hands-free audio stream | hangs ~10 s, or audioserver is killed | ready in 11–61 ms |
| APEX cache filled | at ~24 s, taking ~10 s | at 16.3–16.7 s, taking 1.7–1.9 s |
| Boot animation ends | 19.7–20.4 s | 21.9–22.6 s \* |

\* In the third boot it ended only at 38.5 s. Android's temporary home screen ends the boot
animation only if it is drawn before the user is unlocked, and this race is decided by a few
dozen milliseconds with or without the module. When it is lost, the next activity that becomes
idle ends the boot instead; the launcher used for testing started other apps at once, so that
took until Android's 10 s timeout.

The clock fix is newer: its behaviour is covered by the module's tests (the clock is set within
2 s of the network answering), but not measured on the unit yet. Without it, the same boot logs
show HTTPS failing for 38–50 s after Wi-Fi had connected in the car.

## Side effects

- **The boot animation lasts ~2 s longer.** The cache is filled during it, and PackageManager is
  busy for that time. The home screen then works right away instead of freezing.
- **A few small HTTP requests after a cold start** whose clock is wrong (one per attempt, until one
  answers). None when the clock is right.

## Compatibility

- Magisk v20.4 or newer. The clock fix uses Magisk's busybox (KernelSU's and APatch's are looked
  for too).
- FYT head units running Android 10. Developed on a UMS512 (UIS7862-class) unit.
- The module targets Android 10's lazy `ApexManager`. On other Android versions the listing is
  harmless, but most likely useless. Where `--apex-only` is not supported, the module only notes
  that in its log.

## Installation

1. Download the zip from the releases.
2. Magisk app → **Modules** → **Install from storage** → select the zip.
3. Reboot.

## Checking that it works

After a cold start, read the module's log:

- `/data/adb/modules/fyt_improved_cold_start/boot.log`
- a copy in `/sdcard/Download/fyt_improved_cold_start_boot.log`
- or `adb logcat -s FytColdStart` (the log is repeated there at 40 s of uptime)

A good boot looks like this:

```
[11s] started from service.sh (uptime 11s)
[11s] time sync: clock at 1970-01-01 00:00:11 UTC, before the ROM's build date: set as soon as the network answers
[18s] apex prewarm: cache filled at 16.48s in 1.74s, 7 APEX packages (attempt 22)
[29s] time sync: clock set to 2026-10-04 10:12:09 UTC from the Date header of http://connectivitycheck.gstatic.com/generate_204 (round 10)
```

After a restart without a power loss the clock is already right, and the time sync line reads
`time sync: clock fine (…): nothing to do`.

The freeze is gone when logcat no longer shows `binder thread pool (31 threads) starved` for
~10000 ms or `TimeCheck timeout for IAudioFlinger` during the boot, and carlink logs its
`Unknown package: com.txznet.smartadapter` within a second of its start instead of ~10 s later.

Other messages you may see:

| Message | Meaning |
|---|---|
| `'list packages --apex-only' not supported here: nothing done` | This Android version cannot list APEX packages this way |
| `PackageManager not answering by 60s: nothing done` | PackageManager did not come up within 60 s |
| `apex prewarm off (PREWARM_APEX=0)` | The pre-fill is switched off in the settings |
| `time sync: clock set meanwhile by Android (network time or GPS)` | Android was faster; the module left the clock alone |
| `time sync: no answer by 600s` | No network answered within 10 minutes |
| `time sync: ignored …: its date … is not plausible either` | A server sent a date before the ROM's build date; the next one is tried |
| `time sync: no busybox found` | No Magisk/KernelSU/APatch busybox: the clock fix cannot run |
| `time sync off (SYNC_TIME=0)` | The clock fix is switched off in the settings |

## Configuration

The settings are at the top of the scripts in `/data/adb/modules/fyt_improved_cold_start/`. Edit
them with a root file manager and reboot.

| Setting | File | Default | Meaning |
|---|---|---|---|
| `PREWARM_APEX` | `service.sh` | `1` | `0` switches the pre-fill off |
| `SYNC_TIME` | `service.sh` | `1` | `0` switches the clock fix off |
| `DIAG` | `service.sh` | `0` | `1` takes stack dumps of system_server during the boot (see below) |
| `COPY_DIR` | `service.sh` | `/sdcard/Download` | Where the copy of `boot.log` goes |
| `SUMMARY_UPTIME` | `service.sh` | `40` | Uptime (s) at which `boot.log` is repeated in logcat and copied |
| `PREWARM_TIMEOUT_UPTIME` | `apex_prewarm.sh` | `60` | Stop waiting for PackageManager at this uptime (s) |
| `TIME_URLS` | `time_sync.sh` | three `http://` URLs | Where the `Date` header is taken from, in this order |
| `RETRY_SECONDS` | `time_sync.sh` | `2` | Pause between attempts while the network does not answer |
| `GIVE_UP_UPTIME` | `time_sync.sh` | `600` | Stop trying at this uptime (s) |
| `WRONG_CLOCK_MARGIN` | `time_sync.sh` | `172800` | The clock counts as wrong while it is earlier than the build date plus this (s) |
| `DIAG_TIMES` | `diag.sh` | `26 29 32 36` | Uptimes (s) of the stack dumps |
| `DIAG_COPY_DIR` | `diag.sh` | `/sdcard/Download` | Where the dumps are copied |

## Diagnostics

If your unit still freezes during the boot, set `DIAG=1` and reboot. The module then saves Java
stack dumps of system_server at 26, 29, 32 and 36 s of uptime to `/sdcard/Download/diag_*.txt`. In
them, the threads that wait show which lock they wait for (`waiting to lock <…> held by thread N`),
and the holder's stack shows what it is doing. These dumps are how the cause above was found.

Each dump pauses system_server for a moment, like an ANR trace does, and slows the boot down.
Switch it back to `DIAG=0` when you are done.

## Removal

Magisk app → **Modules** → remove *FYT Improved Cold Start* → reboot.

If the unit does not boot properly and the Magisk app is out of reach, disable the module over
`adb` and reboot:

```
adb shell su -c "touch /data/adb/modules/fyt_improved_cold_start/disable"
```

## Files

| File | Purpose |
|---|---|
| `module.prop` | Module metadata |
| `customize.sh` | Installer messages and file permissions |
| `service.sh` | Starts the other scripts and writes the log |
| `apex_prewarm.sh` | Fills the APEX cache as soon as PackageManager answers |
| `time_sync.sh` | Sets the clock from the network when a cold start left it at the build date |
| `diag.sh` | Optional system_server stack dumps (`DIAG=1`) |

## Disclaimer

This software is provided "as is", without warranty of any kind, express or implied. It was built
and tested on one device only. It may not work on every ROM, head unit model or firmware version.
By installing it you accept full responsibility for any consequences.
