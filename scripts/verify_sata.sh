#!/bin/bash
# Verify that the M.2 B-key slot is running as SATA and the disk is visible.
# Run ON THE TARGET BOARD (root recommended for dmesg).
set -u

KVER=$(uname -r)
echo "== kernel     : $KVER"
echo "== sata2      : $(tr -d '\0' < /proc/device-tree/sata@fe230000/status 2>/dev/null || echo MISSING)"
echo "== pcie2x1l1  : $(tr -d '\0' < /proc/device-tree/pcie@fe180000/status 2>/dev/null || echo MISSING)"
echo "== combphy2   : $(tr -d '\0' < /proc/device-tree/phy@fee20000/status 2>/dev/null || echo MISSING)"

echo "-- modules:"
lsmod | grep -E 'libata|ahci' || echo "   !! libata/ahci_dwc not loaded"

echo "-- ata links:"
found=0
for f in /sys/class/ata_link/*/sata_spd; do
	[ -e "$f" ] || continue
	found=1
	echo "   $(basename "$(dirname "$f")") = $(cat "$f")"
done
[ "$found" = 1 ] || echo "   !! no ata_link (no SATA device detected)"

echo "-- dmesg:"
(dmesg 2>/dev/null || cat /var/log/kern.log 2>/dev/null) |
	grep -iE 'ahci|SATA link|ata[0-9]|Direct-Access|Attached SCSI disk' | tail -15

echo "-- block devices:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT

if ls /dev/sd? >/dev/null 2>&1; then
	echo "RESULT: OK - SATA disk present: $(ls /dev/sd? | tr '\n' ' ')"
else
	echo "RESULT: FAIL - no /dev/sd* device"
	exit 1
fi
