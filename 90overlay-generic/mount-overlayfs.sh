#!/bin/sh

type getarg > /dev/null 2>&1 || . /lib/dracut-lib.sh

lower=$(getarg rd.overlay.lower)
upper=$(getarg rd.overlay.upper)
work=$(getarg rd.overlay.work)

mount -t overlay overlay -o "lowerdir=${lower},upperdir=${upper},workdir=${work}" "${NEWROOT}"
