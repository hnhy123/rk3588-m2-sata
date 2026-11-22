# RK3588 M.2 B-key 槽启用 SATA 固态

**适用设备**：锐丽 Really TVI2340R RK3588 直播机（Armbian，内核 `7.3.5-edge-rockchip64`）
**实测日期**：2026-11-22
**版本**：v1.0

---

## 1. 现象

M.2 B-key 槽插入 NGFF SATA 固态后：

- `lsblk` 只有 eMMC，没有 `/dev/sd*`
- `dmesg | grep -i sata` 完全为空
- `lspci` 只有 WiFi（BCM43752），B-key 槽对应的 PCIe 根端口 `LnkSta: DLActive-`（链路未建立）

## 2. 根因

两个层面同时不具备条件：

1. **板级 DTB 把 3 个 SATA 控制器全关了**：`sata@fe210000`、`sata@fe220000`、`sata@fe230000` 均 `status = "disabled"`。
2. **内核根本没编 ATA 子系统**：`/boot/config-7.3.5-edge-rockchip64` 里是 `# CONFIG_ATA is not set`，`libata` / `ahci_dwc` 模块不存在，`modprobe libata` 直接失败。

此外，这个 B-key 槽在硬件设计上是 **5G 模块槽**（DT 节点 `pcie2x1l1`，带有 `pcie2x1l1-5g-rst`、`pcie2x1l1-pwr-en`、`vcc_5g_dpr_ctl` 等控制脚），默认按 PCIe 2.0 x1 工作，所以插 SATA 盘时 PCIe 侧什么也看不到。

## 3. 为什么能改成 SATA

M.2 B-key（Socket 2）规范里，**SATA 和 PCIe lane0 复用同一组物理引脚**：

| 引脚 | SATA 模式 | PCIe 模式 |
|---|---|---|
| 41 / 43 | SATA-B± | PERp0 / PERn0（接收） |
| 47 / 49 | SATA-A± | PETp0 / PETn0（发送） |

也就是说，板子按 PCIe 布线的 B-key 槽，只要把 SoC 侧 combo PHY 切到 SATA 模式，同一组差分线就能跑 SATA。本板实测确认可行。

本板 DTB 里的 PHY / 控制器对应关系（用 `dtc` 反编译 `/proc/device-tree` 得到）：

| combo PHY | 共用它的控制器 | 实际用途 |
|---|---|---|
| `phy@fee00000` (combphy0_ps) | `pcie2x1l2` + `sata0` | WiFi BCM43752 |
| `phy@fee10000` (combphy1_ps) | `sata1` | 未使用 |
| `phy@fee20000` (combphy2_psu) | `pcie2x1l1` + `sata2` | **M.2 B-key 槽** |

所以本板正确的切换是：**禁用 `pcie2x1l1`，启用 `sata2`**。Armbian 自带的 `rockchip-rk3588-sata2.dtbo` 正是这个内容，直接复用。

槽的 3.3V 由 `vcc3v3_pcie`（GPIO3_11 使能）供电，该 regulator 同时被 WiFi（`pcie2x1l2`）持有，所以切到 SATA 后槽仍然有电；**不要同时禁用 `pcie2x1l2`**，否则 WiFi 掉了、槽也可能断电。

## 4. 包内容

```
rk3588-m2-sata/
├── README.md                     # 本文件
├── QUICKSTART.md                 # 三步速查
├── VERSION
├── MANIFEST.sha256
├── scripts/
│   ├── build_ata_modules.sh      # 在目标机上编译安装 libata/ahci_dwc
│   ├── enable_sata2.sh           # 加 sata2 overlay + 开机加载模块
│   ├── verify_sata.sh            # 验证识别
│   └── rollback_sata2.sh         # 回滚到 PCIe/5G 模式
├── patches/
│   ├── kernel-config-ata.fragment        # 出固件时合入内核配置
│   ├── sata2.dtso                        # overlay 源码（等价于 Armbian 自带版）
│   ├── scsi_transport_api.h              # 编译 libata 需要、headers 包缺失的头
│   └── armbian-customize-image.sh.example# Armbian 构建钩子示例
├── src/ata/                      # vanilla linux-7.3.5 drivers/ata 源码（GPL-2.0）
├── prebuilt/7.3.5-edge-rockchip64/
│   ├── ata/*.ko                  # 与当前内核完全匹配的预编译模块
│   ├── ata-modules-7.3.5-edge-rockchip64.tgz
│   └── README.md                 # 使用条件 + SHA256
├── tools/
│   ├── serial_sendfile.py        # 串口传文件到设备（base64+md5）
│   └── serial_getfile.py         # 从设备取文件
└── docs/
    └── 实测记录.md               # 本次验证的关键输出
```

