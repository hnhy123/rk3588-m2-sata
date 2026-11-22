#!/bin/bash
# Roll back the SATA switch: restore the M.2 B-key slot to PCIe (5G) mode.
# Run ON THE TARGET BOARD as root.
#
#   sudo ./scripts/rollback_sata2.sh                 # remove overlay + modules-load
#   sudo ./scripts/rollback_sata2.sh --purge-modules # also delete built modules
#   sudo ./scripts/rollback_sata2.sh --reboot
set -euo pipefail

ENV_FILE=/boot/armbianEnv.txt
OVERLAY=sata2
PURGE=0
DO_REBOOT=0

while [ $# -gt 0 ]; do
	case "$1" in
		--env) ENV_FILE="$2"; shift 2 ;;
		--overlay) OVERLAY="$2"; shift 2 ;;
		--purge-modules) PURGE=1; shift ;;
		--reboot) DO_REBOOT=1; shift ;;
		-h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "unknown option: $1" >&2; exit 1 ;;
	esac
done

[ "$(id -u)" = 0 ] || { echo "ERROR: run as root" >&2; exit 1; }
[ -f "$ENV_FILE" ] || { echo "ERROR: $ENV_FILE not found" >&2; exit 1; }

CUR=$(sed -n 's/^overlays=//p' "$ENV_FILE" | tail -1)
NEW=""
for t in $CUR; do
	[ "$t" = "$OVERLAY" ] && continue
	NEW="${NEW:+$NEW }$t"
done

if [ "$NEW" = "$CUR" ]; then
	echo "== overlays   : $OVERLAY not present, nothing to remove"
elif [ -n "$NEW" ]; then
	sed -i "s|^overlays=.*|overlays=$NEW|" "$ENV_FILE"
	echo "== overlays   : now '$NEW'"
else
	sed -i '/^overlays=.*/d' "$ENV_FILE"
	echo "== overlays   : line removed"
fi

rm -f /etc/modules-load.d/sata-ahci.conf
echo "== modules-load: removed"

if [ "$PURGE" = 1 ]; then
	KVER=$(uname -r)
	rm -rf "/lib/modules/$KVER/extra/ata"
	depmod -a "$KVER"
	echo "== modules    : deleted /lib/modules/$KVER/extra/ata"
fi

sync
echo
echo "Done. Reboot to restore PCIe mode on the B-key slot (5G module)."
if [ "$DO_REBOOT" = 1 ]; then
	reboot
fi
