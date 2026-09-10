#!/usr/bin/env bash
# Install the Radio Lab privileged helper. Must run as root (pkexec).
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "install.sh must run as root (pkexec $0)" >&2
  exit 2
fi

SRC="$(cd "$(dirname "$0")" && pwd)"
ALLOW_UID="${PKEXEC_UID:-${SUDO_UID:-}}"
if [[ -z ${ALLOW_UID} ]]; then
  echo "install.sh: cannot determine installing user (PKEXEC_UID/SUDO_UID unset)" >&2
  exit 2
fi
ALLOW_USER="$(id -un "${ALLOW_UID}" 2>/dev/null || true)"
if [[ -z ${ALLOW_USER} ]]; then
  echo "install.sh: no user for uid ${ALLOW_UID}" >&2
  exit 2
fi
ALLOW_HOME="$(getent passwd "${ALLOW_UID}" | cut -d: -f6)"
if [[ -z ${ALLOW_HOME} ]]; then
  echo "install.sh: no home directory for uid ${ALLOW_UID}" >&2
  exit 2
fi
CAPTURE_DIR="${ALLOW_HOME}/radio-lab/captures"

install -d -m 0755 /usr/local/lib/radio-lab
install -m 0755 "${SRC}/wnicd" /usr/local/lib/radio-lab/wnicd
install -d -m 0755 /usr/local/bin
ln -sfn /usr/local/lib/radio-lab/wnicd /usr/local/bin/wnic-ctl
ln -sfn /usr/local/lib/radio-lab/wnicd /usr/local/bin/wnicd

install -d -m 0755 -o "${ALLOW_UID}" -g "${ALLOW_UID}" "${ALLOW_HOME}/radio-lab"
install -d -m 0755 -o "${ALLOW_UID}" -g "${ALLOW_UID}" "${CAPTURE_DIR}"

cat > /etc/systemd/system/wnicd.service <<EOF
[Unit]
Description=Radio Lab multi-WNIC monitor and capture helper
After=network-pre.target NetworkManager.service
Wants=NetworkManager.service

[Service]
Type=simple
ExecStart=/usr/local/lib/radio-lab/wnicd daemon --foreground --allow-uid ${ALLOW_UID} --capture-dir "${CAPTURE_DIR}"
Restart=on-failure
RestartSec=2
TimeoutStopSec=10
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF

install -d /etc/polkit-1/rules.d
cat > /etc/polkit-1/rules.d/49-radio-lab.rules <<EOF
// Allow the installing user to start/stop/restart the Radio Lab helper.
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.systemd1.manage-units" &&
        subject.user == "${ALLOW_USER}") {
        var unit = action.lookup("unit");
        var verb = action.lookup("verb");
        if (unit == "wnicd.service" &&
            (verb == "start" || verb == "stop" || verb == "restart" || verb == "reload")) {
            return polkit.Result.YES;
        }
    }
});
EOF

if command -v pacman >/dev/null 2>&1; then
  pacman -S --noconfirm --needed iw >/dev/null 2>&1 || true
fi

systemctl daemon-reload
systemctl enable wnicd.service
systemctl restart wnicd.service

echo "Radio Lab helper installed for ${ALLOW_USER} (uid ${ALLOW_UID})"
echo "Captures: ${CAPTURE_DIR}"
systemctl --no-pager --full status wnicd.service | head -n 12 || true
