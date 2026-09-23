#!/bin/bash
# ============================================================================
# diy-part1.sh —— 【移植注入】在 feeds update 之前执行
# 工作目录：openwrt/
#
# 移植目标：把 zn_m2 加入 iStoreOS 的 qualcommax/ipq60xx
# ----------------------------------------------------------------------------
# 背景：iStoreOS 的 ipq60xx 只有 4 个设备（8devices_mango-dvk /
#       cambiumnetworks_xe3-4 / netgear_wax214 / yuncore_fap650），
#       **不含 zn_m2**。而 02_network 里 `*)` 分支会直接报
#       "Unsupported hardware"，导致网口全废。
#
# 四件套素材全部来自 LiBwrt/LibWrt @ 25.12-nss（唯一支持 zn_m2 的源码）
# ============================================================================
set -e

echo "=============================================================="
echo "  ZN-M2 移植注入开始"
echo "  工作目录: $(pwd)"
echo "=============================================================="

PATCH_SRC="${GITHUB_WORKSPACE}/patch"
QCA="target/linux/qualcommax"

# ----------------------------------------------------------------------------
# 0. 前置校验
# ----------------------------------------------------------------------------
if [ ! -d "$QCA" ]; then
    echo "!! 致命错误：找不到 $QCA，源码结构可能已变"
    exit 1
fi
echo ""
echo "[0/6] 前置校验通过，$QCA 存在"

# ----------------------------------------------------------------------------
# 1. 注入 DTS
#    zn_m2 的 DTS 依赖 ipq6000-cmiot.dtsi（iStoreOS 里已存在，无需搬运）
# ----------------------------------------------------------------------------
echo ""
echo "[1/6] 注入 DTS：ipq6000-m2.dts"
DTS_DIR="$QCA/files/arch/arm64/boot/dts/qcom"
mkdir -p "$DTS_DIR"

if [ -f "$PATCH_SRC/ipq6000-m2.dts" ]; then
    cp "$PATCH_SRC/ipq6000-m2.dts" "$DTS_DIR/"
    echo "    ✓ 已复制到 $DTS_DIR/"
else
    echo "    !! patch/ipq6000-m2.dts 缺失"
    exit 1
fi

# 确认依赖的 dtsi 存在
if [ -f "$DTS_DIR/ipq6000-cmiot.dtsi" ]; then
    echo "    ✓ 依赖 ipq6000-cmiot.dtsi 存在"
else
    echo "    ⚠ 依赖 ipq6000-cmiot.dtsi 不存在，尝试从 patch 复制"
    [ -f "$PATCH_SRC/ipq6000-cmiot.dtsi" ] && cp "$PATCH_SRC/ipq6000-cmiot.dtsi" "$DTS_DIR/" && echo "    ✓ 已补入"
fi

echo "    --- DTS 关键行校验 ---"
grep -E 'model|compatible' "$DTS_DIR/ipq6000-m2.dts" | head -3

# ----------------------------------------------------------------------------
# 2. 注入设备定义到 image/ipq60xx.mk
# ----------------------------------------------------------------------------
echo ""
echo "[2/6] 注入设备定义：define Device/zn_m2"
MK="$QCA/image/ipq60xx.mk"

if [ ! -f "$MK" ]; then
    echo "    !! $MK 不存在"
    exit 1
fi

if grep -q "define Device/zn_m2" "$MK"; then
    echo "    ✓ 已存在，跳过"
else
    cat >> "$MK" <<'MKEOF'

define Device/zn_m2
	$(call Device/FitImage)
	$(call Device/UbiFit)
	DEVICE_VENDOR := ZN
	DEVICE_MODEL := M2
	BLOCKSIZE := 128k
	PAGESIZE := 2048
	SOC := ipq6000
	DEVICE_DTS_CONFIG := config@cp03-c1
	DEVICE_PACKAGES := ipq-wifi-zn_m2
endef
TARGET_DEVICES += zn_m2
MKEOF
    echo "    ✓ 已追加设备定义"
fi

echo "    --- 当前 ipq60xx.mk 设备列表 ---"
grep -o 'define Device/[A-Za-z0-9_-]*' "$MK" | sed 's|define Device/|      |'

