# BCM43602 WiFi fix for MacBook Pro 14,3 on Linux

Fix for Broadcom BCM43602 WiFi on MacBook Pro 14,3 (2017) running Linux.

**Symptoms:** WiFi associates to the AP but never authenticates — the 4-way WPA handshake times out silently. NetworkManager shows "needs authentication" or keeps retrying.

**Root cause:** The BCM43602 firmware (dated 2015) has an internal WPA supplicant (`FWSUP`) that is supposed to handle the WPA handshake inside the chip. It's buggy: it associates successfully but never completes the EAPOL key exchange, and the frames never reach the host. Disabling `FWSUP` (via `feature_disable=0x2000`) forces the host (wpa_supplicant/NetworkManager) to do the handshake — which works correctly.

---

## Hardware

| | |
|---|---|
| **Device** | MacBook Pro 14,3 (2017) |
| **WiFi chip** | Broadcom BCM43602 (PCI ID `14e4:43ba`) |
| **Driver** | `brcmfmac` (open-source, included in mainline kernel) |
| **Tested on** | Manjaro / Arch Linux, kernel 6.x |

---

## Quick install

```bash
git clone https://github.com/animatek/macbook-bcm43602-linux.git
cd macbook-bcm43602-linux
sudo bash install.sh
```

---

## What the script does

| Step | File | Purpose |
|------|------|---------|
| 1 | `/usr/lib/firmware/brcm/brcmfmac43602-pcie.txt` | NVRAM config: sets `ccode=ES`, disables firmware WPA (`sup_wpa=0`) |
| 2 | `brcmfmac43602-pcie.Apple Inc.-MacBookPro14,3.bin` symlink | Loads device-specific firmware path |
| 3 | `/etc/modprobe.d/brcmfmac.conf` | `feature_disable=0x2000` disables `BRCMF_FEAT_FWSUP` (bit 13) |
| 4 | `/etc/NetworkManager/conf.d/wifi-powersave.conf` | Disables power saving to prevent disconnections |
| 5 | `/etc/conf.d/wireless-regdom` | Sets regulatory domain to ES (Spain) |

### Key fix explained

`/etc/modprobe.d/brcmfmac.conf`:
```
options brcmfmac roamoff=1 feature_disable=0x2000
```

- **`feature_disable=0x2000`** — disables `BRCMF_FEAT_FWSUP` (bit 13 in `enum brcmf_feat_id`). This is the firmware-based WPA supplicant. Without this, the 2015 firmware silently fails the 4-way handshake.
- **`roamoff=1`** — disables firmware-based roaming, which can also interfere with authentication.

> **Note on `ccode`:** The NVRAM sets `ccode=ES` (Spain). If you're in a different country, edit `files/brcmfmac43602-pcie.txt` and change `ccode=ES` to your country code (e.g., `ccode=DE`, `ccode=US`) before running the script. Also update `/etc/conf.d/wireless-regdom` accordingly.

---

## Manual installation

If you prefer to apply the fixes manually:

### 1. modprobe options (most important fix)

```bash
sudo tee /etc/modprobe.d/brcmfmac.conf << 'EOF'
options brcmfmac roamoff=1 feature_disable=0x2000
EOF
```

### 2. NVRAM config

```bash
# Get your MAC address
MAC=$(cat /sys/class/net/wlp3s0/address)

# Copy NVRAM file with your MAC
sudo cp files/brcmfmac43602-pcie.txt /usr/lib/firmware/brcm/
sudo sed -i "s/YOUR_MAC_HERE/$MAC/" /usr/lib/firmware/brcm/brcmfmac43602-pcie.txt
```

### 3. Firmware symlink

```bash
cd /usr/lib/firmware/brcm/
sudo xz -dk brcmfmac43602-pcie.bin.xz
sudo ln -sf brcmfmac43602-pcie.bin "brcmfmac43602-pcie.Apple Inc.-MacBookPro14,3.bin"
```

### 4. Disable WiFi power save

```bash
sudo tee /etc/NetworkManager/conf.d/wifi-powersave.conf << 'EOF'
[connection]
wifi.powersave = 2
EOF
```

### 5. Reload driver and NetworkManager

```bash
sudo modprobe -r brcmfmac_wcc brcmfmac
sudo modprobe brcmfmac roamoff=1 feature_disable=0x2000
sudo systemctl restart NetworkManager
```

---

## Verify it's working

```bash
# Should show "connected"
nmcli device status

# Should show an IP address
ip addr show wlp3s0 | grep inet

# Regulatory domain (should match your country)
iw reg get | head -3
```

---

## Related

- [Kernel bug #193121](https://bugzilla.kernel.org/show_bug.cgi?id=193121) — BCM43602 on Linux (NVRAM / country code issues)
- [broadcom-wl-dkms-kernel6](https://github.com/animatek/broadcom-wl-dkms-kernel6) — Fix for the proprietary `wl` driver on BCM4360 (different chip/driver)

---

## License

MIT
