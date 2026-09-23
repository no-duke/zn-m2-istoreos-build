# 兆能 M2 iStoreOS 24.10 云编译

> 设备：兆能 M2（ZN M2）/ 高通 IPQ60XX / 1GB 内存 / 128MB NAND / 已硬改 USB 3.0
> 目标：**iStoreOS 24.10 精简版**，默认 IP `192.168.12.1`

---

## 这个仓库干什么

把 **iStoreOS 24.10** 移植到 **兆能 M2** 上，通过 GitHub Actions 云编译出可刷固件。

### 为什么需要移植

**iStoreOS 不支持 zn_m2。** 实测核实：

| 源码 | ipq60xx 设备数 | 含 zn_m2 |
|---|---|---|
| `istoreos/istoreos` @ istoreos-24.10 | 4 个 | ❌ |
| `openwrt/openwrt` @ openwrt-24.10 | 4 个 | ❌ |
| `openwrt/openwrt` @ openwrt-25.12 | 18 个 | ❌ |
| **`LiBwrt/LibWrt` @ 25.12-nss** | 29 个 | ✅ **唯一来源** |

所以本仓库在编译前从 `LibWrt` 注入**四件套**。

---

## 仓库结构

```
.github/workflows/build.yml     编译工作流
configs/zn-m2.config            精简配置（功能 + 去 WiFi + 剔大包）
scripts/diy-part1.sh            【移植注入】DTS / 设备定义 / 网口 / LED
scripts/diy-part2.sh            【定制】默认 IP / 首次启动配置 / extroot 预留
patch/
  ipq6000-m2.dts                zn_m2 设备树（来自 LibWrt）
  ipq6000-cmiot.dtsi            DTS 依赖（zn_m2 的 dts 要 include 它）
  reference-02_network.txt      网口配置参考（LibWrt 原版，含 zn,m2 分支）
  reference-01_leds.txt         LED 配置参考（LibWrt 原版，含 zn,m2 分支）
```

---

## 移植注入了什么（`diy-part1.sh`）

| # | 注入项 | 目标位置 | 不加会怎样 |
|---|---|---|---|
| 1 | `ipq6000-m2.dts` | `qualcommax/files/arch/arm64/boot/dts/qcom/` | 设备树缺失，无法启动 |
| 2 | `define Device/zn_m2` | `qualcommax/image/ipq60xx.mk` | 编译系统不认识这个设备 |
| 3 | `zn,m2)` 分支 | `qualcommax/ipq60xx/base-files/etc/board.d/02_network` | **网口全废**（落到 `*` 分支报 Unsupported hardware） |
| 4 | `zn,m2)` 分支 | 同目录 `01_leds` | LED 不亮 |
| 5 | 移除 `FEATURES += source-only` | `qualcommax/ipq60xx/target.mk` | **只产 rootfs，不产出可刷镜像** |

### 网口映射（注意与现固件不同）

新固件是 **DSA 架构**，不是现固件的 `eth0-3`：

| 物理口 | 现固件（QSDK 4.4） | 新固件（iStoreOS 24.10） |
|---|---|---|
| WAN | `eth0` | **`wan`** |
| LAN × 3 | `eth1` `eth2` `eth3` | **`lan1` `lan2` `lan3`** |

---

## 集成内容

### 预装（用户明确要求保留）

| 功能 | 组件 | 说明 |
|---|---|---|
| CPU 跑分 | `coremark` | `/bin/coremark` |
| CPU 频率 | `luci-app-cpufreq` | 保留原参数 864–1608MHz / ondemand |
| 温度 | 内核 tsens 驱动 | 7 个 zone，随 target 自动编译 |
| ZeroTier | `zerotier` + `luci-app-zerotier` | 内网穿透 |
| 流量监控 | `nlbwmon` + `luci-app-nlbwmon` | 沿用原参数 |
| 代理 | `luci-app-homeproxy` + `sing-box` | **省空间路线，无需额外内核** |

### 刻意不预装

**OpenClash** —— 它需单独下载 15–35MB 的 mihomo 内核，占 overlay 空间。
需要时从 iStoreOS 商店装即可（本固件已给它留出空间）。

### 剔除的大体积项

PCDN / Docker 全家桶 / qbittorrent / transmission / aria2 / minidns / msd_lite /
python3 / adguardhome / alist / kodexplorer / filebrowser / ssr-plus / passwall

---

## 为什么要精简（空间账）

设备 NAND 只有 **128 MiB**，rootfs 分区 96.5MB（已做过大分区），UBI 内部：

```
kernel        3.6 MiB
rootfs       54.4 MiB   ← 现固件（iStoreOS Yipush PCDN 定制版）
rootfs_data  32.4 MiB   ← overlay，可用仅 22.8MB  ← 装不下 OpenClash 的真凶
```

**关键机制**：`rootfs` 卷大小由 squashfs 实际体积决定，`rootfs_data` 只是"剩下的全给它"。
所以**固件瘦多少，可写空间就涨多少**：

| 固件体积 | overlay 可写 |
|---|---|
| 54.4 MB（现固件） | 22.8 MB |
| **~30 MB（本固件目标）** | **~60 MB** |
| ~25 MB | ~65 MB |

---

## 怎么用

1. `Actions` → 左侧 `Build-ZN-M2-iStoreOS` → `Run workflow`
2. 等 3–5 小时
3. 去 `Releases` 下载 `*zn_m2*` 固件

### 首次必须先开权限

`Settings` → `Actions` → `General` → 最下面 `Workflow permissions`
→ 选 **Read and write** → Save

不设这步，编译会成功但**发不了 Release**。

---

## 刷机

### 前置：备份已在手

引导层（CDT/ART/U-Boot）已备份，**刷前确认备份文件在手**。

### 步骤

1. 电脑网卡设 `192.168.10.2`，网线直连 M2
2. 按住 reset 上电 → 进 `192.168.10.10`（暗云 U-Boot）
3. **只点「固件」入口** → 上传 `*factory.ubi`
4. 等重启，访问 `192.168.12.1`（root / password）

### ⛔ 红线

- **不要点「ART」和「U-Boot」入口**
- 刷写过程中**不能断电**
- 跨大版本**不保留配置**

---

## 参数速查

| 项 | 值 |
|---|---|
| 默认 IP | `192.168.12.1` |
| 用户 / 密码 | `root` / `password` |
| 网口 | `wan` + `lan1 lan2 lan3` |
| 源码 | `istoreos/istoreos` @ `istoreos-24.10` |
| 内核 | 6.6 |
| 目标 | `qualcommax` / `ipq60xx` / `DEVICE_zn_m2` |

---

## 已知限制

- **未实机验证**。首次编译如有报错，需按日志定位（本仓库的工作流已内置移植自检，会打印四件套是否注入成功）
- `ipq-wifi-zn_m2` 由设备定义强制带入（几十 KB），无法通过 `.config` 排除，留着无害
- extroot 已在 `fstab` 中预留但**默认关闭**，插 U 盘后可手动启用
