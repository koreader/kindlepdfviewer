#!/bin/sh
export LC_ALL="en_US.UTF-8"

echo unlock > /proc/keypad
echo unlock > /proc/fiveway

cd /mnt/us/kindlepdfviewer/

grep /mnt/us/kindlepdfviewer/fonts/host /proc/mounts || mount -o bind /usr/java/lib/fonts /mnt/us/kindlepdfviewer/fonts/host

test "$2" == "framework_stop" && /etc/init.d/framework stop

./reader.lua "$1" 2> /mnt/us/kindlepdfviewer/crash.log || cat /mnt/us/kindlepdfviewer/crash.log

grep /mnt/us/kindlepdfviewer/fonts/host /proc/mounts && umount /mnt/us/kindlepdfviewer/fonts/host

# always try to continue cvm
killall -cont cvm || /etc/init.d/framework start

# cleanup hanging process
killall lipc-wait-event

