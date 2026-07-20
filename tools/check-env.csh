#!/bin/csh -f
#
# check-env.csh - OPENSTEP 드라이버 개발환경 일괄 점검.
# OPENSTEP에서 (또는 호스트에서 nxrun.sh 경유로) 실행:
#
#   csh /ndrv/tools/check-env.csh
#
# 결과는 doc/driverkit.md의 [미검증] 항목 확정에 쓴다.

echo "===== system ====="
hostname
uname -a >& /dev/null
if ($status == 0) then
    uname -a
endif
hostinfo

echo ""
echo "===== compiler / make ====="
which cc
cc -v |& head -4
which make

echo ""
echo "===== driver-dev directories ====="
foreach d (/NextDeveloper/Headers/driverkit \
           /NextDeveloper/Makefiles \
           /NextDeveloper/Examples \
           /NextDeveloper/Examples/DriverKit \
           /NextLibrary/Documentation/NextDev \
           /NextAdmin/Configure.app \
           /private/Devices)
    if (-e $d) then
        echo "OK      $d"
    else
        echo "MISSING $d"
    endif
end

echo ""
echo "===== kernel loader tools ====="
foreach f (/usr/etc/kern_loader /usr/etc/kl_util /usr/etc/kl_ld /usr/bin/kl_util)
    if (-e $f) then
        echo "OK      $f"
    else
        echo "MISSING $f"
    endif
end

echo ""
echo "===== installed driver bundles (/private/Devices) ====="
if (-d /private/Devices) then
    ls /private/Devices
endif

echo ""
echo "===== driverkit headers (sample) ====="
if (-d /NextDeveloper/Headers/driverkit) then
    ls /NextDeveloper/Headers/driverkit | head -30
endif

echo ""
echo "check-env: done."
