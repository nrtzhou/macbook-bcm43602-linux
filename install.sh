#!/usr/bin/env bash
# ==============================================================================
# BCM43602 WiFi fix for MacBook Pro 14,3 (2017) on Linux
# https://github.com/animatek/macbook-bcm43602-linux
#
# Root cause: The BCM43602 firmware (2015) has a buggy internal WPA supplicant
# (FWSUP) that silently fails the 4-way handshake. This script disables FWSUP
# so the host handles WPA authentication instead.
#
# Tested on: Manjaro / Arch Linux, kernel 6.18
# ==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}[+]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# --- Checks ------------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
    error "Run as root: sudo bash install.sh"
fi

IFACE=$(iw dev 2>/dev/null | awk '/Interface/{print $2}' | grep -v p2p | head -1)
if [[ -z "$IFACE" ]]; then
    error "No WiFi interface found. Is brcmfmac loaded? (modprobe brcmfmac)"
fi
info "WiFi interface: $IFACE"

MAC=$(cat /sys/class/net/$IFACE/address 2>/dev/null)
if [[ -z "$MAC" ]]; then
    error "Could not read MAC address for $IFACE"
fi
info "MAC address: $MAC"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIRMWARE_DIR="/usr/lib/firmware/brcm"

# --- 1. NVRAM config file ----------------------------------------------------

info "Installing NVRAM config (brcmfmac43602-pcie.txt)..."
sed "s/YOUR_MAC_HERE/$MAC/" "$SCRIPT_DIR/files/brcmfmac43602-pcie.txt" \
    > "$FIRMWARE_DIR/brcmfmac43602-pcie.txt"
chmod 644 "$FIRMWARE_DIR/brcmfmac43602-pcie.txt"
info "  → $FIRMWARE_DIR/brcmfmac43602-pcie.txt"

# --- 2. Apple-specific firmware symlink --------------------------------------

info "Creating Apple-specific firmware symlink..."
if [[ ! -f "$FIRMWARE_DIR/brcmfmac43602-pcie.bin" ]]; then
    if [[ -f "$FIRMWARE_DIR/brcmfmac43602-pcie.bin.xz" ]]; then
        xz -dk "$FIRMWARE_DIR/brcmfmac43602-pcie.bin.xz"
        info "  Decompressed brcmfmac43602-pcie.bin.xz"
    else
        warn "  brcmfmac43602-pcie.bin not found, skipping symlink"
    fi
fi
if [[ -f "$FIRMWARE_DIR/brcmfmac43602-pcie.bin" ]]; then
    ln -sf brcmfmac43602-pcie.bin \
        "$FIRMWARE_DIR/brcmfmac43602-pcie.Apple Inc.-MacBookPro14,3.bin"
    info "  → $FIRMWARE_DIR/brcmfmac43602-pcie.Apple Inc.-MacBookPro14,3.bin"
fi

# --- 3. modprobe options (FWSUP disable) -------------------------------------

info "Installing modprobe config (feature_disable=0x2000)..."
cp "$SCRIPT_DIR/files/brcmfmac.conf" /etc/modprobe.d/brcmfmac.conf
chmod 644 /etc/modprobe.d/brcmfmac.conf
info "  → /etc/modprobe.d/brcmfmac.conf"

# --- 4. Disable WiFi power save ----------------------------------------------

info "Disabling WiFi power save..."
mkdir -p /etc/NetworkManager/conf.d
cp "$SCRIPT_DIR/files/wifi-powersave.conf" \
    /etc/NetworkManager/conf.d/wifi-powersave.conf
chmod 644 /etc/NetworkManager/conf.d/wifi-powersave.conf
info "  → /etc/NetworkManager/conf.d/wifi-powersave.conf"

# --- 5. Regulatory domain ----------------------------------------------------

info "Setting regulatory domain to ES..."
if command -v iw &>/dev/null; then
    iw reg set ES
fi

REGDOM_FILE="/etc/conf.d/wireless-regdom"
if [[ -f "$REGDOM_FILE" ]]; then
    sed -i 's/^#\?.*WIRELESS_REGDOM.*/WIRELESS_REGDOM="ES"/' "$REGDOM_FILE"
    info "  Updated $REGDOM_FILE"
else
    warn "  $REGDOM_FILE not found — set your country code manually if needed"
fi

# --- 6. Reload driver --------------------------------------------------------

info "Reloading brcmfmac driver..."
modprobe -r brcmfmac_wcc brcmfmac 2>/dev/null || true
sleep 1
modprobe brcmfmac roamoff=1 feature_disable=0x2000

sleep 2
if nmcli -t -f DEVICE,STATE device status 2>/dev/null | grep -q "wifi:connected"; then
    info "WiFi already connected!"
else
    info "Restarting NetworkManager..."
    systemctl restart NetworkManager
    sleep 4
    STATE=$(nmcli -t -f DEVICE,STATE device status 2>/dev/null | grep "^$IFACE" | cut -d: -f2)
    info "WiFi state: $STATE"
fi

# --- Done --------------------------------------------------------------------

echo ""
echo -e "${GREEN}✓ Done!${NC} To verify everything is working:"
echo "  nmcli device status"
echo "  ip addr show $IFACE"
echo ""
echo "If WiFi doesn't connect, reload NM and try again:"
echo "  sudo systemctl restart NetworkManager"
