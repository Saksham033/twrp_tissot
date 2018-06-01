#!/sbin/sh

# Various tools

source /tissot_manager/constants.sh

getCurrentSlotLetter() {
	systemSymlink=`readlink /dev/block/bootdevice/by-name/system`
	echo -n $systemSymlink | tail -c 1
}

getOtherSlotLetter() {
	if getCurrentSlotLetter="a"; then
		echo "b"
	else
		echo "a"
	fi
}

isTreble() {
	if [ -b "/dev/block/bootdevice/by-name/vendor_a" -a -b "/dev/block/bootdevice/by-name/vendor_b" ]; then
		# return 0 = true
		return 0 
	else
		# return 1 = false
		return 1
	fi
}

backupTwrp() {
	# check if our current ramdisk is TWRP with Tissot Manager
	if [ -f /tissot_manager/installer.sh ]; then
		ui_print "[#] Backing up current RAMDisk (TWRP survival)..."
		
	fi
}



