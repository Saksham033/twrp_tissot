#!/sbin/sh
# Tissot Manager install script by CosmicDan
# Parts based on AnyKernel2 Backend by osm0sis
#

# This script is called by Aroma installer via update-binary-installer

######
# INTERNAL FUNCTIONS

OUTFD=/proc/self/fd/$2;
ZIP="$3";
DIR=`dirname "$ZIP"`;

ui_print() {
    until [ ! "$1" ]; do
        echo -e "ui_print $1\nui_print" > $OUTFD;
        shift;
    done;
}

show_progress() { echo "progress $1 $2" > $OUTFD; }
set_progress() { echo "set_progress $1" > $OUTFD; }

file_getprop() { grep "^$2" "$1" | cut -d= -f2; }
getprop() { test -e /sbin/getprop && /sbin/getprop $1 || file_getprop /default.prop $1; }
abort() { ui_print "$*"; umount /system; umount /data; exit 1; }

######

source /tissot_manager/constants.sh
source /tissot_manager/tools.sh

if [ -f "/tmp/doadb" ]; then
	rm /tmp/doadb
	ui_print "[#] Mounting /system..."
	targetSlot=`getCurrentSlotLetter`
	mount "/dev/block/bootdevice/by-name/system_$targetSlot" /system > /dev/null 2>&1
	if isTreble; then
		ui_print "[#] Mounting /vendor..."
		mount "/dev/block/bootdevice/by-name/vendor_$targetSlot" /vendor > /dev/null 2>&1
	fi
	
	ui_print "[#] Searching all props and adjusting for insecure ADB on boot..."
	# loop over all prop files on /system (and /vendor since it's symlinked at /system/system/vendor) and change adb-related options
	for f in $(find -L /system -iname \*.prop); do 
		#sed -i 's|ro.secure=.*|ro.secure=0|' "$f"
		sed -i 's|ro.adb.secure=.*|ro.adb.secure=0|' "$f"
		sed -i 's|ro.debuggable=.*|ro.debuggable=1|' "$f"
		#sed -i 's|persist.sys.usb.config=.*|persist.sys.usb.config=adb|' "$f"
	done
	
	ui_print "[#] Adding god-mode ADBD binary to /system..."
	# replace every occurance of adbd on /system (and /vendor since it's symlinked at /system/system/vendor) with recovery version. The path of adbd varies per ROM so this ensures it will work.
	for f in $(find /system -iname adbd); do
		cp -a "/sbin/adbd" "$f"
		chmod 750 "$f"
		chown root:shell "$f"
	done
	
	umount -f /system > /dev/null 2>&1
	if isTreble; then
		umount -f /vendor > /dev/null 2>&1
	fi
	
	ui_print "[i] Done!"
	
	exit 0
fi


ui_print " ";
ui_print "[#] Unmounting all eMMC partitions..."
# This qseecomd jerk sometimes refuses to die, keeping mmcblk0 locked
stop sbinqseecomd
sleep 2
kill `pidof qseecomd`
mount | grep /dev/block/mmcblk0p | while read -r line ; do
	thispart=`echo "$line" | awk '{ print $3 }'`
	umount -f $thispart
	sleep 0.5
done
mount | grep /dev/block/bootdevice/ | while read -r line ; do
	thispart=`echo "$line" | awk '{ print $3 }'`
	umount -f $thispart
	sleep 0.5
done
sleep 2
blockdev --rereadpt /dev/block/mmcblk0

partition_status=`cat /tmp/partition_status`
if [ ! $partition_status -ge 0 ]; then
	ui_print "[!] Error - partition status unknown! Was /tmp wiped? Aborting..."
	exit 1
fi