## 5. 方案 A：现有系统直接用（不重编内核）

前提：目标机已装 `linux-headers-<内核版本>`（Armbian 默认带），有 gcc/make。

```bash
tar xzf rk3588-m2-sata-v1.0.tar.gz
cd rk3588-m2-sata

# 1) 编译并安装 libata / ahci_dwc（约 1-3 分钟）
sudo ./scripts/build_ata_modules.sh

# 2) 加 sata2 overlay、设置开机加载，重启
sudo ./scripts/enable_sata2.sh --reboot

# 3) 重启后验证
sudo ./scripts/verify_sata.sh
```

如果目标机与本机内核完全一致（`uname -r` = `7.3.5-edge-rockchip64`，`/proc/version` 里是 `#75 ... Nov 17 2026`），也可以跳过编译，直接用预编译模块：

```bash
cd prebuilt/7.3.5-edge-rockchip64
sudo mkdir -p /lib/modules/$(uname -r)/extra/ata
sudo cp ata/*.ko /lib/modules/$(uname -r)/extra/ata/
sudo depmod -a && sudo modprobe libata && sudo modprobe ahci_dwc
cd ../.. && sudo ./scripts/enable_sata2.sh --reboot
```

`build_ata_modules.sh` 做的事（出问题时便于排查）：

1. 把 `/usr/src/linux-headers-$(uname -r)` 复制到 `/root/kbuild-ata`
2. 放入 `src/ata` 源码，补 `drivers/scsi/scsi_transport_api.h`
3. 用 `/boot/config-$(uname -r)` 作基础配置，设 `CONFIG_ATA=m`、`CONFIG_AHCI_DWC=m`
4. `make olddefconfig` + `make syncconfig`（**外部模块构建不会自动同步配置**，少了这步 `obj-m` 为空、什么都不会编）
5. 强制 `kernel.release` / `utsrelease.h` 为 `$(uname -r)`（保证 vermagic 匹配）
6. `make M=drivers/ata modules`，校验 vermagic 后装到
   `/lib/modules/$(uname -r)/extra/ata/` 并 `depmod`

## 6. 方案 B：下次出固件时集成（推荐）

### 6.1 内核配置

把 `patches/kernel-config-ata.fragment` 合入构建用的内核 config（Armbian 一般在
`config/kernel/linux-rockchip64-edge.config`，或你构建脚本自己的 config 片段机制）：

```
CONFIG_ATA=y
CONFIG_AHCI_DWC=y
CONFIG_SATA_PMP=y
CONFIG_ATA_SFF=y
```

建议用 `=y` 直接编进内核：固件里不需要额外模块，也不存在升级内核后模块失效的问题。
如果坚持 `=m`，则要把 `libata.ko / libahci.ko / libahci_platform.ko / ahci_dwc.ko`
打进 rootfs，并在 `/etc/modules-load.d/sata-ahci.conf` 里写 `libata`、`ahci_dwc`。

### 6.2 打开 sata2

两种做法任选其一：

**做法 1（改 DTS，最干净）**——在板级 DTS（`rk3588-really.dts`）里加：

```dts
&pcie2x1l1 {
	status = "disabled";
};

&sata2 {
	status = "okay";
};
```

**做法 2（用 overlay，不改 DTS）**——镜像里保留 `overlays=sata2`。
Armbian 的 `linux-dtb` 包自带 `/boot/dtb/rockchip/overlay/rockchip-rk3588-sata2.dtbo`；
若你的构建没有它，用 `patches/sata2.dtso` 自己编：

```bash
dtc -@ -I dts -O dtb -o sata2.dtbo patches/sata2.dtso
cp sata2.dtbo /boot/overlay-user/sata2.dtbo
```

然后在镜像的 `/boot/armbianEnv.txt` 里加（或合并进已有行）：

```
overlays=sata2
```

Armbian 构建可以用 `patches/armbian-customize-image.sh.example` 作为
`userpatches/customize-image.sh` 自动完成这一步。

### 6.3 固件验收

刷机后执行：

```bash
cat /proc/device-tree/sata@fe230000/status     # okay
cat /proc/device-tree/pcie@fe180000/status     # disabled
lsblk                                          # 应出现 /dev/sda
```

## 7. 实测结果

```
ata1: SATA link up 6.0 Gbps (SStatus 133 SControl 300)
ata1.00: ATA-8: LITEON CV3-8D512-11 SATA 512GB, T89110D, max UDMA/133
sd 0:0:0:0: [sda] 1000215216 512-byte logical blocks: (512 GB/477 GiB)
```

