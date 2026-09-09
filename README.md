# Radio Lab

Omarchy bar widget for a multi-WNIC wireless lab. Inventory every nl80211
radio, park a lab NIC in monitor, scan bands into AIR, and write pcaps.

## Install on another Omarchy PC

```
omarchy plugin add https://github.com/TheBluePatrician/omarchy-radio-lab.git --enable
```

That clones the plugin into `~/.config/omarchy/plugins/patrick.radio-lab`
and enables the bar widget. Then open the panel and click **Install** (or
run the helper installer once):

```
pkexec ~/.config/omarchy/plugins/patrick.radio-lab/bin/install.sh
```

Update later with `omarchy plugin update patrick.radio-lab`.

The cloned `patrick.network` widget stays in charge of joining Wi-Fi and
picking which radio is the internet path (INTERFACE pills). Radio Lab is
the extra radios: park a NIC in monitor, scan, and capture. **Restore
Wi-Fi** hands a lab NIC back to NetworkManager so the network panel can
use it; it is not the internet-radio selector.

## Bar

The radar icon sits in the top-right cluster, next to Bluetooth / Wi-Fi.

- Left click: open the panel
- Right click: refresh inventory
- Middle click: open `~/radio-lab/captures`

Badge = number of WNICs. The icon pulses while a capture is running.

## Helper

Monitor mode, channel changes, scan, and capture need a small root
helper (`wnicd`). The panel's **Install** / **Start** button runs that
once via polkit.

```
pkexec ~/.config/omarchy/plugins/patrick.radio-lab/bin/install.sh
```

That installs `/usr/local/lib/radio-lab/wnicd`, a `wnicd.service`, and
`wnic-ctl` on PATH.

## CLI

```
wnic-ctl --pretty                 # inventory (no root)
wnic-ctl monitor-on phy1 --channel 6
wnic-ctl scan-start phy1 --band 2.4 --channels 1,2,3,4,5,6,7,8,9,10,11
wnic-ctl capture-start phy1
wnic-ctl capture-stop phy1
wnic-ctl monitor-off phy1
wnic-ctl disable phy1
wnic-ctl enable phy1
```

`monitor-on` converts that phy's station iface to type monitor in place (`ip a` shows `link/ieee802.11/radiotap`, no IPv4). Click **Monitor** again, or `monitor-off`, to leave monitor without joining Wi-Fi. **Disable** takes the NIC down; click it again (`enable`) to bring the iface back up. **Restore Wi-Fi** remanages NetworkManager and reconnects that NIC. Pick which radio provides internet in the network panel INTERFACE row.

**Scan** walks the selected band with `iw scan` and fills AIR. 6 GHz and DFS are listen-only (`no IR`). **Monitor** parks a channel for radiotap capture; it does not hop.

On a monitor NIC, captures are classic pcap with radiotap
(`DLT_IEEE802_11_RADIO`) and open in Wireshark.

The PCIe RTL8821CE cannot park in monitor mode. Capture on that radio is an
`iw scan` survey: a `.jsonl` log of heard APs plus a `.pcap` of **beacons
rebuilt from those scan results**. That pcap is not a live 802.11 listen.
Use the USB lab NIC for a parked radiotap capture.

## Keys in the panel

| Key | Action |
|-----|--------|
| `i` | install / start helper |
| `m` | monitor on/off for the selected radio |
| `d` | disable / enable the selected radio |
| `c` | capture on/off |
| `p` | scan / stop scan on the focused band |
| `w` | restore Wi-Fi on the selected radio |
| `o` | open capture folder |
| `r` | refresh |

Passive monitoring only — no injection, deauth, or cracking.