choice=`file_getprop /tmp/aroma/choice_repartition.prop root`
if [ "$choice" == "stock" ]; then
	ui_print "[i] Starting repartition back to stock..."
	ui_print "[#] Deleting vendor_a..."
	sgdisk /dev/block/mmcblk0 --delete $vendor_a_partnum
	ui_print "[#] Deleting vendor_b..."
	sgdisk /dev/block/mmcblk0 --delete $vendor_b_partnum
	sleep 1
	blockdev --rereadpt /dev/block/mmcblk0
	sleep 0.5
	if [ "$partition_status" == "2" ]; then
		# system is shrunk
		ui_print "[#] Growing system_a..."
		sgdisk /dev/block/mmcblk0 --delete $system_a_partnum
		sgdisk /dev/block/mmcblk0 --new=$system_a_partnum:$system_a_partstart:$system_a_stock_partend
		sgdisk /dev/block/mmcblk0 --change-name=$system_a_partnum:system_a
		ui_print "[#] Growing system_b..."
		sgdisk /dev/block/mmcblk0 --delete $system_b_partnum
		sgdisk /dev/block/mmcblk0 --new=$system_b_partnum:$system_b_partstart:$system_b_stock_partend
		sgdisk /dev/block/mmcblk0 --change-name=$system_b_partnum:system_b
		ui_print "[#] Formatting system_a and system_b..."
		sleep 2
		blockdev --rereadpt /dev/block/mmcblk0
		sleep 1
		make_ext4fs /dev/block/mmcblk0p$system_a_partnum
		make_ext4fs /dev/block/mmcblk0p$system_b_partnum
	else
		# userdata is shrunk or split
		if [ "$partition_status" == "4" ]; then
			# dualboot userdata
			userdata_partline=`sgdisk --print /dev/block/mmcblk0 | grep -i userdata_a`
		else
			userdata_partline=`sgdisk --print /dev/block/mmcblk0 | grep -i userdata`
		fi
		userdata_partnum_current=$(echo "$userdata_partline" | awk '{ print $1 }')
		userdata_partstart_current=$(echo "$userdata_partline" | awk '{ print $2 }')
		userdata_partend_current=$(echo "$userdata_partline" | awk '{ print $3 }')
		#userdata_partname=$(echo "$userdata_partline" | awk '{ print $7 }')
		if [ "$partition_status" == "4" ]; then
			userdata_b_partline=`sgdisk --print /dev/block/mmcblk0 | grep -i userdata_b`
			userdata_b_partnum_current=$(echo "$userdata_b_partline" | awk '{ print $1 }')
			userdata_b_partstart_current=$(echo "$userdata_b_partline" | awk '{ print $2 }')
			userdata_b_partend_current=$(echo "$userdata_b_partline" | awk '{ print $3 }')
			#userdata_b_partname=$(echo "$userdata_b_partline" | awk '{ print $7 }')
		fi
		# safety check
		if [ "$userdata_partnum_current" == "$userdata_partnum" -a "$userdata_partstart_current" == "$userdata_treble_partstart" ]; then
			if [ "$partition_status" == "4" ]; then
				ui_print "[#] Deleting userdata_b..."
				sgdisk /dev/block/mmcblk0 --delete $userdata_b_partnum_current
				sleep 2
				blockdev --rereadpt /dev/block/mmcblk0
				sleep 1
			fi
			ui_print "[#] Growing userdata..."
			sgdisk /dev/block/mmcblk0 --delete $userdata_partnum
			if [ "$partition_status" == "4" ]; then
				sgdisk /dev/block/mmcblk0 --new=$userdata_partnum:$userdata_stock_partstart:$userdata_b_partend_current
			else
				sgdisk /dev/block/mmcblk0 --new=$userdata_partnum:$userdata_stock_partstart:$userdata_partend_current
			fi
			sgdisk /dev/block/mmcblk0 --change-name=$userdata_partnum:userdata
			ui_print "[#] Formatting userdata..."
			sleep 2
			blockdev --rereadpt /dev/block/mmcblk0
			sleep 1
			# Calculate the length of userdata for make_ext4fs minus 16KB (for the encryption footer reservation)
			userdata_new_partlength_sectors=`echo $((userdata_partend_current-userdata_stock_partstart))`
			if [ "$partition_status" == "4" ]; then
				# we want the userdata_b end sector instead
				userdata_new_partlength_sectors=`echo $((userdata_b_partend_current-userdata_stock_partstart))`
			fi
			userdata_new_partlength_bytes=`echo $((userdata_new_partlength_sectors*512))`
			userdata_new_ext4size=`echo $((userdata_new_partlength_bytes-16384))`
			make_ext4fs -a /data -l $userdata_new_ext4size /dev/block/mmcblk0p$userdata_partnum_current
		else
			ui_print "[!] Could not verify Userdata partition info. Resizing Userdata aborted."
		fi;
	fi;
	ui_print " "
	ui_print "[i] All done!"
	ui_print " "
	ui_print "[i] You are now ready to install a non-Treble ROM or restore from a ROM backup."
