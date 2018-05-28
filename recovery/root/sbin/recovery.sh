#!/sbin/sh

### Recovery service bootstrap for better Treble support
# Purpose:
#  - Prevent recovery from being restarted when it's killed (equivalent to a one-shot service)
#  - symlink to the correct fstab depending on Treble partition state
#

source /treble_manager/constants.sh

# check mount situation and use appropriate fstab
rm /etc/recovery.fstab
if [ -b "$vendor_a_blockdev" -a -b "$vendor_b_blockdev" ]; then
	ln -sn /etc/fstab.twrp.treble /etc/recovery.fstab
else
	ln -sn /etc/fstab.twrp.stock /etc/recovery.fstab
fi;

# replace system symlink with directory (can't do this in build shell for whatever reason)
if [ -L /system ]; then
	rm /system
	mkdir /system
fi

# fix for bootctl
ln -s /dev/block/mmcblk0 /dev/mmcblk0

# fix update_engine_sideload fstab
sed -i 's|/etc/recovery.fstab|/////////fstab.qcom|' /sbin/update_engine_sideload

# start recovery
/sbin/recovery &

# idle around
while kill -0 `pidof recovery`; do sleep 1; done

# stop self
stop recovery
