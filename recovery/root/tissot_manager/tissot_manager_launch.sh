#!/sbin/sh
### tissot manager launcher

# only source it, we set our own OUT_FD
source /tissot_manager/tools.sh

OUT_FD=/proc/$$/fd/$2

ui_print "[#] Starting Tissot Manager..."

pauseTwrp

# stop encryption service
stop sbinqseecomd

/tissot_manager/aroma 1 $2 /tissot_manager/tissot_manager.zip >/tmp/tissot_manager.log
if [ -f "/tissot_manager/tissot_manager.zip.log.txt" ]; then
	cp -f "/tissot_manager/tissot_manager.zip.log.txt" "/sdcard1/tissot_manager.log"
fi

if [ -f "/tmp/do_reboot_recovery" ]; then
	reboot recovery
fi

# restart encryption
start sbinqseecomd

resumeTwrp

