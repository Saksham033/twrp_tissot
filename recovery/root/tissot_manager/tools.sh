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
	if [ `getCurrentSlotLetter` = "a" ]; then
		echo -n "b"
	else
		echo -n "a"
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

hasDualbootUserdata() {
	if [ -b "/dev/block/bootdevice/by-name/userdata_a" -a -b "/dev/block/bootdevice/by-name/userdata_b" ]; then
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

# Checks if current slot vendor is dualboot patched or not.
# returns:
# "dualboot" for dualboot patched
# "singleboot" for singleboot standard
# "na" for error (missing or incompatible fstab)
vendorDualbootCheck() {
	echo "na" > /tmp/dualboot_check
	umount -f /vendor > /dev/null 2>&1
	mount /dev/block/bootdevice/by-name/vendor_`getCurrentSlotLetter` /vendor > /dev/null 2>&1
	if [ -f "/vendor/etc/fstab.qcom" ]; then
		# We want to loop over all matching lines because there could be multiple userdata mounts (e.g. for ext4 and f2fs ROM's)
		cat "/vendor/etc/fstab.qcom" | grep "/dev/block/bootdevice/by-name/userdata" | while read -r LINE; do
			if echo $LINE | grep -Fqe ",slotselect"; then
				echo "dualboot" > /tmp/dualboot_check
			else
				echo "singleboot" > /tmp/dualboot_check
			fi
		done
	fi
	echo -n `cat /tmp/dualboot_check`
	rm /tmp/dualboot_check
}

# Patches the current slot vendor for dualboot (or back)
# returns:
# "dualboot" for dualboot patch succeeded
# "singleboot" for singleboot patch succeeded
# "na" for error (missing or incompatible fstab)
vendorDualbootPatch() {
	echo "na" > /tmp/dualboot_patch
	dualbootCheck=`vendorDualbootCheck`
	rm "/tmp/fstab.qcom.new" > /dev/null 2>&1
	if [ -f "/vendor/etc/fstab.qcom" -a "$dualbootCheck" != "na" ]; then
		# loop over the existing fstab and create a new one, modifying as necessary. Simplest way to replace a string in specific matching line
		{
			IFS=''
			cat "/vendor/etc/fstab.qcom" | while read LINE; do
				if echo $LINE | grep -Fqe "/dev/block/bootdevice/by-name/userdata"; then
					if [ "$dualbootCheck" = "dualboot" ]; then
						LINE=`echo $LINE | sed 's|,slotselect||'`
						echo "singleboot" > /tmp/dualboot_patch
					elif [ "$dualbootCheck" = "singleboot" ]; then
						LINE=`echo $LINE | sed 's|wait,|wait,slotselect,|'`
						echo "dualboot" > /tmp/dualboot_patch
					fi
				fi
				echo $LINE >> "/tmp/fstab.qcom.new"
			done
		}
		mv -f "/tmp/fstab.qcom.new" "/vendor/etc/fstab.qcom"
		chmod 0644 "/vendor/etc/fstab.qcom"
	fi
	echo -n `cat /tmp/dualboot_patch`
	rm /tmp/dualboot_patch > /dev/null 2>&1
	rm /tmp/fstab.qcom.new > /dev/null 2>&1
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

shouldDoPayloadInstall() {
	targetSlot=`getOtherSlotLetter`
	if [ ! -d /system_new_slot ]; then
		mkdir /system_new_slot
	fi
	chmod 777 /system_new_slot
	umount -f /system
	umount -f /system_new_slot
	mount -o ro /dev/block/bootdevice/by-name/system_$targetSlot /system_new_slot
	if [ -f "/system_new_slot/system/build.prop" ]; then
		# don't bother with any of this if it's an empty slot
		targetSlotId=`cat "/system_new_slot/system/build.prop" | grep -i "ro.build.display.id=" | sed 's|ro\.build\.display\.id=||'`
		if [ "$targetSlotId" != "" ]; then
			echo "id=$targetSlotId" > /tmp/aroma_prompt.prop
		else
			echo "id=Unknown [no ro.build.display.id prop found]" > /tmp/aroma_prompt.prop
		fi
		if [ "$targetSlot" = "a" ]; then
			echo "slot=A" >> /tmp/aroma_prompt.prop
		else
			echo "slot=B" >> /tmp/aroma_prompt.prop
		fi
		
		# Do aroma prompt. It should touch /tmp/flash_confirm if the user agreed to install.
		# It can get the build ID and slot from /tmp/aroma_prompt.prop "id" and "slot" props respectively.
		pauseTwrp
		echo "task=flash_slot_prompt" >> /tmp/aroma_prompt.prop
		ui_print
		/tissot_manager/aroma 1 `basename $OUT_FD` /tissot_manager/tissot_manager.zip >/tmp/tissot_manager_prompt.log
		ui_print
		rm "/tmp/aroma_prompt.prop"
		umount -f /system_new_slot
		# Don't rm -rf here just in case the unmount failed
		#rm -rf /system_new_slot
		resumeTwrp
		
		if [ -f "/tmp/flash_confirm" ]; then
			# return true
			rm "/tmp/flash_confirm"
			return 0
		else
			ui_print "[!] Install aborted by user choice."
			# return false
			return 1
		fi
	else
		ui_print "    [i] Slot $targetSlot appears to be empty"
		# return true
		return 0
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

pauseTwrp() {
	for pid in `pidof recovery`; do 
		kill -SIGSTOP $pid
	done;
}

resumeTwrp() {
	for pid in `pidof recovery`; do 
		kill -SIGCONT $pid
	done;
}



#################################
# Entrypoints for Tissot Manager

if [ "$1" == "userdata_calc" ]; then
	userdataCalcUsageRemainingForSlotA "$@"
elif [ "$1" == "vendorDualbootCheck" ]; then
	vendorDualbootCheck
elif [ "$1" == "vendorDualbootPatch" ]; then
	vendorDualbootPatch
elif [ "$1" == "hasDualbootUserdata" ]; then
	hasDualbootUserdata
fi
