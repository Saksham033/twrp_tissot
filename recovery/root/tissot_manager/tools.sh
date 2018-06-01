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

