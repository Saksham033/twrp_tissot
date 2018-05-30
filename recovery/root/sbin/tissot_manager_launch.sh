#!/sbin/sh

# stop encryption service
stop sbinqseecomd

/tissot_manager/aroma 1 0 /tissot_manager/aroma_res.zip >/tmp/aroma_log.txt
cp -f /tissot_manager/aroma_res.zip.log.txt /sdcard1/tissot_manager.log
reboot recovery
