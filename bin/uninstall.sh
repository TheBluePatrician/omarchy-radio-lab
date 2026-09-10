#!/usr/bin/env bash
# Remove the Radio Lab privileged helper. Must run as root (pkexec).
# Does not delete ~/radio-lab/captures or the plugin checkout.
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "uninstall.sh must run as root (pkexec $0)" >&2
  exit 2
fi

systemctl stop wnicd.service 2>/dev/null || true
systemctl disable wnicd.service 2>/dev/null || true
rm -f /etc/systemd/system/wnicd.service
rm -f /etc/polkit-1/rules.d/49-radio-lab.rules
rm -f /usr/local/bin/wnic-ctl /usr/local/bin/wnicd
rm -f /usr/local/lib/radio-lab/wnicd
rmdir /usr/local/lib/radio-lab 2>/dev/null || true
rm -rf /run/wnicd
systemctl daemon-reload 2>/dev/null || true

echo "Radio Lab helper removed."
echo "Captures in ~/radio-lab/captures were left in place."
echo "Remove the bar widget with: omarchy plugin remove patrick.radio-lab"
