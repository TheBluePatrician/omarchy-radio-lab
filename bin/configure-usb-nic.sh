#!/usr/bin/env bash
# Persist US regulatory domain, unlock MediaTek 6 GHz CLC, and treat the
# MT7921U USB radio as a dedicated lab NIC. Must run as root (pkexec).
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "configure-usb-nic.sh must run as root (pkexec $0)" >&2
  exit 2
fi

SRC="$(cd "$(dirname "$0")" && pwd)"
ALLOW_UID="${PKEXEC_UID:-${SUDO_UID:-1000}}"
ALLOW_USER="$(id -un "${ALLOW_UID}" 2>/dev/null || true)"
ALLOW_HOME="$(getent passwd "${ALLOW_UID}" | cut -d: -f6)"
ALLOW_HOME="${ALLOW_HOME:-/home/${ALLOW_USER:-${ALLOW_UID}}}"

# --- US regulatory domain (required for 6 GHz to be enabled, not disabled) ---
regdom_file=/etc/conf.d/wireless-regdom
if [[ -f $regdom_file ]]; then
  if grep -q '^WIRELESS_REGDOM=' "$regdom_file"; then
    sed -i 's/^WIRELESS_REGDOM=.*/WIRELESS_REGDOM="US"/' "$regdom_file"
  else
    printf '\nWIRELESS_REGDOM="US"\n' >> "$regdom_file"
  fi
else
  printf 'WIRELESS_REGDOM="US"\n' > "$regdom_file"
fi

install -d /etc/modprobe.d
cat > /etc/modprobe.d/cfg80211-regdom.conf <<'EOF'
# Lock the kernel regulatory domain to US so 6 GHz (U-NII-5..8) is enabled.
options cfg80211 ieee80211_regdom=US
EOF

# MediaTek CLC (country location control) often leaves 6 GHz listen-only or
# blocked even after iw reg set US. Disable it for this lab adapter.
cat > /etc/modprobe.d/mt7921-6ghz.conf <<'EOF'
# Allow the MT7921U USB Wi-Fi 6E NIC to use the kernel US 6 GHz map.
options mt7921_common disable_clc=1
EOF

# Do not permanently unmanage the USB NIC. Radio Lab unmanages it only while
# Monitor/Disable is active; Restore Wi-Fi and the network panel INTERFACE
# picker need NetworkManager to be able to take it as a station.

# Reinstall helper binary if present so 6 GHz freq parking is live.
if [[ -x ${SRC}/wnicd ]]; then
  install -d -m 0755 /usr/local/lib/radio-lab
  install -m 0755 "${SRC}/wnicd" /usr/local/lib/radio-lab/wnicd
  ln -sfn /usr/local/lib/radio-lab/wnicd /usr/local/bin/wnic-ctl
  ln -sfn /usr/local/lib/radio-lab/wnicd /usr/local/bin/wnicd
fi

if command -v pacman >/dev/null 2>&1; then
  pacman -S --noconfirm --needed usbutils iw wireless-regdb >/dev/null 2>&1 || true
fi

if systemctl is-active --quiet wnicd.service 2>/dev/null; then
  systemctl stop wnicd.service || true
fi

iw reg set US || true

if command -v nmcli >/dev/null 2>&1; then
  nmcli general reload || true
fi

# Reprobe so disable_clc=1 is actually loaded (module params apply at insert).
for iface in $(iw dev 2>/dev/null | awk '/Interface/{print $2}'); do
  if [[ $iface == rlab* || $iface == wlp0s20f0u* ]]; then
    ip link set "$iface" down 2>/dev/null || true
    iw dev "$iface" del 2>/dev/null || true
  fi
done
modprobe -r mt7921u 2>/dev/null || true
modprobe -r mt792x_usb 2>/dev/null || true
modprobe -r mt7921_common 2>/dev/null || true
modprobe mt7921_common disable_clc=1
modprobe mt7921u

sleep 2
iw reg set US || true

if [[ -f /etc/systemd/system/wnicd.service ]]; then
  systemctl start wnicd.service || true
fi

echo "US regulatory domain persisted (WIRELESS_REGDOM + cfg80211.ieee80211_regdom=US)"
echo "mt7921_common.disable_clc=1 for 6 GHz"
echo "NetworkManager may manage mt7921u as a station NIC (lab ops unmanage it per session)"
iw reg get | head -n 16 || true
echo
iw phy 2>/dev/null | awk '
  /^Wiphy /{p=$2}
  /Band 4:/{print p, "has 6 GHz"}
' || true
echo
echo "Done."