elif [ "$choice" == "treble_userdata" ]; then
	ui_print "[i] Starting Treble repartition by shrinking Userdata..."
	# get Userdata info
	userdata_partline=`sgdisk --print /dev/block/mmcblk0 | grep -i userdata`
	userdata_partnum_current=$(echo "$userdata_partline" | awk '{ print $1 }')
	userdata_partstart_current=$(echo "$userdata_partline" | awk '{ print $2 }')
	userdata_partend_current=$(echo "$userdata_partline" | awk '{ print $3 }')
	#userdata_partname=$(echo "$userdata_partline" | awk '{ print $7 }')
	dualboot_option=`file_getprop /tmp/aroma/choice_dualboot.prop root`
	if [ "$dualboot_option" == "none" ]; then
		ui_print "[#] Shrinking userdata..."
		sgdisk /dev/block/mmcblk0 --delete $userdata_partnum_current
		sgdisk /dev/block/mmcblk0 --new=$userdata_partnum_current:$userdata_treble_partstart:$userdata_partend_current
		sgdisk /dev/block/mmcblk0 --change-name=$userdata_partnum_current:userdata
	else
		ui_print "[#] Shrinking and splitting userdata with $dualboot_option Slot B size..."
		# instead of using pre-defined values, we calculate the userdata_a end and userdata_b start boundary dynamically
		userdata_a_length=`/tissot_manager/tools.sh userdata_calc "$dualboot_option" "as_sectors"`
		userdata_a_partstart=$userdata_treble_partstart
		userdata_a_partend=`echo $(($userdata_treble_partstart+userdata_a_length-2))`
		userdata_b_partstart=`echo $((userdata_a_partend+4))`
		userdata_b_partend=$userdata_partend_current
		sgdisk /dev/block/mmcblk0 --delete $userdata_partnum_current
		sgdisk /dev/block/mmcblk0 --new=$userdata_partnum:$userdata_a_partstart:$userdata_a_partend
		sgdisk /dev/block/mmcblk0 --change-name=$userdata_partnum:userdata_a
		sgdisk /dev/block/mmcblk0 --new=$userdata_b_partnum:$userdata_b_partstart:$userdata_b_partend
		sgdisk /dev/block/mmcblk0 --change-name=$userdata_b_partnum:userdata_b
	fi
	ui_print "[#] Creating vendor_a..."
	sgdisk /dev/block/mmcblk0 --new=$vendor_a_partnum:$vendor_a_partstart_userdata:$vendor_a_partend_userdata
	sgdisk /dev/block/mmcblk0 --change-name=$vendor_a_partnum:vendor_a
	ui_print "[#] Creating vendor_b..."
	sgdisk /dev/block/mmcblk0 --new=$vendor_b_partnum:$vendor_b_partstart_userdata:$vendor_b_partend_userdata
	sgdisk /dev/block/mmcblk0 --change-name=$vendor_b_partnum:vendor_b
	sleep 2
	blockdev --rereadpt /dev/block/mmcblk0
	sleep 1
	# Calculate the length of userdata for make_ext4fs minus 16KB (for the encryption footer reservation)
	if [ "$dualboot_option" == "none" ]; then
		ui_print "[#] Formatting userdata..."
		userdata_new_partlength_sectors=`echo $((userdata_partend_current-userdata_treble_partstart))`
		userdata_new_partlength_bytes=`echo $((userdata_new_partlength_sectors*512))`
		userdata_new_ext4size=`echo $((userdata_new_partlength_bytes-16384))`
		make_ext4fs -a /data -l $userdata_new_ext4size /dev/block/mmcblk0p$userdata_partnum_current
	else
		ui_print "[#] Formatting userdata_a..."
		userdata_a_new_partlength_sectors=`echo $((userdata_a_partend-userdata_a_partstart))`
		userdata_a_new_partlength_bytes=`echo $((userdata_a_new_partlength_sectors*512))`
		userdata_a_new_ext4size=`echo $((userdata_a_new_partlength_bytes-16384))`
		make_ext4fs -a /data -l $userdata_a_new_ext4size /dev/block/mmcblk0p$userdata_partnum
		ui_print "[#] Formatting userdata_b..."
		userdata_b_new_partlength_sectors=`echo $((userdata_b_partend-userdata_b_partstart))`
		userdata_b_new_partlength_bytes=`echo $((userdata_b_new_partlength_sectors*512))`
		userdata_b_new_ext4size=`echo $((userdata_b_new_partlength_bytes-16384))`
		make_ext4fs -a /data -l $userdata_b_new_ext4size /dev/block/mmcblk0p$userdata_b_partnum
	fi
	ui_print "[#] Formatting vendor_a and vendor_b..."
	sleep 2
	make_ext4fs /dev/block/mmcblk0p$vendor_a_partnum
	make_ext4fs /dev/block/mmcblk0p$vendor_b_partnum
	ui_print " "
	ui_print "[i] All done!"
	ui_print " "
	ui_print "[i] You are now ready to install a any ROM (non-Treble or Treble) and/or Vendor pack."
	if [ "$dualboot_option" != "none" ]; then
		ui_print " "
		ui_print "[i] Remember that you now have userdata_a and userdata_b for dualboot. All storage and userdata operations in TWRP and Android will be specific to the current slot."
	fi
