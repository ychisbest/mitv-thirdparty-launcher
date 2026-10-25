#!/system/bin/sh
# Push to /sdcard then:
#   adb shell 'service call TvService 4400 s16 s s16 "sh,/sdcard/temp-root-id.sh"'
id > /sdcard/root_probe.txt
cat /proc/self/attr/current > /sdcard/selinux_ctx.txt
echo DONE >> /sdcard/root_probe.txt
