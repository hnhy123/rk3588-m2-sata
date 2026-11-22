# drivers/ata source

Vanilla `drivers/ata` from **linux-7.3.5** (kernel.org, downloaded from the
Tsinghua mirror). Nothing patched.

Why the full directory: the Armbian `linux-headers-<ver>` package ships only
Kconfig/Makefile for `drivers/ata`, not the C sources, so the ATA subsystem
cannot be built out-of-tree without adding them. The tree is 2.8 MB / 123 files.

Only these objects are built by `scripts/build_ata_modules.sh`:

| file | CONFIG |
|---|---|
| libata.ko | CONFIG_ATA=m |
| libahci.ko, libahci_platform.ko, ahci_dwc.ko | CONFIG_AHCI_DWC=m |

`ahci_dwc.c` matches `compatible = "snps,dwc-ahci"`, which is the second
compatible of the RK3588 SATA node, so no vendor patch is required.

License: GPL-2.0 (see the SPDX headers in each file).
