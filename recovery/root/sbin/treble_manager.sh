#!/sbin/sh

chmod 777 /treble_manager/*
start treble_manager_launch
sleep 1
kill `pidof recovery`
# loop forever. The treble_manager_launch will reboot recovery when it closes and cleans up
while true; do sleep 1; done

