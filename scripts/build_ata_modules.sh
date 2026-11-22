#!/bin/bash
# Build and install libata / ahci_dwc kernel modules for the running kernel,
# so that the RK3588 SATA controller (sata2) can drive the M.2 B-key slot.
#
# Run ON THE TARGET BOARD (as root). No network needed.
#
#   sudo ./scripts/build_ata_modules.sh
#
# Options:
#   --no-install     build only, do not copy to /lib/modules
#   --keep-build     keep the existing build dir instead of recreating it
#   --build-dir DIR  build directory (default /root/kbuild-ata)
#   --kdir DIR       kernel headers dir (default /usr/src/linux-headers-$(uname -r))
#   --src DIR        drivers/ata source dir (default <pkg>/src/ata)
#   -j N             parallel jobs
set -euo pipefail

PKG_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KVER=$(uname -r)
KDIR="/usr/src/linux-headers-$KVER"
BUILD_DIR="/root/kbuild-ata"
SRC_DIR="$PKG_DIR/src/ata"
DO_INSTALL=1
DO_CLEAN=1
JOBS=$(nproc)

usage() {
	sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
	exit "${1:-0}"
}

while [ $# -gt 0 ]; do
	case "$1" in
		--no-install) DO_INSTALL=0; shift ;;
		--keep-build) DO_CLEAN=0; shift ;;
		--build-dir) BUILD_DIR="$2"; shift 2 ;;
		--kdir) KDIR="$2"; shift 2 ;;
		--src) SRC_DIR="$2"; shift 2 ;;
		-j) JOBS="$2"; shift 2 ;;
		-h|--help) usage 0 ;;
		*) echo "unknown option: $1" >&2; usage 1 ;;
	esac
done

[ "$(id -u)" = 0 ] || { echo "ERROR: run as root" >&2; exit 1; }
[ -d "$KDIR" ] || {
	echo "ERROR: kernel headers not found: $KDIR" >&2
	echo "       install linux-headers-$KVER first (apt install linux-headers-$KVER)" >&2
	exit 1
}
[ -d "$SRC_DIR" ] || { echo "ERROR: ata source not found: $SRC_DIR" >&2; exit 1; }
command -v gcc >/dev/null || { echo "ERROR: gcc not found" >&2; exit 1; }
command -v make >/dev/null || { echo "ERROR: make not found" >&2; exit 1; }

CFG="/boot/config-$KVER"
[ -f "$CFG" ] || { echo "ERROR: $CFG not found" >&2; exit 1; }
grep -q '^CONFIG_MODULES=y' "$CFG" || { echo "ERROR: kernel has no module support" >&2; exit 1; }

if grep -q '^CONFIG_ATA=y' "$CFG"; then
	echo "Kernel already has CONFIG_ATA=y (built-in libata). No module needed."
	exit 0
fi

echo "== kernel     : $KVER"
echo "== headers    : $KDIR"
echo "== build dir  : $BUILD_DIR"
echo "== source     : $SRC_DIR"

if [ "$DO_CLEAN" = 1 ]; then
	rm -rf "$BUILD_DIR"
fi
mkdir -p "$BUILD_DIR"
if [ ! -f "$BUILD_DIR/Makefile" ]; then
	echo "== copying headers tree (about 172MB, one time)..."
	cp -a "$KDIR"/. "$BUILD_DIR"/
fi

echo "== installing drivers/ata sources"
mkdir -p "$BUILD_DIR/drivers/ata"
cp -a "$SRC_DIR"/. "$BUILD_DIR/drivers/ata"/

# Armbian linux-headers packages strip drivers/scsi, libata-eh.c needs this one.
if [ ! -f "$BUILD_DIR/drivers/scsi/scsi_transport_api.h" ]; then
	mkdir -p "$BUILD_DIR/drivers/scsi"
	cp "$PKG_DIR/patches/scsi_transport_api.h" "$BUILD_DIR/drivers/scsi/scsi_transport_api.h"
fi

echo "== configuring"
cp "$CFG" "$BUILD_DIR/.config"
chmod +w "$BUILD_DIR/.config"
(
	cd "$BUILD_DIR"
	./scripts/config --module ATA --module AHCI_DWC \
		--enable SATA_PMP --enable ATA_SFF
	# Keep the exact kernel release string, otherwise module vermagic != uname -r.
	LOCALV=""
	case "$KVER" in *-*) LOCALV="-${KVER#*-}" ;; esac
	./scripts/config --set-str LOCALVERSION "$LOCALV"
	make olddefconfig >/dev/null
	# External module builds do NOT regenerate auto.conf/autoconf.h by
	# themselves - do it explicitly or obj-m stays empty.
	make syncconfig >/dev/null
	# syncconfig can regenerate these without the localversion suffix.
	printf '%s\n' "$KVER" > include/config/kernel.release
	printf '#define UTS_RELEASE "%s"\n' "$KVER" > include/generated/utsrelease.h
)

echo "== building (make -j$JOBS M=drivers/ata)"
make -C "$BUILD_DIR" -j"$JOBS" M=drivers/ata modules

VM=$(modinfo -F vermagic "$BUILD_DIR/drivers/ata/libata.ko")
echo "== vermagic  : $VM"
case "$VM" in
	"$KVER "*) ;;
	*) echo "ERROR: vermagic mismatch, expected: $KVER" >&2; exit 1 ;;
esac

if [ "$DO_INSTALL" = 1 ]; then
	DEST="/lib/modules/$KVER/extra/ata"
	mkdir -p "$DEST"
	cp "$BUILD_DIR"/drivers/ata/libata.ko \
	   "$BUILD_DIR"/drivers/ata/libahci.ko \
	   "$BUILD_DIR"/drivers/ata/libahci_platform.ko \
	   "$BUILD_DIR"/drivers/ata/ahci_dwc.ko "$DEST"/
	depmod -a "$KVER"
	echo "== installed  : $DEST"
	modprobe libata || true
	modprobe ahci_dwc || true
	lsmod | grep -E 'libata|ahci' || true
fi

echo
echo "DONE. Next:"
echo "  sudo $PKG_DIR/scripts/enable_sata2.sh --reboot"
