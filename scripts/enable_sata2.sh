#!/bin/bash
# Enable the M.2 B-key slot as SATA: disable pcie2x1l1, enable sata2,
# and make sure libata/ahci_dwc are loaded at boot.
#
# Run ON THE TARGET BOARD as root.
#   sudo ./scripts/enable_sata2.sh            # configure, do not reboot
#   sudo ./scripts/enable_sata2.sh --reboot   # configure and reboot
#
# Options:
#   --env FILE       boot env file (default /boot/armbianEnv.txt)
#   --overlay NAME   overlay name (default sata2)
#   --reboot         reboot at the end
#   --no-modules     do not create /etc/modules-load.d (kernel has CONFIG_ATA=y)
set -euo pipefail

ENV_FILE=/boot/armbianEnv.txt
OVERLAY=sata2
DO_REBOOT=0
DO_MODULES=1

while [ $# -gt 0 ]; do
	case "$1" in
		--env) ENV_FILE="$2"; shift 2 ;;
		--overlay) OVERLAY="$2"; shift 2 ;;
		--reboot) DO_REBOOT=1; shift ;;
		--no-modules) DO_MODULES=0; shift ;;
		-h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "unknown option: $1" >&2; exit 1 ;;
	esac
done

[ "$(id -u)" = 0 ] || { echo "ERROR: run as root" >&2; exit 1; }
[ -f "$ENV_FILE" ] || { echo "ERROR: $ENV_FILE not found" >&2; exit 1; }

PREFIX=$(sed -n 's/^overlay_prefix=//p' "$ENV_FILE" | tail -1)
PREFIX=${PREFIX:-rockchip-rk3588}

DTBO=""
for cand in "/boot/dtb/rockchip/overlay/${PREFIX}-${OVERLAY}.dtbo" \
            "/boot/overlay-user/${OVERLAY}.dtbo"; do
	[ -f "$cand" ] && DTBO="$cand" && break
done
if [ -z "$DTBO" ]; then
	echo "ERROR: overlay not found." >&2
	echo "Looked for:" >&2
	echo "  /boot/dtb/rockchip/overlay/${PREFIX}-${OVERLAY}.dtbo" >&2
	echo "  /boot/overlay-user/${OVERLAY}.dtbo" >&2
	echo "Compile patches/sata2.dtso and install it as /boot/overlay-user/${OVERLAY}.dtbo," >&2
	echo "or update linux-dtb (Armbian ships rockchip-rk3588-sata2.dtbo)." >&2
	exit 1
fi
echo "== overlay    : $DTBO"

BK="$ENV_FILE.bak-sata-$(date +%Y%m%d-%H%M%S)"
cp -a "$ENV_FILE" "$BK"
echo "== backup     : $BK"

CUR=$(sed -n 's/^overlays=//p' "$ENV_FILE" | tail -1)
case " $CUR " in
	*" $OVERLAY "*)
		echo "== overlays   : already contains $OVERLAY"
		;;
	*)
		if [ -n "$CUR" ]; then
			NEW="$CUR $OVERLAY"
			sed -i "s|^overlays=.*|overlays=$NEW|" "$ENV_FILE"
		else
			# drop an empty overlays= line if present, then append
			sed -i '/^overlays=$/d' "$ENV_FILE"
			echo "overlays=$OVERLAY" >> "$ENV_FILE"
		fi
		echo "== overlays   : $OVERLAY added"
		;;
esac
grep '^overlays=' "$ENV_FILE"

KVER=$(uname -r)
CFG="/boot/config-$KVER"
if [ "$DO_MODULES" = 1 ]; then
	if [ -f "$CFG" ] && grep -q '^CONFIG_ATA=y' "$CFG"; then
		echo "== modules    : kernel has built-in ATA, skipping modules-load.d"
	else
		printf 'libata\nahci_dwc\n' > /etc/modules-load.d/sata-ahci.conf
		echo "== modules    : /etc/modules-load.d/sata-ahci.conf"
	fi
fi

sync
echo
echo "Configured. Reboot to apply:  reboot"
echo "After reboot check with:      sudo $PWD/verify_sata.sh"
if [ "$DO_REBOOT" = 1 ]; then
	echo "Rebooting now..."
	reboot
fi
