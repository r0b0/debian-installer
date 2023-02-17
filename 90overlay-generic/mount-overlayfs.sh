#!/bin/sh

type getarg > /dev/null 2>&1 || . /lib/dracut-lib.sh
type wait_for_mount > /dev/null 2>&1 || . /lib/dracut-lib.sh

lower=$(getarg rd.overlay.lower)
upper=$(getarg rd.overlay.upper)
work=$(getarg rd.overlay.work)

wait_for_mount ${lower}
wait_for_mount ${upper}
wait_for_mount ${work}
sleep 2

mount -t overlay overlay -o "lowerdir=${lower},upperdir=${upper},workdir=${work}" "${NEWROOT}"
