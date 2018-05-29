#!/sbin/sh

### Recovery service bootstrap for better Treble support
# Purpose:
#  - Prevent recovery from being restarted when it's killed (equivalent to a one-shot service)
#  - symlink to the correct fstab depending on Treble partition state
#

source /tissot_manager/constants.sh

# check mount situation and use appropriate fstab
rm /etc/twrp.flags
if [ -b "$vendor_a_blockdev" -a -b "$vendor_b_blockdev" ]; then
	ln -sn /etc/twrp.flags.treble /etc/twrp.flags
else
	ln -sn /etc/twrp.flags.stock /etc/twrp.flags
fi;

# insert our update_engine_sideload bootstrap
if [ -f /sbin/update_engine_sideload ]; then
	mv /sbin/update_engine_sideload /sbin/update_engine_sideload_real
	mv /sbin/update_engine_sideload.sh /sbin/update_engine_sideload
fi;

# replace system symlink with directory (can't do this in build shell for whatever reason)
if [ -L /system ]; then
	rm /system
	mkdir /system
fi

# Needed for boot control HAL to update GPT partition info
ln -s /dev/block/mmcblk0 /dev/mmcblk0

# start recovery
/sbin/recovery &

# idle around
while kill -0 `pidof recovery`; do sleep 1; done

# stop self
stop recovery
