#!/sbin/sh

# Various tools for Tissot TWRP by CosmicDan
# Parts from LazyFlasher boot image patcher script by jcadduono

source /tissot_manager/constants.sh

ui_print() {
	if [ "$OUT_FD" ]; then
		if [ "$1" ]; then
			echo "ui_print $1" > "$OUT_FD"
		else
			echo "ui_print  " > "$OUT_FD"
		fi
	else
		echo "$1"
	fi
}

# set to a fraction (where 1.0 = 100%)
set_progress() {
	echo "set_progress $1" > "$OUT_FD"
}

# find the recovery text output pipe (it's always the last one found)
for l in /proc/self/fd/*; do 
	# set the last pipe: target
	if readlink $l | grep -Fqe 'pipe:'; then
		OUT_FD=$l
	fi
done

getCurrentSlotLetter() {
	systemSymlink=`readlink /dev/block/bootdevice/by-name/system`
	echo -n $systemSymlink | tail -c 1
}

getBootSlotLetter() {
	getprop ro.boot.slot_suffix | sed 's|_||'
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

isHotBoot() {
	if cat /proc/cmdline | grep -Fqe " gpt "; then
		# " gpt " in kernel cmdline = real boot
		return 1
	else
		# no " gpt " = fastboot hotboot
		return 0
	fi
}

# internal
dumpAndSplitBoot() {
	dd if=/dev/block/bootdevice/by-name/boot_$1 of=/tmp/boot.img
	bootimg xvf /tmp/boot.img /tmp/boot_split
	rm /tmp/boot.img
}

backupTwrp() {
	if isHotBoot; then
		# Don't do anything if we're on a hotboot
		ui_print "[!] Skipping TWRP survival (unsupported in hotboot)"
		return
	fi
	boot_slot=`getBootSlotLetter`
	ui_print "[#] Backing up current RAMDisk from boot slot $boot_slot"
	ui_print "    (automatic TWRP survival)..."
	dumpAndSplitBoot $boot_slot
	mv /tmp/boot_split/boot.img-ramdisk /tmp/ramdisk-twrp-backup.img
	rm -rf /tmp/boot_split
	if [ ! -f "/tmp/ramdisk-twrp-backup.img" ]; then
		ui_print "    [!] Failed. Check Recovery log for details."
	fi
}

restoreTwrp() {
	if isHotBoot; then
		# Don't do anything if we're on a hotboot
		return
	fi
	targetSlot=$1
	if [ "$targetSlot" != "a" -a "$targetSlot" != "b" ]; then
		ui_print "[!] No target slot specified!"
		return
	fi
	if [ -f "/tmp/ramdisk-twrp-backup.img" ]; then
		ui_print "[#] Reinstalling TWRP to boot slot $targetSlot"
		ui_print "    (automatic TWRP survival)..."
		dumpAndSplitBoot $targetSlot
		if [ -f "/tmp/boot_split/boot.img-ramdisk" ]; then
			rm "/tmp/boot_split/boot.img-ramdisk"
			mv "/tmp/ramdisk-twrp-backup.img" "/tmp/boot_split/boot.img-ramdisk"
			bootimg cvf "/tmp/boot-new.img" "/tmp/boot_split"
			if [ -f "/tmp/boot-new.img" ]; then
				dd if=/tmp/boot-new.img of=/dev/block/bootdevice/by-name/boot_$targetSlot
				rm /tmp/boot-new.img
				touch /tmp/twrp_survival_success
				return
			fi
		fi
		ui_print "    [!] Failed. Check Recovery log for details."
	else
		ui_print "[!] Unable to perform TWRP survival: backup missing!"
	fi
}

userdataCalcUsageRemainingForSlotA() {
	userdata_capacity=`sgdisk --print /dev/block/mmcblk0 | grep -i userdata | awk '{ print $4 }'`
	userdata_start=`sgdisk --print /dev/block/mmcblk0 | grep -i userdata | awk '{ print $2 }'`
	userdata_end=`sgdisk --print /dev/block/mmcblk0 | grep -i userdata | awk '{ print $3 }'`
	userdata_length=`echo $((userdata_end-userdata_start))`
	if [ "$2" == "4gb" ]; then
		if [ "$3" == "as_sectors" ]; then
			userdata_a_shrunk=`dc $userdata_length 8388608 - p`
		else
			userdata_a_shrunk=`dc $userdata_capacity 4 - p`
		fi
	elif [ "$2" == "6gb" ]; then
		if [ "$3" == "as_sectors" ]; then
			userdata_a_shrunk=`dc $userdata_length 12582912 - p`
		else
			userdata_a_shrunk=`dc $userdata_capacity 6 - p`
		fi
	elif [ "$2" == "8gb" ]; then
		if [ "$3" == "as_sectors" ]; then
			userdata_a_shrunk=`dc $userdata_length 16777216 - p`
		else
			userdata_a_shrunk=`dc $userdata_capacity 8 - p`
		fi
	elif [ "$2" == "12gb" ]; then
		if [ "$3" == "as_sectors" ]; then
			userdata_a_shrunk=`dc $userdata_length 25165824 - p`
		else
			userdata_a_shrunk=`dc $userdata_capacity 12 - p`
		fi
	elif [ "$2" == "16gb" ]; then
		if [ "$3" == "as_sectors" ]; then
			userdata_a_shrunk=`dc $userdata_length 33554432 - p`
		else
			userdata_a_shrunk=`dc $userdata_capacity 16 - p`
		fi
	fi
	# subtract vendor_a and vendor_b
	if [ "$3" == "as_sectors" ]; then
		echo -n $((userdata_a_shrunk-2457600))
	else
		echo -n "`dc $userdata_a_shrunk 1.2 - p`"
	fi
}

if [ "$1" == "userdata_calc" ]; then
	userdataCalcUsageRemainingForSlotA "$@"
fi