# ----------------------------------------------------------------------------
# 3. 注入网口配置到 02_network
# ----------------------------------------------------------------------------
echo ""
echo "[3/6] 注入网口配置：02_network"
NET="$QCA/ipq60xx/base-files/etc/board.d/02_network"

if [ ! -f "$NET" ]; then
    echo "    !! $NET 不存在"
    exit 1
fi

if grep -q 'zn,m2' "$NET"; then
    echo "    ✓ 已含 zn,m2，跳过"
else
    # 在 "Unsupported hardware" 那行之前插入 zn,m2 分支
    sed -i '/echo "Unsupported hardware/i\\tzn,m2)\n\t\tucidef_set_interfaces_lan_wan "lan1 lan2 lan3" "wan"\n\t\t;;' "$NET"
    echo "    ✓ 已插入 zn,m2 分支"
fi
echo "    --- 校验（缩进可能被 sed 吃掉，只要语法正确即可）---"
grep -B1 -A3 'zn,m2' "$NET"

# ----------------------------------------------------------------------------
# 4. 注入 LED 配置到 01_leds
# ----------------------------------------------------------------------------
echo ""
echo "[4/6] 注入 LED 配置：01_leds"
LED="$QCA/ipq60xx/base-files/etc/board.d/01_leds"

if [ ! -f "$LED" ]; then
    echo "    ⚠ $LED 不存在，跳过（非致命）"
else
    if grep -q 'zn,m2' "$LED"; then
        echo "    ✓ 已含 zn,m2，跳过"
    else
        # 在最后的 esac 之前插入
        sed -i '/^esac/i\\nzn,m2)\n\tucidef_set_led_netdev "wan" "WAN" "blue:wan" "wan"\n\tucidef_set_led_netdev "lan" "LAN" "blue:lan" "br-lan"\n\tucidef_set_led_netdev "wlan2g" "WLAN2G" "blue:wlan2g" "phy1-ap0"\n\tucidef_set_led_netdev "wlan5g" "WLAN5G" "blue:wlan5g" "phy0-ap0"\n\t;;\n' "$LED"
        echo "    ✓ 已插入 zn,m2 LED 配置"
    fi
    echo "    --- 校验 ---"
    grep -A5 'zn,m2' "$LED" || echo "      (未匹配到)"
fi

# ----------------------------------------------------------------------------
# 5. 移除 source-only
#    iStoreOS 的 ipq60xx/target.mk 带 FEATURES += source-only，
#    该特性会让编译只产出 rootfs 而不打包可刷镜像，必须去掉
# ----------------------------------------------------------------------------
echo ""
echo "[5/6] 移除 source-only（否则不产 factory 镜像）"
TMK="$QCA/ipq60xx/target.mk"
if [ -f "$TMK" ]; then
    echo "    --- 处理前 ---"
    cat "$TMK" | sed 's/^/      /'
    sed -i 's/^FEATURES += source-only/# FEATURES += source-only   # 已由 ZN-M2 移植移除/' "$TMK"
    echo "    --- 处理后 ---"
    cat "$TMK" | sed 's/^/      /'
else
    echo "    ⚠ $TMK 不存在"
fi

# ----------------------------------------------------------------------------
# 6. 收尾自检
# ----------------------------------------------------------------------------
echo ""
echo "[6/6] 移植自检"
echo "    DTS          : $([ -f "$DTS_DIR/ipq6000-m2.dts" ] && echo '✓' || echo '✗')"
echo "    设备定义     : $(grep -q 'define Device/zn_m2' "$MK" && echo '✓' || echo '✗')"
echo "    02_network   : $(grep -q 'zn,m2' "$NET" && echo '✓' || echo '✗')"
echo "    01_leds      : $([ -f "$LED" ] && (grep -q 'zn,m2' "$LED" && echo '✓' || echo '✗') || echo '跳过')"
echo "    source-only  : $(grep -q '^FEATURES += source-only' "$TMK" 2>/dev/null && echo '✗ 仍存在' || echo '✓ 已移除')"

echo ""
echo "=============================================================="
echo "  ZN-M2 移植注入完成"
echo "=============================================================="
