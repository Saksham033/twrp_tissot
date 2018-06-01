#!/sbin/sh

# stop encryption service
stop sbinqseecomd

/tissot_manager/aroma 1 0 /tissot_manager/tissot_manager.zip >/tmp/tissot_manager.txt
cp -f /tissot_manager/tissot_manager.zip.log.txt /sdcard1/tissot_manager.log
reboot recovery