elif [ "$choice" == "treble_system" ]; then
	ui_print "[i] Starting Treble repartition by shrinking System..."
	ui_print "[#] Shrinking system_a..."
	sgdisk /dev/block/mmcblk0 --delete $system_a_partnum
	sgdisk /dev/block/mmcblk0 --new=$system_a_partnum:$system_a_partstart:$system_a_treble_partend
	sgdisk /dev/block/mmcblk0 --change-name=$system_a_partnum:system_a
	ui_print "[#] Shrinking system_b..."
	sgdisk /dev/block/mmcblk0 --delete $system_b_partnum
	sgdisk /dev/block/mmcblk0 --new=$system_b_partnum:$system_b_partstart:$system_b_treble_partend
	sgdisk /dev/block/mmcblk0 --change-name=$system_b_partnum:system_b
	ui_print "[#] Creating vendor_a..."
	sgdisk /dev/block/mmcblk0 --new=$vendor_a_partnum:$vendor_a_partstart_system:$vendor_a_partend_system
	sgdisk /dev/block/mmcblk0 --change-name=$vendor_a_partnum:vendor_a
	ui_print "[#] Creating vendor_b..."
	sgdisk /dev/block/mmcblk0 --new=$vendor_b_partnum:$vendor_b_partstart_system:$vendor_b_partend_system
	sgdisk /dev/block/mmcblk0 --change-name=$vendor_b_partnum:vendor_b
	ui_print "[#] Formatting system_a and system_b..."
	sleep 2
	blockdev --rereadpt /dev/block/mmcblk0
	sleep 1
	make_ext4fs /dev/block/mmcblk0p$system_a_partnum
	make_ext4fs /dev/block/mmcblk0p$system_b_partnum
	ui_print "[#] Formatting vendor_a and vendor_b..."
	sleep 2
	make_ext4fs /dev/block/mmcblk0p$vendor_a_partnum
	make_ext4fs /dev/block/mmcblk0p$vendor_b_partnum
	ui_print " "
	ui_print "[i] All done!"
	ui_print " "
	ui_print "[i] You are now ready to install a Treble ROM and/or Vendor pack. Non-Treble ROM's are now incompatible."
fi;

blockdev --rereadpt /dev/block/mmcblk0
sleep 0.2
sync /dev/block/mmcblk0
sleep 0.2

ui_print " ";
ui_print " ";
while read line || [ -n "$line" ]; do
    ui_print "$line"
done < /tmp/aroma/credits.txt
ui_print " ";
ui_print "<#009>Be sure to select 'Save Logs' in case you need to report a bug. Will be saved to microSD root as 'tissot_manager.log'.</#>";
set_progress "1.0"

