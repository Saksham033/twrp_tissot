#!/sbin/sh

### simg2img bootstrap

source /tissot_manager/tools.sh
# note - calling this script from cmd doesn't support ui_print for some reason

sourceFile="$1"
targetMount="$2"

if [ ! -f "$sourceFile" ]; then
	echo "[!] Source file not found!"
	return;
fi

targetBlock=
targetType=
isFilesystem=false

# look for mount point and type from recovery.fstab
while read LINE; do
	firstChar=`echo "$LINE" | head -c 1`
	if [ "$firstChar" = "#" -o "$firstChar" = "" ]; then 
		# skip comments and blank lines
		continue
	fi
    entryMountPoint=$(echo "$LINE" | awk '{ print $2 }')
	if [ "$entryMountPoint" = "$targetMount" ]; then
		targetBlock=$(echo "$LINE" | awk '{ print $1 }')
		targetType=$(echo "$LINE" | awk '{ print $3 }')
		echo "[i] Target block is $targetBlock of type $targetType"
		break;
	fi
done < /etc/recovery.fstab

if [ "$targetBlock" = "" -o "$targetType" = "" ]; then
	# look for mount point and type from twrp.flags
	while read LINE; do
		firstChar=`echo "$LINE" | head -c 1`
		if [ "$firstChar" = "#" -o "$firstChar" = "" ]; then 
			# skip comments and blank lines
			continue
		fi
		entryMountPoint=$(echo "$LINE" | awk '{ print $1 }')
		if [ "$entryMountPoint" = "$targetMount" ]; then
			targetBlock=$(echo "$LINE" | awk '{ print $3 }')
			targetType=$(echo "$LINE" | awk '{ print $2 }')
			echo "[i] Target block is $targetBlock of type $targetType"
			break;
		fi
	done < /etc/twrp.flags
fi

# now check if this block device is actually a filesystem
while read LINE; do
	firstChar=`echo "$LINE" | head -c 1`
	if [ "$firstChar" = "#" -o "$firstChar" = "" ]; then 
		# skip comments and blank lines
		continue
	fi
	entryBlock=$(echo "$LINE" | awk '{ print $3 }')
	if [ "$entryBlock" = "$targetBlock" ]; then
		entryType=$(echo "$LINE" | awk '{ print $2 }')
		if [ "$entryType" = "ext4" -o "$entryType" = "f2fs" ]; then
			isFilesystem=true
		fi
	fi
done < /etc/twrp.flags

if [ "$isFilesystem" = "true" ]; then
	echo "[i] Flash mode is filesystem"
	echo "[#] Running simg2img $sourceFile $targetBlock ..."
	simg2img $sourceFile $targetBlock
	exit $?
else
	echo "[i] Flash mode is raw"
	echo "[#] Running dd if=$sourceFile of=$targetBlock ..."
	dd if=$sourceFile of=$targetBlock
	exit $?
fi

