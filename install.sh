#!/usr/bin/env bash
# ==============================================================================
# BCM43602 WiFi 修复脚本 - 适用于 MacBook Pro 12,1 (2015) 在 Linux 下使用
# https://github.com/animatek/macbook-bcm43602-linux
#
# 根本原因：BCM43602 固件 (2015) 存在有缺陷的内部 WPA 认证程序 (FWSUP)，
# 会在四次握手时静默失败。本脚本禁用 FWSUP，改由主机处理 WPA 认证。
#
# 测试环境：Manjaro / Arch Linux，内核 6.18
# ==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}[+]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# --- 检查 ---------------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
    error "请使用 root 权限运行：sudo bash install.sh"
fi

IFACE=$(iw dev 2>/dev/null | awk '/Interface/{print $2}' | grep -v p2p | head -1)
if [[ -z "$IFACE" ]]; then
    error "未找到 WiFi 接口。brcmfmac 是否已加载？(modprobe brcmfmac)"
fi
info "WiFi 接口：$IFACE"

MAC=$(cat /sys/class/net/$IFACE/address 2>/dev/null)
if [[ -z "$MAC" ]]; then
    error "无法读取 $IFACE 的 MAC 地址"
fi
info "MAC 地址：$MAC"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIRMWARE_DIR="/usr/lib/firmware/brcm"

# --- 1. NVRAM 配置文件 --------------------------------------------------------

info "正在安装 NVRAM 配置文件 (brcmfmac43602-pcie.txt)..."
sed "s/YOUR_MAC_HERE/$MAC/" "$SCRIPT_DIR/files/brcmfmac43602-pcie.txt" \
    > "$FIRMWARE_DIR/brcmfmac43602-pcie.txt"
chmod 644 "$FIRMWARE_DIR/brcmfmac43602-pcie.txt"
info "  → $FIRMWARE_DIR/brcmfmac43602-pcie.txt"

# --- 2. Apple 专用固件符号链接 -------------------------------------------------

info "正在创建 Apple 专用固件符号链接..."
if [[ ! -f "$FIRMWARE_DIR/brcmfmac43602-pcie.bin" ]]; then
    if [[ -f "$FIRMWARE_DIR/brcmfmac43602-pcie.bin.zst" ]]; then
        unzstd -f "$FIRMWARE_DIR/brcmfmac43602-pcie.bin.zst" -o "$FIRMWARE_DIR/brcmfmac43602-pcie.bin"
        info "  已解压 brcmfmac43602-pcie.bin.zst"
    else
        warn "  未找到 brcmfmac43602-pcie.bin，跳过符号链接"
    fi
fi
if [[ -f "$FIRMWARE_DIR/brcmfmac43602-pcie.bin" ]]; then
    ln -sf brcmfmac43602-pcie.bin \
        "$FIRMWARE_DIR/brcmfmac43602-pcie.Apple Inc.-MacBookPro12,1.bin"
    info "  → $FIRMWARE_DIR/brcmfmac43602-pcie.Apple Inc.-MacBookPro12,1.bin"
fi

# --- 3. modprobe 配置选项（禁用 FWSUP）-----------------------------------------

info "正在安装 modprobe 配置 (feature_disable=0x2000)..."
cp "$SCRIPT_DIR/files/brcmfmac.conf" /etc/modprobe.d/brcmfmac.conf
chmod 644 /etc/modprobe.d/brcmfmac.conf
info "  → /etc/modprobe.d/brcmfmac.conf"

# --- 4. 禁用 WiFi 省电模式 -----------------------------------------------------

info "正在禁用 WiFi 省电模式..."
mkdir -p /etc/NetworkManager/conf.d
cp "$SCRIPT_DIR/files/wifi-powersave.conf" \
    /etc/NetworkManager/conf.d/wifi-powersave.conf
chmod 644 /etc/NetworkManager/conf.d/wifi-powersave.conf
info "  → /etc/NetworkManager/conf.d/wifi-powersave.conf"

# --- 5. 监管域设置 ------------------------------------------------------------

info "正在设置监管域为 ALL..."
if command -v iw &>/dev/null; then
    iw reg set ALL
fi

REGDOM_FILE="/etc/conf.d/wireless-regdom"
if [[ -f "$REGDOM_FILE" ]]; then
    sed -i 's/^#\?.*WIRELESS_REGDOM.*/WIRELESS_REGDOM="ALL"/' "$REGDOM_FILE"
    info "  已更新 $REGDOM_FILE"
else
    warn "  未找到 $REGDOM_FILE — 如需要请手动设置你的国家代码"
fi

# --- 6. 重新加载驱动 ----------------------------------------------------------

info "正在重新加载 brcmfmac 驱动..."
modprobe -r brcmfmac_wcc brcmfmac 2>/dev/null || true
sleep 1
modprobe brcmfmac roamoff=1 feature_disable=0x2000

sleep 2
if nmcli -t -f DEVICE,STATE device status 2>/dev/null | grep -q "wifi:connected"; then
    info "WiFi 已连接！"
else
    info "正在重启 NetworkManager..."
    systemctl restart NetworkManager
    sleep 4
    STATE=$(nmcli -t -f DEVICE,STATE device status 2>/dev/null | grep "^$IFACE" | cut -d: -f2)
    info "WiFi 状态：$STATE"
fi

# --- 完成 ---------------------------------------------------------------------

echo ""
echo -e "${GREEN}✓ 完成！${NC} 验证是否正常工作："
echo "  nmcli device status"
echo "  ip addr show $IFACE"
echo ""
echo "如果 WiFi 无法连接，请重启 NetworkManager 后重试："
echo "  sudo systemctl restart NetworkManager"
