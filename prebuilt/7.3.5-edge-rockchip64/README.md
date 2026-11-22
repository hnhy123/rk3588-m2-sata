# Prebuilt modules — 7.3.5-edge-rockchip64

Built on the target board on 2026-11-22 for exactly:

```
Linux really 7.3.5-edge-rockchip64 #75 SMP PREEMPT Tue Nov 17 18:14:21 CST 2026 aarch64
```

`modinfo -F vermagic` = `7.3.5-edge-rockchip64 SMP preempt mod_unload aarch64`.

**Do not use on another kernel version/build** — vermagic must match exactly.
Check first:

```bash
uname -r                       # must print 7.3.5-edge-rockchip64
grep '^Linux version' /proc/version
```

Install:

```bash
sudo mkdir -p /lib/modules/$(uname -r)/extra/ata
sudo cp ata/*.ko /lib/modules/$(uname -r)/extra/ata/
sudo depmod -a
sudo modprobe libata && sudo modprobe ahci_dwc
```

Then run `scripts/enable_sata2.sh --reboot` from the package root.

SHA256:

```
7f1975365933c40c133ff885725037679c69287a48888e4be3e10e1c325acaea  ata/ahci_dwc.ko
fd821d62a0e5e02a639ff6dc8da68ca65060e5a936f55e2de8a09cb848f3ffbd  ata/libahci.ko
87da65d07373faa17f05a668fa230b70ac331f9a038298937fcbc71b8bd177ed  ata/libahci_platform.ko
cdfaee3c7a3cab7a18f008750f11d2e059f2b980d6c1d0d2772d6fa57bce1a01  ata/libata.ko
fd848f5c2d0fd8f92ea2cf80bc0e233b0e9a9e8d2702da9f3ef6239162f69ffd  ata-modules-7.3.5-edge-rockchip64.tgz
```

If the checksums differ, use `scripts/build_ata_modules.sh` to rebuild from
`src/ata` instead.
