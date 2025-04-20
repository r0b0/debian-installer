function notify {
  echo $@
  read -p "Enter to continue"
}

function shrink_btrfs_filesystem {
  local filesystem=$1
  notify balancing and shrinking the filesystem ${filesystem}
  btrfs balance start -dusage=90 -musage=90 ${filesystem}
  true
  while [ $? -eq 0 ]; do
      btrfs filesystem resize -1G ${filesystem}
  done
  true
  while [ $? -eq 0 ]; do
      btrfs filesystem resize -100M ${filesystem}
  done
  true
  while [ $? -eq 0 ]; do
      btrfs filesystem resize -10M ${filesystem}
  done

  btrfs filesystem usage -m ${filesystem} |grep slack | cut -f 3 | tr -d '[:space:]' > device_slack.txt
  local DEVICE_SLACK=$(cat device_slack.txt)
  echo device slack is ${DEVICE_SLACK}
}

function shrink_partition {
  local slack=$1
  local disk=$2
  local partition_nr=$3
  if [ ! -f "partition_${partition_nr}_shrunk.txt" ]; then
    notify shrinking partition ${disk}${partition_nr} by ${slack}
    echo ", -${slack}" | sfdisk ${disk} -N ${partition_nr}
    notify checking the filesystem after partition shrink
    btrfs check "${disk}${partition_nr}"
    touch "partition_${partition_nr}_shrunk.txt"
  fi
}