- `/dev/sda` 512GB，6.0 Gbps（该槽只布线 1 lane，带宽上限由 SATA 本身决定）
- WiFi（BCM43752）不受影响，仍在 `pcie2x1l2`
- 原盘上的 Windows 分区（EFI + MSR + 3×NTFS）**未做任何写入**

> 注意：镜像带桌面环境时，udisks2 会自动把 NTFS 分区挂到
> `/run/media/<用户>/<UUID>`（ntfs3, `rw`）。不想让它自动写盘就先
> `udisksctl unmount -b /dev/sda5`，需要时再 `mount -o ro` 只读挂载。

## 8. 回滚

```bash
sudo ./scripts/rollback_sata2.sh                  # 移除 overlay + 开机加载配置
sudo ./scripts/rollback_sata2.sh --purge-modules  # 连模块一起删
sudo ./scripts/rollback_sata2.sh --reboot
```

回滚并重启后，B-key 槽恢复 PCIe 模式（可插 5G 模块），SATA 盘不再识别。
`/boot/armbianEnv.txt` 每次修改前会自动备份为 `armbianEnv.txt.bak-sata-<时间戳>`。

## 9. 注意事项 / 踩过的坑

1. **5G 与 SATA 二选一**：`pcie2x1l1` 和 `sata2` 共用 `combphy2_psu`。启用 SATA 后该槽不能再用 5G 模块。
2. **必须保持 vermagic 一致**：内核是 `7.3.5-edge-rockchip64`，不是 `7.3.5`。
   `make modules_prepare` / `make olddefconfig` 可能把 localversion 丢掉，脚本里已强制
   `CONFIG_LOCALVERSION="-edge-rockchip64"` 并重写 `include/config/kernel.release`、
   `include/generated/utsrelease.h`。模块加载前可用
   `modinfo -F vermagic xxx.ko` 与任意系统模块对比。
3. **不要跑 `make modules_prepare`**：Armbian headers 包缺
   `arch/arm64/tools/gen-cpucaps.awk`，会失败；直接 `make M=drivers/ata modules` 即可。
4. **headers 包被裁剪**：`drivers/ata` 只有 Makefile/Kconfig，`drivers/scsi` 缺
   `scsi_transport_api.h`，本包已补齐。
5. **apt 升级内核后必须重编模块**（`uname -r` 变了就失效）；出固件用 `CONFIG_ATA=y` 可彻底避免。
6. **不要同时禁用 `pcie2x1l2`**：`vcc3v3_pcie` 由它和 B-key 槽共用，禁掉可能导致槽断电。
7. 模块是 out-of-tree，加载后内核会 taint（`loading out-of-tree module taints kernel`），无功能影响。
8. 串口控制台是 1500000 8N1；设备无网络时可用 `tools/serial_sendfile.py` 传文件。
   串口登录密码不写死，用 `--password` 或 `SERIAL_PASSWORD` 环境变量传入。

## 10. 换到其他 RK3588 板子怎么改

不同板子的 B-key 槽可能挂在不同的 PCIe 控制器/PHY 上，**不要照抄 sata2**。判定方法：

```bash
dtc -I fs -O dts /proc/device-tree 2>/dev/null > /tmp/dt.dts

# 1) 找到 B-key 槽对应的 PCIe 节点（看 5g/wwan 相关 pinctrl、或物理位置）
#    读出它的 phys 属性里的 phandle 和 PHY_TYPE（2=PCIe）
grep -n -A30 'pcie@fe180000 {' /tmp/dt.dts | grep -E 'phys|status'

# 2) 找到该 phandle 对应的 phy@feeXXXXX
grep -n -A6 'phy@fee20000 {' /tmp/dt.dts

# 3) 找哪个 sata 节点的 phys 用了同一个 phandle（PHY_TYPE=1）
grep -n -A12 'sata@fe2' /tmp/dt.dts | grep -E 'sata@|phys'
```

同一个 PHY 的 `sataN` 就是要启用的那个，然后：

```bash
sudo ./scripts/enable_sata2.sh --overlay sataN
```

如果板子没有对应的 Armbian overlay，用 `patches/sata2.dtso` 改掉
`&pcie2x1l1` / `&sata2` 两个符号后自己编译，放到 `/boot/overlay-user/`。

## 11. 许可

- 本项目脚本与文档：MIT，见 `LICENSE`
- `src/ata/`：Linux 内核源码，GPL-2.0（保留各文件 SPDX 头）
