#!/sbin/sh

### update_engine_sideload bootstrap
# Purpose:
#  - 
#

ui_print() {
	if [ "$1" ]; then
		echo "ui_print $1" > "$OUT_FD"
	else
		echo "ui_print  " > "$OUT_FD"
	fi
	echo
}

# set to a fraction (where 1.0 = 100%)
set_progress() {
	echo "set_progress $1" > "$OUT_FD"
}

# test stuff
echo "$@" > /tmp/update_engine_sideload_params
ls -la /proc/self/fd/ > /tmp/pipe_test

# find the recovery text output pipe
for l in /proc/self/fd/*; do 
	# set the last pipe: target
	if readlink $l | grep -Fqe "pipe:"; then
		echo "Found pipe at $l" >>/tmp/pipe_test
		OUT_FD=$l
	fi
done

ui_print
ui_print "[#] Starting update_engine_sideload..."
# Run the update_engine_sideload
/sbin/update_engine_sideload_real "$@" &
tail -f /tmp/recovery.log | while read LINE; do
	if echo $LINE | grep -Fqe "target_slot: "; then
		# extract target slot
		echo $LINE | sed -e "s|.*target_slot: ||g" | sed -e "s|, url: .*||g" > /tmp/target_slot
	fi
	# break if finished
	if ! kill -0 `pidof update_engine_sideload_real`; then
		break
	fi;
done
ui_print
ui_print "[i] ROM install done to Slot `cat /tmp/target_slot`."
rm /tmp/target_slot
ui_print
ui_print "[i] Be sure to reinstall TWRP immediately, then Reboot Recovery to switch to the new slot before installing anything else."
ui_print
exit $?