# asustor-panel

Drives the front LCD and reads the front buttons on Asustor NAS hardware running a stock
Linux distribution instead of ADM.

On these machines the display and the four buttons beside it are a microcontroller on a
serial port. No Linux driver knows it exists, which is why a NAS reinstalled with Debian,
Proxmox or TrueNAS shows ADM's power-on splash forever and the navigation buttons do
nothing. `mafredri/asustor-platform-driver` covers the LEDs, the fan, and the power and
copy buttons; it does not cover the display or those four buttons, and nothing else does
either.

Verified on an **AS6704T**. The protocol is almost certainly shared across the range: it
was recovered from ADM's `lcmd`, which is a single binary shipped for all models whose
only per-model branch is an unrelated MCU workaround for the AS1A02T. Reports from other
models are welcome.

## What it does

- Cycles status screens on the LCD: hostname and load, temperatures, zpool, root usage
- Up and down step between screens
- `asustor-panelctl` scripts the display from the shell
- Button presses run hooks, including the copy and power buttons

## Install

```sh
sudo make install
sudo systemctl enable --now asustor-panel
```

Requires Python 3 and `socat`. Configuration is optional; `/etc/asustor-panel.conf`
overrides any default in `DEFAULTS` at the top of the daemon.

## Scripting

```sh
asustor-panelctl text 0 "hello"     # write the top line, pins the display
asustor-panelctl text 1 "world"
asustor-panelctl clear
asustor-panelctl auto               # hand it back to the status screens
asustor-panelctl screen 2
asustor-panelctl off                # display off
asustor-panelctl on                 # back on; power-cycles the MCU, takes ~4s
asustor-panelctl status
```

The daemon owns the serial port and the CLI talks to it over a unix socket. That is not
indirection for its own sake: two readers on one serial line split the MCU's button
frames between them at random, so a CLI that opened the port itself would make the panel
start missing presses for no visible reason.

## Hooks

Drop an executable at `/etc/asustor-panel/hooks/<button>`, where `<button>` is one of
`up`, `down`, `back`, `enter`, `copy`, `power`. It runs detached with the button name as
its first argument.

```sh
#!/bin/sh
# /etc/asustor-panel/hooks/copy
rsync -a /mnt/usb/ /srv/backup/
```

`power` fires on a short press. On most systems logind also acts on that and will shut
the machine down; set `HandlePowerKey=ignore` in `logind.conf` if the hook should own it.

## The protocol

Everything below was recovered by disassembling ADM's `lcmd` and verified against the
hardware. No ADM code is used or included.

### Transport

`/dev/ttyS1`, **115200 8N1 raw**, no flow control. From the single `tcsetattr` in `lcmd`:
`c_cflag = 0x18b2`, which is `CS8|CREAD|CLOCAL|B115200`.

The baud must be set in `c_cflag`. On Linux the speed lives in that field's `CBAUD` bits
and `c_ispeed`/`c_ospeed` are consulted only for `BOTHER`, so a cflag assembled without
it is `B0`, which hangs up the line.

### Frames

```
[0]        0xf0    host to MCU        (0xf1 = MCU to host)
[1]        len
[2]        command
[3..]      arguments
[last]     checksum, the 8-bit sum of every preceding byte
```

Two layouts, chosen on `len + 4 > 0x15`:

| layout | total | checksum at | summed over |
| ------ | ----- | ----------- | ----------- |
| short  | `len + 4` | `len + 3` | `[0 .. len+2]` |
| long   | 22    | 21 (fixed)  | `[0 .. 20]` |

A frame with a wrong checksum, a wrong layout or a wrong baud is **ignored silently**: no
reply, no error. Use the reply as the oracle when exploring.

### Commands

| frame | does |
| ----- | ---- |
| `f0 01 13 01 05` | init; the MCU answers `f1 01 13 00 05` |
| `f0 12 27 <line> <attr> <16 chars> <cksum>` | write a line, `<line>` is 0 or 1 |
| `f0 01 11 00 03` | display OFF |

`0x12`, `0x20`, `0x21`, `0x22`, `0x23`, `0x25` and `0x26` are also accepted and
acknowledged; their effects are not yet identified.

**There is no known display-on command.** `0x11` with arg 1 is rejected, and text written
while the display is off lands in a buffer nobody can see. The only way back is to cut
the panel's power rail, which on this hardware is the `power:lcd` LED the platform driver
exposes. The MCU then reboots into its ROM splash and accepts text again.

### Buttons

```
f0 01 80 <id> <cksum>
```

`01` up, `02` down, `03` back, `04` enter. The MCU sends these unsolicited; it never
reports anything else on its own, so a port that stays quiet is not evidence of absence.

The other two front buttons are not the MCU's, which is the main reason this took so long
to find. Copy is a Super I/O GPIO behind the `asustor-keys` input device (`KEY_COPY`,
133); power is ACPI (`KEY_POWER`, 116). Three mechanisms, six buttons.

Input device numbering is **not stable across reboots**: `asustor-keys` was `event9`
before a reboot and `event2` after it on the same machine. Match on
`/sys/class/input/event*/device/name`.

### Recovering it yourself

The ADM image is still on the internal eMMC of any of these machines reinstalled onto a
different disk, because installers write to the SSD or NVMe and never touch `mmcblk0`:

```sh
mount -o ro /dev/mmcblk0p2 /mnt/adm
xzcat /mnt/adm/initramfs | cpio -idm 'usr/sbin/lcmd' 'usr/lib/libndal*'
objdump -d usr/sbin/lcmd
```

`lcmd` has exactly one `write()` call. The function containing it builds the frame and
computes the checksum, and the twelve call sites give the command table.

## Licence

GPL-2.0-or-later.
