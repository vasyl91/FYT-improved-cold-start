# Runs in the Magisk installer.
ui_print "- FYT Improved Cold Start v1"
ui_print "  Fills Android's APEX package cache as soon as"
ui_print "  PackageManager is up, during the boot animation,"
ui_print "  instead of under PackageManager's lock at ~24 s,"
ui_print "  which froze the system for ~10 s after every"
ui_print "  cold start."
ui_print "  Sets the clock from the network when a cold start"
ui_print "  left it at the ROM's build date, so HTTPS works"
ui_print "  right after Wi-Fi connects."
ui_print "  Changes no system file; remove the module to undo."
ui_print "  May not work on every ROM - use at your own risk."
ui_print "  Log after a reboot:"
ui_print "  /data/adb/modules/fyt_improved_cold_start/boot.log"
ui_print "  (copy in Download/, logcat tag FytColdStart)"
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/apex_prewarm.sh" 0 0 0755
set_perm "$MODPATH/diag.sh" 0 0 0755
set_perm "$MODPATH/time_sync.sh" 0 0 0755
