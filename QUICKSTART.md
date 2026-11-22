# QUICKSTART（给同事）

目标：让 RK3588 直播机的 M.2 B-key 槽识别 NGFF SATA 固态。

## 前提

- 设备是锐丽 Really TVI2340R（Armbian，内核 `7.3.5-edge-rockchip64`）
- root 权限；已安装 `linux-headers-$(uname -r)`、gcc、make
- 该槽以后不能再用 5G 模块（SATA 与 5G PCIe 二选一）

## 三步

```bash
tar xzf rk3588-m2-sata-v1.0.tar.gz
cd rk3588-m2-sata

sudo ./scripts/build_ata_modules.sh          # 编 libata/ahci_dwc 并安装
sudo ./scripts/enable_sata2.sh --reboot      # 加 sata2 overlay，重启
```

重启后：

```bash
sudo ./scripts/verify_sata.sh
```

看到 `RESULT: OK - SATA disk present: /dev/sda` 就成功了。

## 内核版本完全一致时（可选，跳过编译）

```bash
cd prebuilt/7.3.5-edge-rockchip64
sudo mkdir -p /lib/modules/$(uname -r)/extra/ata
sudo cp ata/*.ko /lib/modules/$(uname -r)/extra/ata/
sudo depmod -a && sudo modprobe libata && sudo modprobe ahci_dwc
cd ../.. && sudo ./scripts/enable_sata2.sh --reboot
```

## 失败时先看这三条

```bash
uname -r                                     # 必须是 7.3.5-edge-rockchip64
cat /proc/device-tree/sata@fe230000/status    # 必须是 okay
dmesg | grep -iE 'ahci|ata1|SATA link'
```

回滚：

```bash
sudo ./scripts/rollback_sata2.sh --purge-modules --reboot
```

详细原理、固件集成方法和踩坑记录见 `README.md`。
