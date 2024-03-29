#!/bin/bash
# truncate gpt image file to fit all the partitions
# run as root
# inspired by https://gist.github.com/dkebler/92aa919e9aacc8a3f6b6b07c7abe12b4#file-rock64shrink-sh-L321

img=$1
newdiskinfo=$(fdisk -l $img)
endsector=$(echo "$newdiskinfo" | tail -n 1  | perl -pe 's/ +/\t/g' | cut -f 3)
bps=$(echo "$newdiskinfo" | grep Units | perl -pe 's/.*=//g;s/[^0-9]//g')
# add 33 for gpt backup
newsize=$(echo "($endsector+1+33)*$bps" | bc)
echo "truncating $img to sector ${endsector}+1+33 which will give size of $(printf %.2f $(echo "$newsize/10^9" | bc -l)) GB"
echo "with command 'truncate --size=$newsize $img'"
read -p "Enter to continue"
truncate --size=$newsize $img

#echo "moving backup gpt table to end of image"
#read -p "Enter to continue"
#sgdisk -e "$img"

echo "now use 'gdisk $img' and try to fix it up manually:"
echo "r access Recovery menu"
echo "d use main GPT header (rebuilding backup)"
echo "x extra functionality"
echo "e relocate backup data structures to the end of the disk"
echo "s resize partition table"
echo "100 change to a random value first"
echo "s resize partition table"
echo "128 now to final value"
echo "v verify disk"
echo "w write table to disk and exit"
