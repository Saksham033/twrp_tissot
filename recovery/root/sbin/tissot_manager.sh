#!/sbin/sh

chmod 777 /tissot_manager/*
start tissot_manager_launch
sleep 1
kill `pidof recovery`
# loop forever. The tissot_manager_launch will reboot recovery when it closes and cleans up
while true; do sleep 1; done

