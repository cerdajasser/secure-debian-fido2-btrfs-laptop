---
title: "Secure Debian Laptop Setup: FIDO2 Keys, LUKS2, Btrfs, Snapper, dracut, and GRUB Rollback"
subtitle: A field-tested anon-howtos rebuild guide for a secure, recoverable Debian laptop.
description: A technical walkthrough for building a secure and recoverable Debian laptop using LUKS2, LVM, Btrfs, Snapper, FIDO2 security keys, PAM U2F, dracut FIDO2 disk unlock, grub-btrfs rollback entries, zsh, Kando, and skwd-wall.
author: anon-howtos
status: final draft
created: 2026-06-13
updated: 2026-06-14
tags:
  - Debian
  - Linux
  - FIDO2
  - YubiKey
  - LUKS2
  - Btrfs
  - Snapper
  - GRUB
  - dracut
  - Hyprland
  - zsh
  - Recovery
  - Security
  - anon-howtos
---

# Secure Debian Laptop Setup: FIDO2 Keys, LUKS2, Btrfs, Snapper, dracut, and GRUB Rollback


> Audience: technical Linux users who are comfortable editing PAM files, rebuilding initramfs images, reading GRUB config, testing from a TTY, and keeping a live USB nearby.

A secure Linux laptop is not finished when disk encryption works. It is finished when you can update it, break it, unlock it with hardware-backed auth, fall back to a passphrase, and recover from GRUB without panic.

This is the rebuild guide I wish I had at the beginning.
This is a rebuild guide for a secure Debian laptop setup that took a few days of trial, error, and recovery testing. The result is not just "encrypted Debian." The result is a laptop that is encrypted, hardware-key aware, snapshot-backed, boot-menu recoverable, and still practical as a daily driver.

The final system uses:

- Debian Testing / Sid-style Debian base.
- LUKS2 full-disk encryption for the Linux system.
- LVM inside LUKS for root, home, and swap.
- Btrfs for root and home.
- Snapper snapshots for root.
- apt pre/post snapshots.
- FIDO2 security keys for sudo, login, lock screen, TTY, and disk unlock.
- dracut for FIDO2-aware early boot.
- GRUB fallback entries.
- grub-btrfs snapshot boot menu entries.
- A safer systemd path/timer replacement for flaky grub-btrfs auto-refresh behavior.
- zsh, Fastfetch, and some Hyprland desktop polish.
- Optional Kando and skwd-wall / Wallpaper Engine setup.

The most important theme is this:

```text
Secure is good. Recoverable is better.
```

---

## Glossary

| Term | Meaning in this setup |
|---|---|
| **FIDO2** | A hardware-backed authentication standard. Here it is used both for Linux PAM authentication after boot and for LUKS2 disk unlock before boot. |
| **Security key / FIDO key / YubiKey** | A physical USB/NFC authenticator. This guide uses two keys: one daily key and one backup key. The examples say "security key" generically, but YubiKey-style devices were used. |
| **PIN + touch** | FIDO2 commonly requires a local PIN plus physical touch. The PIN proves local knowledge. Touch proves physical presence. |
| **PAM** | Pluggable Authentication Modules. PAM controls authentication for sudo, SDDM, lock screens, TTY logins, and `su`. |
| **pam_u2f** | The PAM module used to authenticate Linux sessions with FIDO/U2F keys. |
| **`sufficient` PAM rule** | Lets the FIDO key authenticate successfully but still allows password fallback. This is safer than `required` during initial setup. |
| **LUKS2** | Linux Unified Key Setup version 2. The encrypted disk metadata format used here. FIDO2 enrollment with `systemd-cryptenroll` requires LUKS2. |
| **crypttab** | `/etc/crypttab` tells early boot how to unlock encrypted volumes. For the dracut/FIDO2 path, the key option is `fido2-device=auto`. |
| **initramfs** | The temporary early boot filesystem that loads before the real root filesystem. It must be able to unlock LUKS and activate LVM. |
| **initramfs-tools** | Debian's traditional initramfs generator. It worked for normal passphrase unlock but did not handle the `fido2-device=auto` path in this build. |
| **dracut** | Alternative initramfs generator used to build a systemd/FIDO2-capable early boot image. |
| **Btrfs** | Copy-on-write Linux filesystem used for root snapshots and rollback support. |
| **Subvolume** | A Btrfs filesystem tree that can be mounted and snapshotted separately. Root used `@rootfs`. |
| **Snapper** | Snapshot manager used for manual, timeline, boot, and apt pre/post snapshots. |
| **grub-btrfs** | Tool that generates GRUB menu entries for booting Btrfs snapshots. |
| **GRUB** | Bootloader menu. It chooses the default dracut FIDO2 boot entry, normal Debian fallback, Windows, firmware setup, and Btrfs snapshots. |
| **LVM** | Logical Volume Manager. Used inside the encrypted LUKS container to split storage into root, home, and swap. |
| **Fallback boot** | A known-good normal Debian boot entry left available in GRUB in case the custom dracut/FIDO2 path fails. |
| **Fallback auth** | Password or LUKS passphrase authentication kept available in case the security key is missing or fails. |
| **Golden snapshot** | A named Snapper checkpoint after the system reaches a known-good state. |
| **Kando** | Optional cross-platform pie menu used as desktop polish. |
| **skwd-wall** | Optional wallpaper selector / Wallpaper Engine-style desktop polish layer used later in the setup. |

---

## Table of contents

- [Threat model](#threat-model)
- [Final architecture](#final-architecture)
- [Design decisions and tradeoffs](#design-decisions-and-tradeoffs)
- [Debian install: storage layout](#debian-install-storage-layout)
- [First boot verification](#first-boot-verification)
- [Base package set](#base-package-set)
- [Snapper setup](#snapper-setup)
- [PAM U2F setup for two security keys](#pam-u2f-setup-for-two-security-keys)
- [sudo, SDDM, lock screen, TTY, and su](#sudo-sddm-lock-screen-tty-and-su)
- [FIDO2 LUKS unlock: what failed first](#fido2-luks-unlock-what-failed-first)
- [FIDO2 LUKS unlock with dracut](#fido2-luks-unlock-with-dracut)
- [Custom GRUB default entry](#custom-grub-default-entry)
- [Kernel update helper script](#kernel-update-helper-script)
- [grub-btrfs snapshot menu](#grub-btrfs-snapshot-menu)
- [Safer grub-btrfs refresh service](#safer-grub-btrfs-refresh-service)
- [Final script index](#final-script-index)
- [Final configuration appendix](#final-configuration-appendix)
- [Controlled recovery behavior](#controlled-recovery-behavior)
- [zsh and shell setup](#zsh-and-shell-setup)
- [Optional desktop polish: Kando and skwd-wall](#optional-desktop-polish-kando-and-skwd-wall)
- [App list for a fresh Debian workstation](#app-list-for-a-fresh-debian-workstation)
- [What worked and what did not](#what-worked-and-what-did-not)
- [Final checklist](#final-checklist)
- [References](#references)

---

## Threat model

This is a practical secure laptop build, not a formal compliance baseline.

The goals:

- If the laptop is powered off, the Linux system is encrypted.
- If the laptop is stolen, the attacker still needs either the LUKS passphrase or a FIDO2 key plus its PIN.
- If someone gets access to the running desktop, privileged actions still require password or FIDO-backed authentication.
- If Debian Testing/Sid packages break the system, snapshots and fallback boot entries exist.
- If the custom dracut FIDO2 boot path fails, normal Debian passphrase boot remains available.

Non-goals:

- Do not make boot impossible without a security key.
- Do not remove the LUKS passphrase.
- Do not remove password fallback from PAM while testing.
- Do not rely on one security key.
- Do not replace normal Debian boot entries until the custom path has been tested repeatedly.

The core rule:

```text
Hardware key first. Password/passphrase fallback always.
```

---

## Final architecture

```text
Power on
  -> UEFI
  -> GRUB
     -> default: dracut FIDO2 LUKS entry
        -> FIDO2 PIN prompt
        -> security key touch
        -> LUKS2 unlock
        -> LVM activation
        -> Btrfs root subvolume mount
        -> Debian boots
     -> fallback: normal Debian initramfs-tools entry
        -> normal LUKS passphrase unlock
     -> submenu: Debian GNU/Linux snapshots
        -> grub-btrfs generated Snapper entries
```

Working features in the final build:

- Two FIDO2 keys enrolled.
- sudo accepts security key touch or password fallback.
- SDDM accepts security key touch or password fallback.
- Daily login is faster in practice: insert key, enter the PIN where prompted, touch the button, and move on.
- hyprlock accepts security key touch or password fallback.
- TTY login and `su` can be configured with the same PAM U2F method.
- LUKS2 disk unlock works with both keys through dracut.
- Removing the key falls back to the normal LUKS passphrase prompt.
- GRUB defaults to a custom dracut FIDO2 entry.
- Normal Debian boot remains in the menu.
- Snapper snapshots appear in GRUB through grub-btrfs.
- grub-btrfs refresh is handled by a safer custom systemd path/timer wrapper.

---

## Design decisions and tradeoffs

### Decision 1: keep fallback everywhere

The setup deliberately avoids key-only authentication. Key-only setups are exciting until a key breaks, a USB controller acts up, an initramfs image is missing a module, or a PAM edit is wrong.

For PAM, the safe rule is:

```text
auth sufficient pam_u2f.so cue authfile=/etc/Yubico/u2f_keys
```

Not this during early setup:

```text
auth required pam_u2f.so
```

`sufficient` lets the key authenticate immediately. If the key is missing or fails, the rest of the PAM stack continues and password fallback still works.

### Decision 2: enroll two keys before calling it done

A single key is a single point of failure. The daily key and backup key were enrolled for:

- PAM U2F mapping.
- sudo.
- SDDM.
- lock screen.
- TTY login and `su` if enabled.
- LUKS2 FIDO2 disk unlock.

A setup is not complete until the backup key is tested.

### Decision 3: LUKS2 first, then LVM, then Btrfs

The storage stack was:

```text
LUKS2 -> LVM -> Btrfs root / Btrfs home / swap
```

That keeps one encryption boundary around the Linux system, while still allowing separate logical volumes. Btrfs on root gives Snapper and grub-btrfs a clean target.

### Decision 4: separate Btrfs `/home`

Root rollback should not roll back user documents, browser profiles, game libraries, local projects, or media. Using a separate Btrfs filesystem for `/home` keeps OS rollback separate from user data.

Tradeoff: root Snapper snapshots do not replace a proper `/home` backup strategy. Use restic, borg, rclone, Syncthing, or external backups for home data.

### Decision 5: Snapper instead of Timeshift

Snapper integrates cleanly with apt pre/post snapshots, timeline snapshots, boot snapshots, and grub-btrfs. The snapshot descriptions also become useful labels in GRUB.

Useful examples:

```text
Before YubiKey PAM setup
Before dracut FIDO2 LUKS setup
Golden state YubiKey dracut LUKS and grub-btrfs working
```

When you are recovering from a broken system, readable snapshot names matter.

### Decision 6: dracut instead of fighting initramfs-tools

The first attempt added `fido2-device=auto` to `/etc/crypttab` and rebuilt with Debian's normal initramfs-tools path. The warning was:

```text
cryptsetup: WARNING: nvme1n1p3_crypt: ignoring unknown option 'fido2-device'
```

That meant the FIDO2 LUKS token was enrolled, but the early boot path was not using systemd/FIDO2 handling. The fix was to build a dracut image and boot that as a separate GRUB entry.

### Decision 7: test dracut manually before making it default

The dracut image was first booted manually by editing the GRUB `initrd` line. Only after that worked with:

- security key #1,
- security key #2,
- and normal passphrase fallback,

was a custom GRUB entry created.

### Decision 8: put the custom entry before Debian's normal entries

The custom entry was placed in:

```text
/etc/grub.d/09_dracut_fido2
```

Debian's normal kernel entries come from:

```text
/etc/grub.d/10_linux
```

Putting the custom entry at `09_` makes it first. Then this is simple:

```text
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=5
```

### Decision 9: leave normal Debian boot as fallback

The normal Debian entry still exists. That is intentional. If the custom dracut entry breaks, boot the normal Debian entry and use the normal LUKS passphrase.

### Decision 10: use a larger `/boot` next time

A 944 MiB `/boot` worked but was tight. A dracut image was about 313 MiB. Keeping multiple kernels, normal initramfs images, dracut images, and backups fills `/boot` fast.

Next install:

```text
/boot = 2 GiB minimum
/boot = 4 GiB if experimenting with kernels/initrds
```

### Decision 11: replace the flaky grub-btrfs daemon

`grub-btrfsd` ran and watched `/.snapshots`, but it did not reliably refresh during testing. Manual generation worked. The replacement was a custom systemd path/timer service that runs a locked `update-grub` wrapper and avoids overlapping with `os-prober` or another GRUB generation process.

---

## Debian install: storage layout

### Recommended partition layout

```text
Disk: /dev/nvme1n1

/dev/nvme1n1p1   EFI System Partition   FAT32   1 GiB      /boot/efi
/dev/nvme1n1p2   Linux /boot            ext4    2-4 GiB    /boot
/dev/nvme1n1p3   LUKS2 container        crypto  rest       encrypted Linux system
```

Inside LUKS2:

```text
/dev/mapper/nvme1n1p3_crypt
  -> LVM volume group
     -> root LV   Btrfs   /
     -> home LV   Btrfs   /home
     -> swap LV   swap
```

Example final layout:

```text
nvme1n1
├─nvme1n1p1            vfat        /boot/efi
├─nvme1n1p2            ext4        /boot
└─nvme1n1p3            crypto_LUKS LUKS2
  └─nvme1n1p3_crypt    LVM2
    ├─ANONHOWTO--Laptop--vg-root  btrfs  /
    ├─ANONHOWTO--Laptop--vg-home  btrfs  /home
    └─ANONHOWTO--Laptop--vg-swap  swap
```

### Debian installer flow

1. Manual partitioning.
2. Create EFI partition.
3. Create separate ext4 `/boot` partition.
4. Create encrypted LUKS partition for the rest of the disk.
5. Put LVM inside the encrypted partition.
6. Create root, home, and swap logical volumes.
7. Format root as Btrfs.
8. Format home as Btrfs.
9. Finish install.
10. After first boot, verify mounts and subvolumes.

### Expected Btrfs layout

Root was mounted from a Btrfs subvolume:

```text
/dev/mapper/ANONHOWTO--Laptop--vg-root[/@rootfs] /
```

Snapper snapshots lived at:

```text
/.snapshots
```

Subvolumes looked like:

```text
ID 256 path @rootfs
ID 257 path .snapshots
ID ... path .snapshots/<number>/snapshot
```

`grub-btrfs` generated snapshot boot entries like:

```text
@rootfs/.snapshots/442/snapshot
```

---

## First boot verification

Before adding security layers, verify the base system.

```bash
lsblk -f
cat /etc/crypttab
findmnt -no SOURCE,FSTYPE,OPTIONS /
findmnt -no SOURCE,FSTYPE,OPTIONS /home
sudo btrfs subvolume list /
sudo cryptsetup luksDump /dev/nvme1n1p3 | grep -E "Version|Keyslots|Tokens"
```

Expected:

```text
LUKS version: 2
root on Btrfs
home on Btrfs
/boot separate ext4
/boot/efi separate FAT32
```

Early checkpoint:

```bash
sudo snapper -c root create --description "Base encrypted Debian Btrfs install verified"
```

---

## Base package set

Install base tools:

```bash
sudo apt install -y \
  yubikey-manager libpam-u2f pamu2fcfg \
  cryptsetup cryptsetup-initramfs systemd-cryptsetup \
  fido2-tools libfido2-1 \
  dracut-core \
  btrfs-progs snapper inotify-tools \
  lvm2 os-prober
```

Useful checks:

```bash
ykman info
systemd-cryptenroll --fido2-device=list
```

---

## Snapper setup

Verify root Snapper config:

```bash
sudo snapper -c root list
```

Enable timers:

```bash
sudo systemctl enable --now snapper-timeline.timer
sudo systemctl enable --now snapper-cleanup.timer
sudo systemctl enable --now snapper-boot.timer
```

Create a manual checkpoint:

```bash
sudo snapper -c root create --description "Snapper root snapshots working"
```

### apt pre/post snapshots

The reliable approach was helper scripts, not fragile inline apt hook quoting.

Create the pre hook:

```bash
sudo tee /usr/local/sbin/snapper-apt-pre >/dev/null <<'EOF'
#!/bin/bash
set -e
if command -v snapper >/dev/null 2>&1; then
  snapper -c root create \
    --type pre \
    --print-number \
    --description "apt package operation" \
    --userdata "important=yes" \
    > /run/snapper-apt-pre-number || true
fi
EOF

sudo chmod +x /usr/local/sbin/snapper-apt-pre
```

Create the post hook:

```bash
sudo tee /usr/local/sbin/snapper-apt-post >/dev/null <<'EOF'
#!/bin/bash
set -e
if command -v snapper >/dev/null 2>&1 && [ -r /run/snapper-apt-pre-number ]; then
  pre="$(cat /run/snapper-apt-pre-number)"
  if [[ "$pre" =~ ^[0-9]+$ ]]; then
    snapper -c root create \
      --type post \
      --pre-number "$pre" \
      --description "apt package operation finished" \
      --userdata "important=yes" \
      || true
  fi
  rm -f /run/snapper-apt-pre-number
fi
EOF

sudo chmod +x /usr/local/sbin/snapper-apt-post
```

Create apt hook:

```bash
sudo tee /etc/apt/apt.conf.d/80snapper >/dev/null <<'EOF'
DPkg::Pre-Invoke { "/usr/local/sbin/snapper-apt-pre"; };
DPkg::Post-Invoke { "/usr/local/sbin/snapper-apt-post"; };
EOF
```

Test:

```bash
sudo apt install --reinstall -y bash
sudo snapper -c root list | tail -12
```

---

## PAM U2F setup for two security keys

Create mapping directory:

```bash
mkdir -p ~/.config/Yubico
chmod 700 ~/.config/Yubico
```

Register key #1:

```bash
pamu2fcfg -u "$USER" > ~/.config/Yubico/u2f_keys
chmod 600 ~/.config/Yubico/u2f_keys
```

Register key #2:

```bash
pamu2fcfg -n >> ~/.config/Yubico/u2f_keys
```

Copy mapping to a system path for login managers and lock screens:

```bash
sudo mkdir -p /etc/Yubico
sudo cp ~/.config/Yubico/u2f_keys /etc/Yubico/u2f_keys
sudo chown root:root /etc/Yubico/u2f_keys
sudo chmod 644 /etc/Yubico/u2f_keys
```

Check:

```bash
cat /etc/Yubico/u2f_keys
```

---

## sudo, SDDM, lock screen, TTY, and su

### sudo

Back up:

```bash
sudo cp /etc/pam.d/sudo /etc/pam.d/sudo.bak.$(date +%F-%H%M%S)
```

Add near the top of `/etc/pam.d/sudo`:

```text
auth sufficient pam_u2f.so cue authfile=/etc/Yubico/u2f_keys
```

Test in a new terminal:

```bash
sudo -k
sudo true
```

Test both keys, then unplug keys and test password fallback.

### SDDM login

Back up:

```bash
sudo cp /etc/pam.d/sddm /etc/pam.d/sddm.bak.$(date +%F-%H%M%S)
```

Add near the top of `/etc/pam.d/sddm`:

```text
auth sufficient pam_u2f.so cue authfile=/etc/Yubico/u2f_keys
```

Test before logging out:

```bash
sudo apt install -y pamtester
pamtester sddm "$USER" authenticate
```

In SDDM, there may be no visible prompt. The key may simply light up. Touch it.

This is also one of the nicest quality-of-life improvements: with the key ready, login feels faster than typing the full password every time. PIN, touch, done.

### hyprlock / lock screen

The lock screen was a small trap. The desktop hints referenced `hyprlock`, but the actual lock script was using `loginctl lock-session`, so editing `/etc/pam.d/swaylock` was not enough.

Final PAM file:

```bash
sudo tee /etc/pam.d/hyprlock >/dev/null <<'EOF'
auth sufficient pam_u2f.so cue authfile=/etc/Yubico/u2f_keys
@include common-auth
EOF
```

Final Hyprland lock script change:

```bash
nano ~/.config/hypr/scripts/LockScreen.sh
```

Use `hyprlock` directly:

```bash
pidof hyprlock || hyprlock -q
# loginctl lock-session
```

Test PAM first:

```bash
pamtester hyprlock "$USER" authenticate
```

Then lock the session and test both key unlock and password fallback.


The setup initially had `/etc/pam.d/swaylock`, but the actual Hyprland lock script used `loginctl lock-session` and referenced hyprlock. The fix was to make the lock script call hyprlock directly and create a PAM file for hyprlock.

Create `/etc/pam.d/hyprlock`:

```bash
sudo tee /etc/pam.d/hyprlock >/dev/null <<'EOF'
auth sufficient pam_u2f.so cue authfile=/etc/Yubico/u2f_keys
@include common-auth
EOF
```

Test:

```bash
pamtester hyprlock "$USER" authenticate
```

Example Hyprland lock script change:

```bash
pidof hyprlock || hyprlock -q
# loginctl lock-session
```

### TTY login

Back up:

```bash
sudo cp /etc/pam.d/login /etc/pam.d/login.bak.$(date +%F-%H%M%S)
```

Add near the top of `/etc/pam.d/login`:

```text
auth sufficient pam_u2f.so cue authfile=/etc/Yubico/u2f_keys
```

Test:

```bash
pamtester login "$USER" authenticate
```

### su

Back up:

```bash
sudo cp /etc/pam.d/su /etc/pam.d/su.bak.$(date +%F-%H%M%S)
```

Add near the top of `/etc/pam.d/su`:

```text
auth sufficient pam_u2f.so cue authfile=/etc/Yubico/u2f_keys
```

Important: plain `su` means "switch to root" and may fail if the root account has no password or no root mapping. Use `sudo -i` or `sudo su` for root shells in this setup.

---

## FIDO2 LUKS unlock: what failed first

FIDO2 tokens were enrolled with `systemd-cryptenroll`, then `/etc/crypttab` was updated with:

```text
fido2-device=auto
```

But Debian's initramfs-tools path warned:

```text
cryptsetup: WARNING: nvme1n1p3_crypt: ignoring unknown option 'fido2-device'
```

That meant the LUKS2 token existed, but early boot did not use it. The fix was dracut.

---

## FIDO2 LUKS unlock with dracut

### Add recovery key first

```bash
sudo systemd-cryptenroll --recovery-key /dev/nvme1n1p3
```

Save it offline.

### Enroll both security keys

Key #1:

```bash
sudo systemd-cryptenroll \
  --fido2-device=auto \
  --fido2-with-client-pin=yes \
  /dev/nvme1n1p3
```

Key #2:

```bash
sudo systemd-cryptenroll \
  --fido2-device=auto \
  --fido2-with-client-pin=yes \
  /dev/nvme1n1p3
```

Check:

```bash
sudo systemd-cryptenroll /dev/nvme1n1p3
sudo cryptsetup luksDump /dev/nvme1n1p3 | sed -n '/Tokens:/,/Digests:/p'
```

### crypttab for dracut

Final line:

```text
nvme1n1p3_crypt UUID=<luks-uuid> none luks,discard,x-initrd.attach,fido2-device=auto
```

Do not use `update-initramfs` to test this path. Build dracut images instead.

### dracut config

```bash
sudo mkdir -p /etc/dracut.conf.d

sudo tee /etc/dracut.conf.d/10-anonhowto-luks-fido2.conf >/dev/null <<'EOF'
hostonly="yes"
hostonly_mode="strict"
hostonly_cmdline="yes"

install_items+=" /etc/crypttab "
install_items+=" /usr/bin/fido2-token "
install_items+=" /usr/lib/udev/rules.d/60-fido-id.rules "
install_items+=" /usr/lib/udev/fido_id "
EOF
```

### Build to `/tmp` first

This avoids filling `/boot` before knowing the image size.

```bash
KVER="$(uname -r)"

sudo dracut --force --hostonly --compress "xz -T0 --check=crc32" \
  "/tmp/initrd.img-${KVER}-dracut-passphrase" \
  "$KVER"

ls -lh "/tmp/initrd.img-${KVER}-dracut-passphrase"
```

Copy only after confirming space:

```bash
sudo cp -v "/tmp/initrd.img-${KVER}-dracut-passphrase" \
  "/boot/initrd.img-${KVER}-dracut-passphrase"
```

### One-time GRUB test

At GRUB:

1. Highlight normal Debian entry.
2. Press `e`.
3. Change the `initrd` line to the dracut image:

```text
initrd /initrd.img-<kernel>-dracut-passphrase
```

4. Add to the `linux` line:

```text
rd.auto=1
```

5. Boot with `Ctrl+x` or `F10`.

Expected behavior:

- With the security key inserted, boot asks for the FIDO2 token PIN. Enter the FIDO2 PIN, then touch the key.
- With the key removed, boot falls back to the normal LUKS passphrase prompt.

---

## Custom GRUB default entry

Once dracut FIDO2 boot worked, create `/etc/grub.d/09_dracut_fido2`:

```bash
sudo tee /etc/grub.d/09_dracut_fido2 >/dev/null <<'EOF'
#!/bin/sh
exec tail -n +3 $0

menuentry 'Debian GNU/Linux - dracut FIDO2 LUKS default' {
    search --no-floppy --fs-uuid --set=root <boot-fs-uuid>
    linux /vmlinuz-<kernel> root=/dev/mapper/ANONHOWTO--Laptop--vg-root ro rootflags=subvol=@rootfs quiet rd.auto=1
    initrd /initrd.img-<kernel>-dracut-passphrase
}
EOF

sudo chmod +x /etc/grub.d/09_dracut_fido2
```

Set `/etc/default/grub`:

```text
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=5
```

Then:

```bash
sudo update-grub
```

Verify:

```bash
sudo grep -A5 -B2 "dracut FIDO2" /boot/grub/grub.cfg
```

After boot:

```bash
cat /proc/cmdline | tr ' ' '\n' | grep -E 'rd.auto|root=|BOOT_IMAGE'
```

Expected:

```text
BOOT_IMAGE=/vmlinuz-<kernel>
root=/dev/mapper/ANONHOWTO--Laptop--vg-root
rd.auto=1
```

---

## Kernel update helper script

The custom GRUB entry points to a specific kernel and initrd. After a future kernel upgrade, Debian will generate normal entries for the new kernel, but the FIDO2/dracut default entry needs its matching dracut initrd rebuilt and the `09_dracut_fido2` GRUB snippet rewritten.

The final helper script below does that repeatably.

It intentionally:

- finds the newest installed kernel unless one is passed as an argument;
- confirms `/etc/crypttab` contains `fido2-device=auto`;
- writes dracut output to `/var/tmp` first;
- checks `/boot` space before copying;
- overwrites the known working `dracut-passphrase` initrd slot instead of creating endless new initrds;
- rewrites `/etc/grub.d/09_dracut_fido2`;
- forces `GRUB_DEFAULT=0` with a visible fallback menu;
- keeps normal Debian entries available as fallback.

> Naming note: the initrd suffix stayed `dracut-passphrase` because that was the originally tested working filename. Even though it now supports FIDO2, keeping the name avoided creating a second 300+ MB initrd on a small `/boot` partition.

Install the helper:

```bash
sudo tee /usr/local/sbin/update-dracut-fido2-grub >/dev/null <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

TITLE="Debian GNU/Linux - dracut FIDO2 LUKS default"
GRUB_SNIPPET="/etc/grub.d/09_dracut_fido2"
LUKS_DEVICE="/dev/nvme1n1p3"
DRACUT_SUFFIX="dracut-passphrase"
MIN_BOOT_FREE_MIB=60

die() {
  echo "ERROR: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

[ "$(id -u)" -eq 0 ] || die "Run with sudo."

need_cmd dracut
need_cmd update-grub
need_cmd find
need_cmd sort
need_cmd sed
need_cmd grep
need_cmd awk
need_cmd stat
need_cmd df
need_cmd python3

[ -x /usr/sbin/grub-probe ] || die "Missing /usr/sbin/grub-probe"
[ -e "$LUKS_DEVICE" ] || die "Missing LUKS device: $LUKS_DEVICE"
[ -f /etc/crypttab ] || die "Missing /etc/crypttab"

echo "==> Checking /etc/crypttab..."
if ! awk '
  $0 !~ /^[[:space:]]*#/ &&
  $1 == "nvme1n1p3_crypt" &&
  $0 ~ /(^|,)fido2-device=auto(,|$)/ { found=1 }
  END { exit(found ? 0 : 1) }
' /etc/crypttab; then
  echo "Current /etc/crypttab:" >&2
  sed -n '1,20p' /etc/crypttab >&2
  die "/etc/crypttab does not contain fido2-device=auto for nvme1n1p3_crypt."
fi

echo "==> Ensuring dracut FIDO2 config exists..."
mkdir -p /etc/dracut.conf.d

cat > /etc/dracut.conf.d/10-anonhowto-luks-fido2.conf <<'DRACUT_CONF'
hostonly="yes"
hostonly_mode="strict"
hostonly_cmdline="yes"

install_items+=" /etc/crypttab "
install_items+=" /usr/bin/fido2-token "
install_items+=" /usr/lib/udev/rules.d/60-fido-id.rules "
install_items+=" /usr/lib/udev/fido_id "
DRACUT_CONF

KVER="${1:-}"
if [ -z "$KVER" ]; then
  KVER="$(find /boot -maxdepth 1 -name 'vmlinuz-*' -printf '%f\n' \
    | sed 's/^vmlinuz-//' \
    | sort -V \
    | tail -n1)"
fi

[ -n "$KVER" ] || die "Could not find a kernel in /boot."
[ -f "/boot/vmlinuz-${KVER}" ] || die "Missing kernel: /boot/vmlinuz-${KVER}"

TARGET="/boot/initrd.img-${KVER}-${DRACUT_SUFFIX}"
TMP="/var/tmp/initrd.img-${KVER}-${DRACUT_SUFFIX}.$$"

echo "==> Kernel: $KVER"
echo "==> Target initrd: $TARGET"

echo "==> Creating Snapper checkpoint..."
if command -v snapper >/dev/null 2>&1; then
  snapper -c root create --description "Before rebuilding dracut FIDO2 GRUB entry for ${KVER}" || true
fi

echo "==> Building dracut image in /var/tmp first..."
rm -f "$TMP"

dracut --force --hostonly --compress "xz -T0 --check=crc32" "$TMP" "$KVER"

[ -s "$TMP" ] || die "Dracut image was not created."

IMG_SIZE_BYTES="$(stat -c '%s' "$TMP")"
IMG_SIZE_MIB="$(( (IMG_SIZE_BYTES + 1048575) / 1048576 ))"

BOOT_FREE_BYTES="$(df --output=avail -B1 /boot | awk 'NR==2 {print $1}')"
BOOT_FREE_MIB="$(( BOOT_FREE_BYTES / 1048576 ))"

OLD_SIZE_MIB=0
if [ -f "$TARGET" ]; then
  OLD_SIZE_BYTES="$(stat -c '%s' "$TARGET")"
  OLD_SIZE_MIB="$(( (OLD_SIZE_BYTES + 1048575) / 1048576 ))"
fi

EFFECTIVE_FREE_MIB="$(( BOOT_FREE_MIB + OLD_SIZE_MIB ))"
NEEDED_MIB="$(( IMG_SIZE_MIB + MIN_BOOT_FREE_MIB ))"

echo "==> New image size: ${IMG_SIZE_MIB} MiB"
echo "==> /boot free: ${BOOT_FREE_MIB} MiB"
echo "==> /boot effective free after overwrite: ${EFFECTIVE_FREE_MIB} MiB"

if [ "$EFFECTIVE_FREE_MIB" -lt "$NEEDED_MIB" ]; then
  rm -f "$TMP"
  die "/boot too tight. Need about ${NEEDED_MIB} MiB effective free."
fi

echo "==> Quick initrd contents check..."
if command -v lsinitrd >/dev/null 2>&1; then
  lsinitrd "$TMP" | grep -E 'crypttab|systemd-cryptsetup|cryptsetup|fido2-token|fido_id|60-fido|lvm|btrfs' | head -80 || true
fi

echo "==> Installing dracut image into /boot..."
cp -f "$TMP" "${TARGET}.new"
chmod 0644 "${TARGET}.new"
mv -f "${TARGET}.new" "$TARGET"
rm -f "$TMP"

BOOT_UUID="$(/usr/sbin/grub-probe --target=fs_uuid /boot)"
[ -n "$BOOT_UUID" ] || die "Could not determine /boot UUID."

LINUX_ARGS="$(cat /proc/cmdline | tr ' ' '\n' \
  | grep -v '^BOOT_IMAGE=' \
  | grep -v '^rd.auto=1$' \
  | grep -v '^initrd=' \
  | paste -sd' ' -)"

echo "$LINUX_ARGS" | grep -q 'root=' || die "Could not find root= in current kernel cmdline."

echo "==> Backing up old GRUB snippet..."
mkdir -p /root/grubd-backups
if [ -f "$GRUB_SNIPPET" ]; then
  cp -av "$GRUB_SNIPPET" "/root/grubd-backups/09_dracut_fido2.bak.$(date +%F-%H%M%S)" >/dev/null
fi

echo "==> Writing $GRUB_SNIPPET..."
cat > "$GRUB_SNIPPET" <<GRUB_ENTRY
#!/bin/sh
exec tail -n +3 \$0

menuentry '${TITLE}' {
    search --no-floppy --fs-uuid --set=root ${BOOT_UUID}
    linux /vmlinuz-${KVER} ${LINUX_ARGS} rd.auto=1
    initrd /initrd.img-${KVER}-${DRACUT_SUFFIX}
}
GRUB_ENTRY

chmod +x "$GRUB_SNIPPET"

echo "==> Setting GRUB to boot first menu entry with visible fallback menu..."
cp -av /etc/default/grub "/etc/default/grub.bak.update-dracut-fido2.$(date +%F-%H%M%S)" >/dev/null

python3 - <<'PY'
from pathlib import Path

p = Path('/etc/default/grub')
lines = p.read_text().splitlines()

wanted = {
    'GRUB_DEFAULT': '0',
    'GRUB_TIMEOUT_STYLE': 'menu',
    'GRUB_TIMEOUT': '5',
}

seen = set()
out = []

for line in lines:
    stripped = line.strip()
    replaced = False
    for key, value in wanted.items():
        if stripped.startswith(key + '='):
            if key not in seen:
                out.append(f'{key}={value}')
                seen.add(key)
            replaced = True
            break
    if not replaced:
        out.append(line)

for key, value in wanted.items():
    if key not in seen:
        out.append(f'{key}={value}')

p.write_text('\n'.join(out).rstrip() + '\n')
PY

echo "==> Regenerating GRUB..."
update-grub

echo
echo "==> Final verification:"
grep -A5 -B2 "dracut FIDO2" /boot/grub/grub.cfg || true
echo
grep -E '^GRUB_DEFAULT=|^GRUB_TIMEOUT_STYLE=|^GRUB_TIMEOUT=' /etc/default/grub || true

echo
echo "DONE. Normal Debian entries remain available as fallback."
EOF

sudo chmod +x /usr/local/sbin/update-dracut-fido2-grub
sudo ln -sfn /usr/local/sbin/update-dracut-fido2-grub /usr/sbin/update-dracut-fido2-grub
sudo bash -n /usr/local/sbin/update-dracut-fido2-grub
```

Run after kernel upgrades:

```bash
sudo update-dracut-fido2-grub
```

If `sudo` cannot find it because of `secure_path`, use the full path:

```bash
sudo /usr/local/sbin/update-dracut-fido2-grub
```

Verify after it runs:

```bash
sudo grep -A5 -B2 "dracut FIDO2" /boot/grub/grub.cfg
df -h /boot
```

---
## grub-btrfs snapshot menu

Install from package if available, or source if not:

```bash
sudo apt install -y grub-btrfs inotify-tools
```

If not packaged:

```bash
sudo apt install -y git make gawk btrfs-progs inotify-tools
mkdir -p ~/opt
cd ~/opt
git clone https://github.com/Antynea/grub-btrfs.git
cd grub-btrfs
make
sudo make install
```

Config:

```bash
sudo cp -av /etc/default/grub-btrfs/config /etc/default/grub-btrfs/config.bak.$(date +%F-%H%M%S)
```

Set:

```text
GRUB_BTRFS_MKCONFIG="/usr/sbin/update-grub"
GRUB_BTRFS_ENABLE_CRYPTODISK="true"
```

Manual generation:

```bash
sudo /etc/grub.d/41_snapshots-btrfs
sudo update-grub
```

Verify:

```bash
sudo grep -nEi "snapshot|snapper|grub-btrfs|Snapshots" /boot/grub/grub.cfg | head -80
ls -lh /boot/grub/grub-btrfs.cfg
sudo grub-script-check /boot/grub/grub-btrfs.cfg
```

The generated submenu looked like:

```text
Debian GNU/Linux snapshots
```

And snapshot paths looked like:

```text
@rootfs/.snapshots/<number>/snapshot
```

---

## Safer grub-btrfs refresh service

The upstream `grub-btrfsd` daemon did not refresh reliably in this build. Manual generation worked, but the daemon did not always update `grub-btrfs.cfg` after new Snapper snapshots.

A second issue appeared when a manual `sudo update-grub` ran too close to an automatic refresh. `os-prober` complained that `/var/lib/os-prober/mount` was busy, and `grub-btrfs` restored the previous working config after detecting a syntax error in a generated temporary file. The restore behavior protected the system, but the fix was to avoid overlapping GRUB jobs.

The final solution was:

- disable `grub-btrfsd`;
- create a locked wrapper script;
- use a systemd path unit to refresh when `/.snapshots` changes;
- add a timer fallback every 15 minutes;
- never run multiple GRUB refreshes at the same time.

Disable the flaky daemon:

```bash
sudo systemctl disable --now grub-btrfsd
```

Create the safe refresh wrapper:

```bash
sudo tee /usr/local/sbin/grub-btrfs-safe-refresh >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

exec 9>/run/grub-btrfs-refresh.lock
flock -n 9 || exit 0

# Let Snapper finish writing metadata and avoid racing manual update-grub.
sleep 8

for i in {1..60}; do
  if pgrep -x update-grub >/dev/null 2>&1 || \
     pgrep -x grub-mkconfig >/dev/null 2>&1 || \
     pgrep -x os-prober >/dev/null 2>&1; then
    sleep 2
  else
    break
  fi
done

/usr/sbin/update-grub
EOF

sudo chmod +x /usr/local/sbin/grub-btrfs-safe-refresh
```

Create the service:

```bash
sudo tee /etc/systemd/system/grub-btrfs-refresh.service >/dev/null <<'EOF'
[Unit]
Description=Refresh grub-btrfs snapshot menu safely

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/grub-btrfs-safe-refresh
EOF
```

Create the path unit:

```bash
sudo tee /etc/systemd/system/grub-btrfs-refresh.path >/dev/null <<'EOF'
[Unit]
Description=Watch Snapper snapshots and refresh grub-btrfs menu

[Path]
PathModified=/.snapshots
PathChanged=/.snapshots

[Install]
WantedBy=multi-user.target
EOF
```

Create the timer fallback:

```bash
sudo tee /etc/systemd/system/grub-btrfs-refresh.timer >/dev/null <<'EOF'
[Unit]
Description=Periodic grub-btrfs menu refresh fallback

[Timer]
OnBootSec=3min
OnUnitActiveSec=15min
Persistent=true

[Install]
WantedBy=timers.target
EOF
```

Enable the replacement refresh system:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now grub-btrfs-refresh.path
sudo systemctl enable --now grub-btrfs-refresh.timer
```

Test it:

```bash
BEFORE="$(stat -c '%Y %y' /boot/grub/grub-btrfs.cfg)"
echo "BEFORE: $BEFORE"

DESC="custom grub-btrfs path refresh test $(date +%s)"
SNAPNUM="$(sudo snapper -c root create --print-number --description "$DESC")"

echo "Snapshot number: $SNAPNUM"
echo "Description: $DESC"

sleep 20

AFTER="$(stat -c '%Y %y' /boot/grub/grub-btrfs.cfg)"
echo "AFTER:  $AFTER"

systemctl status grub-btrfs-refresh.service --no-pager
sudo grep -nE "/?\.snapshots/${SNAPNUM}/snapshot|snapshots/${SNAPNUM}/snapshot|/${SNAPNUM}/snapshot" /boot/grub/grub-btrfs.cfg || echo "Snapshot number not found yet"
```

Expected behavior:

```text
AFTER timestamp changes
ExecStart=/usr/local/sbin/grub-btrfs-safe-refresh exits SUCCESS
new snapshot number appears in /boot/grub/grub-btrfs.cfg
```

Final status check:

```bash
systemctl is-enabled grub-btrfsd
systemctl is-active grub-btrfsd
systemctl is-enabled grub-btrfs-refresh.path
systemctl is-enabled grub-btrfs-refresh.timer
```

Desired result:

```text
grub-btrfsd: disabled / inactive
grub-btrfs-refresh.path: enabled
grub-btrfs-refresh.timer: enabled
```

---
## Final script index

The final setup uses these local scripts and generated config files. They are shown in their working sections above, but this index is useful when rebuilding the machine later.

| File | Purpose | Section |
|---|---|---|
| `/usr/local/sbin/snapper-apt-pre` | Creates a pre snapshot before apt package operations. | [apt pre/post snapshots](#apt-prepost-snapshots) |
| `/usr/local/sbin/snapper-apt-post` | Creates a post snapshot linked to the apt pre snapshot. | [apt pre/post snapshots](#apt-prepost-snapshots) |
| `/etc/apt/apt.conf.d/80snapper` | Hooks apt/dpkg into Snapper. | [apt pre/post snapshots](#apt-prepost-snapshots) |
| `/etc/pam.d/sudo` | Adds FIDO key support for sudo with password fallback. | [sudo](#sudo) |
| `/etc/pam.d/sddm` | Adds FIDO key support for graphical login. | [SDDM login](#sddm-login) |
| `/etc/pam.d/hyprlock` | Adds FIDO key support for Hyprland lock screen unlock. | [hyprlock / lock screen](#hyprlock--lock-screen) |
| `/etc/pam.d/login` | Adds FIDO key support for TTY login. | [TTY login](#tty-login) |
| `/etc/pam.d/su` | Adds FIDO key support for `su` when authenticating as the mapped user. | [su](#su) |
| `/etc/dracut.conf.d/10-anonhowto-luks-fido2.conf` | Ensures dracut includes FIDO2 helpers and crypttab. | [FIDO2 LUKS unlock with dracut](#fido2-luks-unlock-with-dracut) |
| `/etc/crypttab` | Contains the `fido2-device=auto` option used by dracut/systemd-cryptsetup. | [crypttab for dracut](#crypttab-for-dracut) |
| `/etc/grub.d/09_dracut_fido2` | First/default GRUB entry for FIDO2 dracut boot. | [Custom GRUB default entry](#custom-grub-default-entry) |
| `/usr/local/sbin/update-dracut-fido2-grub` | Rebuilds the dracut FIDO2 initrd and rewrites the default GRUB entry after kernel upgrades. | [Kernel update helper script](#kernel-update-helper-script) |
| `/usr/local/sbin/grub-btrfs-safe-refresh` | Locked safe wrapper around `update-grub` for Snapper/grub-btrfs refreshes. | [Safer grub-btrfs refresh service](#safer-grub-btrfs-refresh-service) |
| `/etc/systemd/system/grub-btrfs-refresh.service` | One-shot service that runs the safe refresh wrapper. | [Safer grub-btrfs refresh service](#safer-grub-btrfs-refresh-service) |
| `/etc/systemd/system/grub-btrfs-refresh.path` | Watches `/.snapshots` and triggers a GRUB refresh. | [Safer grub-btrfs refresh service](#safer-grub-btrfs-refresh-service) |
| `/etc/systemd/system/grub-btrfs-refresh.timer` | Periodic fallback refresh in case the path watcher misses an event. | [Safer grub-btrfs refresh service](#safer-grub-btrfs-refresh-service) |
| `~/.config/hypr/scripts/LockScreen.sh` | Launches `hyprlock` directly instead of `loginctl lock-session`. | [hyprlock / lock screen](#hyprlock--lock-screen) |
| `~/.config/systemd/user/skwd-daemon.service` | User service for skwd-wall daemon. | [skwd-wall / Wallpaper Engine-style setup](#skwd-wall--wallpaper-engine-style-setup) |
| `/usr/local/bin/linux-wallpaperengine` | Wrapper for the locally installed Wallpaper Engine renderer. | [skwd-wall / Wallpaper Engine-style setup](#skwd-wall--wallpaper-engine-style-setup) |

---

## Final configuration appendix

The sections above explain why each file exists; This appendix is for rebuilding or auditing the machine later.

> Do not paste these blindly. Replace placeholders like `<kernel>`, `<boot-fs-uuid>`, `<luks-uuid>`, `<ANONHOWTO-USER>`, and `<security-key-mapping-data>` with values from the target machine.

### Placeholder map

| Placeholder | Meaning | How to get it |
|---|---|---|
| `<kernel>` | Kernel version used by the custom dracut entry. | `uname -r` or `ls /boot/vmlinuz-*` |
| `<boot-fs-uuid>` | Filesystem UUID for `/boot`, not the LUKS UUID. | `sudo grub-probe --target=fs_uuid /boot` |
| `<luks-uuid>` | UUID of the encrypted LUKS partition. | `lsblk -f` or `blkid /dev/nvme1n1p3` |
| `<root-mapper>` | LVM root mapper path. | `findmnt -no SOURCE /` |
| `<security-key-mapping-data>` | Public U2F mapping data generated by `pamu2fcfg`. | `cat ~/.config/Yubico/u2f_keys` |
| `<steam-root>` | Steam root used by the Wallpaper Engine tools. | Usually `~/.steam/debian-installation` on Debian Steam installs. |

### `/etc/crypttab`

Final dracut/FIDO2-enabled line:

```text
nvme1n1p3_crypt UUID=<luks-uuid> none luks,discard,x-initrd.attach,fido2-device=auto
```

Decision note:

- `fido2-device=auto` is intentionally present because dracut/systemd-cryptsetup understands it.
- Debian `initramfs-tools` may warn about this option. That is why the custom dracut boot entry is the default and the normal Debian entry is kept as fallback.
- Do not remove the normal LUKS passphrase. The security key is an additional unlock method, not the only recovery method.

### `/etc/dracut.conf.d/10-anonhowto-luks-fido2.conf`

```conf
hostonly="yes"
hostonly_mode="strict"
hostonly_cmdline="yes"

install_items+=" /etc/crypttab "
install_items+=" /usr/bin/fido2-token "
install_items+=" /usr/lib/udev/rules.d/60-fido-id.rules "
install_items+=" /usr/lib/udev/fido_id "
```

Decision note:

- `hostonly=yes` keeps the image tied to this laptop instead of building a generic initramfs.
- `hostonly_mode=strict` helped keep the dracut image small enough for a limited `/boot` partition.
- FIDO2 helper files are explicitly included so early boot has what it needs for token detection.

### `/etc/default/grub`

```conf
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=5
```

Optional theme settings:

```conf
GRUB_TERMINAL_OUTPUT=gfxterm
GRUB_GFXMODE=auto
# Example if installed:
# GRUB_THEME="/usr/share/desktop-base/grub-themes/starfield/theme.txt"
```

Decision note:

- `GRUB_DEFAULT=0` works because `/etc/grub.d/09_dracut_fido2` is intentionally ordered before `10_linux`.
- A visible 5-second menu is kept so the normal Debian entry remains reachable if the custom dracut entry fails.

### `/etc/grub.d/09_dracut_fido2`

```sh
#!/bin/sh
exec tail -n +3 $0

menuentry 'Debian GNU/Linux - dracut FIDO2 LUKS default' {
    search --no-floppy --fs-uuid --set=root <boot-fs-uuid>
    linux /vmlinuz-<kernel> root=/dev/mapper/ANONHOWTO--Laptop--vg-root ro rootflags=subvol=@rootfs quiet rd.auto=1
    initrd /initrd.img-<kernel>-dracut-passphrase
}
```

Permissions:

```bash
sudo chmod +x /etc/grub.d/09_dracut_fido2
sudo update-grub
```

Decision note:

- The file is named `09_...` so it is generated before Debian's normal `10_linux` entries.
- The custom entry uses the known-good dracut initrd.
- The normal Debian entries are left in place as fallback.

### `/etc/default/grub-btrfs/config`

Only the important final values are shown here:

```conf
GRUB_BTRFS_MKCONFIG="/usr/sbin/update-grub"
GRUB_BTRFS_ENABLE_CRYPTODISK="true"
```

Optional limit if the snapshot menu gets too large or a snapshot description breaks generation:

```conf
GRUB_BTRFS_LIMIT="20"
```

Decision note:

- `GRUB_BTRFS_ENABLE_CRYPTODISK=true` matters because the root filesystem is behind LUKS/LVM/Btrfs.
- The daemon from upstream/source install did not reliably refresh on this setup, so a safer systemd path/timer wrapper was used instead.

### `/etc/systemd/system/grub-btrfs-refresh.service`

```ini
[Unit]
Description=Refresh grub-btrfs snapshot menu safely

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/grub-btrfs-safe-refresh
```

### `/etc/systemd/system/grub-btrfs-refresh.path`

```ini
[Unit]
Description=Watch Snapper snapshots and refresh grub-btrfs menu

[Path]
PathModified=/.snapshots
PathChanged=/.snapshots

[Install]
WantedBy=multi-user.target
```

### `/etc/systemd/system/grub-btrfs-refresh.timer`

```ini
[Unit]
Description=Periodic grub-btrfs menu refresh fallback

[Timer]
OnBootSec=3min
OnUnitActiveSec=15min
Persistent=true

[Install]
WantedBy=timers.target
```

Enable the safer refresh path and timer:

```bash
sudo systemctl disable --now grub-btrfsd
sudo systemctl daemon-reload
sudo systemctl enable --now grub-btrfs-refresh.path
sudo systemctl enable --now grub-btrfs-refresh.timer
```

Expected final state:

```text
grub-btrfsd: disabled / inactive
grub-btrfs-refresh.path: enabled
grub-btrfs-refresh.timer: enabled
```

### `/etc/apt/apt.conf.d/80snapper`

```conf
DPkg::Pre-Invoke { "/usr/local/sbin/snapper-apt-pre"; };
DPkg::Post-Invoke { "/usr/local/sbin/snapper-apt-post"; };
```

Decision note:

- Inline shell in apt hooks was fragile and caused broken quoting behavior.
- Small helper scripts were more reliable and easier to debug.

### `/etc/Yubico/u2f_keys`

System-wide mapping used by PAM files:

```text
ANONHOWTO:<security-key-mapping-data-for-key-1>,<security-key-mapping-data-for-key-2>
```

Permissions:

```bash
sudo mkdir -p /etc/Yubico
sudo cp ~/.config/Yubico/u2f_keys /etc/Yubico/u2f_keys
sudo chown root:root /etc/Yubico/u2f_keys
sudo chmod 0644 /etc/Yubico/u2f_keys
```

Decision note:

- A system-wide mapping avoids lock/login failures caused by home directory path or permission assumptions.
- Two keys are enrolled before touching login or disk unlock.

### PAM files: common final pattern

The final PAM pattern is intentionally `sufficient`, not `required`:

```text
auth sufficient pam_u2f.so cue authfile=/etc/Yubico/u2f_keys
@include common-auth
```

Use that pattern in these files, near the top before `@include common-auth`:

```text
/etc/pam.d/sudo
/etc/pam.d/sddm
/etc/pam.d/hyprlock
/etc/pam.d/login
/etc/pam.d/su
```

Decision note:

- `sufficient` gives security-key login while preserving password fallback.
- `required` can lock you out if the mapping, key, PAM module, or USB stack breaks.
- `cue` shows a touch prompt in terminal contexts. Graphical prompts may not display it clearly, but the key still lights up.

### `~/.config/hypr/scripts/LockScreen.sh`

Final Hyprland lock behavior launches `hyprlock` directly instead of delegating to `loginctl lock-session`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Ensure only one lockscreen instance exists.
pidof hyprlock >/dev/null 2>&1 || hyprlock -q
```

Decision note:

- `pamtester swaylock` passed, but the actual lock script was using `loginctl lock-session` and the config references pointed toward `hyprlock`.
- Creating `/etc/pam.d/hyprlock` and launching `hyprlock` directly made the authentication path explicit.

### `~/.config/systemd/user/skwd-daemon.service`

```ini
[Unit]
Description=Skwd daemon
After=graphical-session.target

[Service]
ExecStart=/usr/local/bin/skwd-daemon
Restart=on-failure
Environment=PATH=/home/ANONHOWTO/.cargo/bin:/usr/local/bin:/usr/bin:/bin
Environment=LD_LIBRARY_PATH=/usr/local/lib:/opt/linux-wallpaperengine/lib

[Install]
WantedBy=default.target
```

Enable as the user:

```bash
systemctl --user daemon-reload
systemctl --user enable --now skwd-daemon.service
```

### skwd-wall important config values

The exact JSON keys may vary by version, but the values that mattered were the Steam and Wallpaper Engine paths:

```json
{
  "steamRoot": "/home/ANONHOWTO/.steam/debian-installation",
  "wallpaperEngineAssets": "/home/ANONHOWTO/.steam/debian-installation/steamapps/common/wallpaper_engine/assets",
  "workshopPath": "/home/ANONHOWTO/.steam/debian-installation/steamapps/workshop/content/431960",
  "ollamaModel": "moondream"
}
```

Decision note:

- The path values must be raw paths only. Do not paste labels like `Steam root ->` into JSON values.
- Ollama analysis is optional. It failed on WebP-heavy wallpapers and was not required for the wallpaper stack itself.

### `/usr/local/bin/linux-wallpaperengine`

```bash
#!/usr/bin/env bash
export LD_LIBRARY_PATH="/opt/linux-wallpaperengine/lib:${LD_LIBRARY_PATH:-}"
cd /opt/linux-wallpaperengine
exec ./linux-wallpaperengine "$@"
```

Permissions:

```bash
sudo chmod +x /usr/local/bin/linux-wallpaperengine
```

### zsh config: final defensive patterns

The full `.zshrc` can be kept as a separate companion file. The important patterns were:

```zsh
is_interactive() { [[ $- == *i* ]]; }
has() { command -v "$1" >/dev/null 2>&1; }

path_prepend() {
  [[ -d "$1" ]] || return
  case ":$PATH:" in
    *":$1:"*) ;;
    *) export PATH="$1${PATH:+:$PATH}" ;;
  esac
}

xdg_prepend() {
  [[ -d "$1" ]] || return
  case ":${XDG_DATA_DIRS:-}:" in
    *":$1:"*) ;;
    *) export XDG_DATA_DIRS="$1${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}" ;;
  esac
}

export XDG_DATA_DIRS="$HOME/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share"
export XDG_CONFIG_DIRS="/etc/xdg"

is_interactive || return 0
```

Decision note:

- Non-interactive shells exit early after environment setup.
- Missing plugins are skipped instead of breaking the shell.
- XDG paths explicitly include `/usr/share`, which fixed portal/GSettings issues seen during the desktop setup.
- `/usr/local/sbin` may not be in sudo's secure path, so admin helper scripts can be called by full path when needed.

---
## Controlled recovery behavior

### If the key is present at boot

The dracut entry asks for the FIDO2 token PIN. Enter the security key PIN, touch the key, and boot continues.

### If the key is missing

Remove the key and wait. The system falls back to the normal LUKS passphrase prompt.

### If the dracut boot entry breaks

Reboot and choose the normal Debian entry in GRUB. Unlock with the normal LUKS passphrase.

### If a package update breaks the system

Use the GRUB snapshots submenu. Boot a known-good Snapper snapshot, then decide whether to rollback or manually repair.

Do not treat snapshot boot entries as daily boot entries. Treat them as recovery tools.

---

## zsh and shell setup

The shell setup was not just cosmetic. During this build, the terminal was the recovery console, the log viewer, the config editor, the GRUB/debug workstation, and the place where every rollback command had to be readable under pressure.

The goal was:

```text
fast enough to use every day
fancy enough to be pleasant
safe enough not to break non-interactive scripts
defensive enough to survive missing plugins
portable enough to recreate on the next Debian install
```

The final approach used zsh with Oh My Zsh, Starship, fzf-tab, syntax highlighting, autosuggestions, Fastfetch, and a few Debian compatibility aliases.

### Why zsh instead of leaving Bash alone?

Bash is perfectly fine for recovery and scripting. The reason to switch the login shell to zsh was interactive quality of life:

- better completion menus,
- fuzzy completion with previews,
- history search,
- command autosuggestions,
- prompt customization,
- cleaner aliases/functions for repeated admin work.

The decision was to keep Bash available for scripts and use zsh only as the interactive user shell.

### Packages used

Start with Debian packages first:

```bash
sudo apt install -y \
  zsh curl git ca-certificates \
  fzf zoxide direnv \
  zsh-autosuggestions zsh-syntax-highlighting zsh-completions \
  eza lsd bat fd-find ripgrep \
  fastfetch btop nvtop ncdu jq tree \
  fonts-jetbrains-mono fonts-noto-color-emoji
```

Optional shell tools used or supported by the config:

```bash
sudo apt install -y \
  yazi chafa cmatrix sl figlet toilet lolcat \
  nethogs iftop bmon nload vnstat duf dust
```

Not every package is required. The `.zshrc` was written defensively so missing tools do not create startup errors.

### Oh My Zsh, Starship, and fzf-tab

Install Oh My Zsh manually if it is not already present:

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

Install Starship:

```bash
curl -sS https://starship.rs/install.sh | sh
```

Install extra Oh My Zsh plugins:

```bash
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

git clone https://github.com/Aloxaf/fzf-tab "$ZSH_CUSTOM/plugins/fzf-tab"
git clone https://github.com/zsh-users/zsh-completions "$ZSH_CUSTOM/plugins/zsh-completions"
```

Debian packages already provide `zsh-autosuggestions` and `zsh-syntax-highlighting`, but the config also checks Oh My Zsh custom plugin paths. That makes the setup tolerant of either packaging style.

### Make zsh the login shell

```bash
chsh -s "$(command -v zsh)"
```

Log out and back in.

Confirm:

```bash
echo "$SHELL"
ps -p $$ -o comm=
```

### Design decisions in the `.zshrc`

The final config used a few important patterns.

#### 1. Helper functions instead of blind assumptions

The config defined helpers like:

```zsh
is_interactive() { [[ $- == *i* ]]; }
has() { command -v "$1" >/dev/null 2>&1; }
```

That allowed the rest of the file to check whether a command exists before enabling aliases, prompts, plugins, or previews.

This matters because a post-install shell file should not fail just because `yazi`, `chafa`, `lsd`, `atuin`, or `starship` is not installed yet.

#### 2. Non-interactive shells exit early

The file exports environment variables first, then stops for non-interactive shells:

```zsh
is_interactive || return 0
```

This avoids poisoning scripts, `scp`, cron jobs, systemd commands, or other non-interactive shell use with prompt/plugin logic.

#### 3. PATH is ordered but deduplicated

The config used a safe `path_prepend` helper and zsh's unique array behavior:

```zsh
typeset -U path fpath
```

User paths were prioritized:

```zsh
$HOME/.local/bin
$HOME/bin
$HOME/go/bin
$HOME/.cargo/bin
$HOME/.atuin/bin
$HOME/.local/share/gem/ruby/3.3.0/bin
```

This was useful for tools installed by Rust, Go, pipx, Ruby, local scripts, or manual builds.

#### 4. Debian command compatibility

Debian often ships commands under different names:

```text
bat -> batcat
fd  -> fdfind
```

The config handled that:

```zsh
if ! has bat && has batcat; then
  alias bat='batcat'
fi

if ! has fd && has fdfind; then
  alias fd='fdfind'
fi
```

#### 5. Completion and fzf-tab previews

fzf-tab was configured for grouped completions and previews. For directory/file previews, the config preferred `lsd`, falling back to `ls`:

```zsh
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'lsd -la --color=always "$realpath" 2>/dev/null || ls -la "$realpath"'
zstyle ':fzf-tab:complete:ls:*' fzf-preview 'lsd -la --color=always "$realpath" 2>/dev/null || ls -la "$realpath"'
zstyle ':fzf-tab:complete:bat:*' fzf-preview 'bat --color=always --style=numbers --line-range=:200 "$realpath" 2>/dev/null'
```

This made path completion much easier while editing system files.

#### 6. Prompt ownership belongs to Starship

Oh My Zsh was used for plugins, but not for the prompt:

```zsh
ZSH_THEME=""
has starship && eval "$(starship init zsh)"
```

Starship was initialized after tool hooks so it could own the prompt cleanly.

### Recommended `.zshrc` skeleton

This is a compact version of the working config. It keeps the important decisions without including every optional alias.

```zsh
# ============================================================
# ANONHOWTO Zsh — Oh My Zsh + Starship + fzf-tab
# Clean, fast, defensive, and fancy.
# ============================================================

is_interactive() { [[ $- == *i* ]]; }
has() { command -v "$1" >/dev/null 2>&1; }

path_prepend() {
  [[ -d "$1" ]] || return
  case ":$PATH:" in
    *":$1:"*) ;;
    *) export PATH="$1${PATH:+:$PATH}" ;;
  esac
}

xdg_prepend() {
  [[ -d "$1" ]] || return
  case ":${XDG_DATA_DIRS:-}:" in
    *":$1:"*) ;;
    *) export XDG_DATA_DIRS="$1${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}" ;;
  esac
}

typeset -U path fpath

export EDITOR="${EDITOR:-nano}"
export VISUAL="${VISUAL:-$EDITOR}"
export PAGER="${PAGER:-less}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
mkdir -p "$XDG_CACHE_HOME/zsh" "$XDG_CACHE_HOME/zsh/completions" 2>/dev/null

path_prepend "$HOME/.local/share/gem/ruby/3.3.0/bin"
path_prepend "$HOME/.atuin/bin"
path_prepend "$HOME/.cargo/bin"
path_prepend "$HOME/go/bin"
path_prepend "$HOME/.pyenv/bin"
path_prepend "$HOME/bin"
path_prepend "$HOME/.local/bin"

xdg_prepend "/var/lib/flatpak/exports/share"
xdg_prepend "$HOME/.local/share/flatpak/exports/share"

export XDG_DATA_DIRS="$HOME/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share"
export XDG_CONFIG_DIRS="/etc/xdg"

if ! has bat && has batcat; then alias bat='batcat'; fi
if ! has fd && has fdfind; then alias fd='fdfind'; fi

is_interactive || return 0

export ZSH="$HOME/.oh-my-zsh"
export ZSH_CUSTOM="${ZSH_CUSTOM:-$ZSH/custom}"
ZSH_THEME=""
ENABLE_CORRECTION="false"
COMPLETION_WAITING_DOTS="true"
DISABLE_UNTRACKED_FILES_DIRTY="true"

if [[ -d "$ZSH_CUSTOM/plugins/zsh-completions/src" ]]; then
  fpath=("$ZSH_CUSTOM/plugins/zsh-completions/src" $fpath)
fi

autoload -Uz colors && colors
zmodload zsh/complist 2>/dev/null

zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$XDG_CACHE_HOME/zsh/completions"
zstyle ':completion:*' menu select
zstyle ':completion:*' group-name ''
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}' 'r:|[._-]=** r:|=**'

export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:---height 40% --layout=reverse --border --info=inline}"
if has rg; then
  export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git/*"'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
fi

zstyle ':fzf-tab:*' switch-group '<' '>'
zstyle ':fzf-tab:*' show-group full
zstyle ':fzf-tab:*' fzf-flags --height=40% --layout=reverse --border
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'lsd -la --color=always "$realpath" 2>/dev/null || ls -la "$realpath"'

plugins=()
_want_plugins=(
  git debian sudo colored-man-pages command-not-found extract
  history-substring-search docker docker-compose systemd python pip fzf
  zsh-completions zsh-autosuggestions fzf-tab zsh-syntax-highlighting
)
for _p in "${_want_plugins[@]}"; do
  if [[ -d "$ZSH/plugins/$_p" || -d "$ZSH_CUSTOM/plugins/$_p" ]]; then
    plugins+=("$_p")
  fi
done
unset _p _want_plugins

if [[ -r "$ZSH/oh-my-zsh.sh" ]]; then
  source "$ZSH/oh-my-zsh.sh"
else
  autoload -Uz compinit
  compinit -i -d "$XDG_CACHE_HOME/zsh/zcompdump-${ZSH_VERSION}"
fi

HISTFILE="$HOME/.zsh_history"
HISTSIZE=200000
SAVEHIST=200000
setopt EXTENDED_HISTORY APPEND_HISTORY INC_APPEND_HISTORY SHARE_HISTORY
setopt HIST_EXPIRE_DUPS_FIRST HIST_IGNORE_DUPS HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS HIST_SAVE_NO_DUPS HIST_REDUCE_BLANKS HIST_VERIFY HIST_IGNORE_SPACE
setopt AUTO_CD AUTO_PUSHD PUSHD_SILENT PUSHD_IGNORE_DUPS INTERACTIVE_COMMENTS GLOB_DOTS NO_BEEP
unsetopt FLOW_CONTROL
bindkey -e

has zoxide && eval "$(zoxide init zsh)"
has direnv && eval "$(direnv hook zsh)"
has atuin && eval "$(atuin init zsh)"
has starship && eval "$(starship init zsh)"

if has lsd; then
  alias ls='lsd --group-dirs first'
  alias l='lsd -l --group-dirs first'
  alias la='lsd -a --group-dirs first'
  alias lla='lsd -la --group-dirs first'
elif has eza; then
  alias ls='eza --group-directories-first --icons=auto'
  alias l='eza -l --group-directories-first --icons=auto'
  alias la='eza -a --group-directories-first --icons=auto'
  alias lla='eza -la --group-directories-first --icons=auto'
else
  alias ls='ls --color=auto'
fi

alias grep='grep --color=auto'
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias mkdir='mkdir -pv'
alias reload='source ~/.zshrc'
alias zshrc='$EDITOR ~/.zshrc'
alias top='btop'
alias d='docker'
alias dc='docker compose'
alias gst='git status --short --branch'
alias glog='git log --oneline --decorate --graph --all -n 25'
alias ports='ss -tulpn'
alias update='sudo apt update && sudo apt full-upgrade'
alias cleanup='sudo apt autoremove --purge && sudo apt autoclean'

mkcd() { mkdir -p -- "$1" && cd -- "$1"; }
serve() { python3 -m http.server "${1:-8000}"; }
pathclean() { path=("${(@u)path}"); export PATH; print -P "%F{green}PATH deduplicated.%f"; }
please() { sudo $(fc -ln -1); }

export LESS='-R'
if has bat; then
  export MANPAGER="sh -c 'col -bx | bat -l man -p'"
fi

[[ -r "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
[[ -r "$HOME/.config/fastfetch/graphite-banner.sh" ]] && source "$HOME/.config/fastfetch/graphite-banner.sh"
```

### Useful aliases and helper functions from the final build

The fuller config included convenience wrappers for repeated admin work:

```zsh
alias d='docker'
alias dc='docker compose'
alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
alias dlog='docker logs -f'
alias dcu='docker compose up -d'
alias dcd='docker compose down'
alias dcl='docker compose logs -f'

alias ports='ss -tulpn'
alias myip='curl -4 ifconfig.me 2>/dev/null; echo'
alias update='sudo apt update && sudo apt full-upgrade'
alias cleanup='sudo apt autoremove --purge && sudo apt autoclean'

mkcd() { mkdir -p -- "$1" && cd -- "$1"; }
serve() { python3 -m http.server "${1:-8000}"; }
please() { sudo $(fc -ln -1); }
```

A small dashboard function also helped during rebuilds:

```zsh
dash() {
  clear
  if command -v fastfetch >/dev/null 2>&1; then
    fastfetch
  fi
  echo
  echo "Quick commands:"
  echo "  top        -> btop if installed"
  echo "  gputop     -> nvtop if installed"
  echo "  netapps    -> sudo nethogs"
  echo "  nettop     -> sudo iftop"
  echo "  y          -> yazi with cd-on-exit"
  echo "  h <cmd>    -> tldr help"
}
```

### Issues encountered during shell setup

#### sudo secure path

A helper script was installed here:

```text
/usr/local/sbin/update-dracut-fido2-grub
```

But this failed:

```text
sudo: update-dracut-fido2-grub: command not found
```

The script existed and passed syntax checks. The issue was `sudo` secure path. Fixes:

```bash
sudo /usr/local/sbin/update-dracut-fido2-grub
```

or:

```bash
sudo ln -sfn /usr/local/sbin/update-dracut-fido2-grub /usr/sbin/update-dracut-fido2-grub
```

#### Fastfetch Graphite banner

A custom Fastfetch Graphite banner made the shell feel polished and helped confirm the config loaded. Keep it optional:

```zsh
[[ -r "$HOME/.config/fastfetch/graphite-banner.sh" ]] && source "$HOME/.config/fastfetch/graphite-banner.sh"
```



Useful checks:

```bash
fastfetch
which zsh
printenv XDG_DATA_DIRS
printenv PATH
```

---

## Optional desktop polish: Kando and skwd-wall

This section is not required for the secure boot/recovery setup. It is desktop polish added after the base system was safe.

### Kando

Kando is a cross-platform pie menu. It is useful if you like gesture/radial launchers for apps, macros, and shortcuts.

Install options:

```bash
flatpak install flathub menu.kando.Kando
```

or use the upstream release packaging if preferred.

Decision-making:

- Kando is not security-critical.
- Install it after snapshots and FIDO2 boot are working.
- Keep it user-level, not root-level.
- Use it for desktop workflow shortcuts, not privileged scripts.

Hyprland idea:

```ini
bind = SUPER, SPACE, exec, flatpak run menu.kando.Kando
```

Adjust based on how Kando is packaged and launched.

### skwd-wall / Wallpaper Engine-style setup

skwd-wall was used as a wallpaper selector / desktop aesthetics layer. The important lesson: do this after the system has rollback and snapshots.

High-level pieces:

```text
skwd-wall      -> wallpaper selector UI
skwd-daemon    -> background service
skwd-paper-still -> static image helper that was required for static wallpapers
linux-wallpaperengine -> renderer for Wallpaper Engine scene support
Steam Wallpaper Engine assets/workshop paths -> source content
matugen        -> color/theme generation
Ollama         -> optional image analysis/tagging, not required
```

Useful final Hyprland binding:

```ini
exec-once = skwd-daemon
bind = SUPER, T, exec, skwd wall toggle
```

What did not work cleanly:

- Launching the Quickshell file directly was the wrong interface for normal use.
- The actual toggle command was `skwd wall toggle`.
- Static wallpapers failed until `skwd-paper-still` existed.
- Wallpaper Engine paths needed to be raw paths, not labels pasted into config.
- Ollama image analysis failed on WebP-heavy libraries and was not required.

Example Steam paths to check:

```text
$HOME/.steam/debian-installation/steamapps/common/wallpaper_engine/assets
$HOME/.steam/debian-installation/steamapps/workshop/content/431960
```

Use placeholders in notes/config examples:

```text
/home/ANONHOWTO/.steam/debian-installation/steamapps/common/wallpaper_engine/assets
/home/ANONHOWTO/.steam/debian-installation/steamapps/workshop/content/431960
```

Decision-making:

- Keep wallpaper tooling outside the boot-critical path.
- Snapshot before building from source.
- If Ollama analysis fails, disable/ignore it; wallpaper setting can still work.
- Avoid troubleshooting visual extras before the boot/recovery stack is stable.


### XDG variables and desktop portals for Kando/skwd-wall/Wayland tools

Hyprland/Kooldots-style configs can break desktop portals and visual desktop tools if `XDG_DATA_DIRS` does not include `/usr/share`. This mattered after Kando, skwd-wall, Waybar, portals, Flatpak exports, and GSettings-backed apps entered the picture.

Good values:

```bash
export XDG_DATA_DIRS="$HOME/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share"
export XDG_CONFIG_DIRS="/etc/xdg"
```

Import them for user services when needed:

```bash
systemctl --user import-environment XDG_DATA_DIRS XDG_CONFIG_DIRS PATH
dbus-update-activation-environment --systemd XDG_DATA_DIRS XDG_CONFIG_DIRS PATH
```

Bad patterns to watch for:

```text
/home/ANONHOWTO
XDG_CONFIG_DIRS./etc/xdg
XDG_DATA_DIRS without /usr/share
```

Symptoms included broken portals, missing app discovery, and Waybar/desktop components behaving strangely even when terminal commands worked.

This belongs with the desktop polish section because the secure boot stack can work perfectly while Wayland portals, launchers, wallpaper tools, or app discovery are still broken by bad XDG values.


Final user service for the daemon:

```bash
mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/skwd-daemon.service <<'EOF'
[Unit]
Description=Skwd daemon
After=graphical-session.target

[Service]
ExecStart=/usr/local/bin/skwd-daemon
Restart=on-failure
Environment=PATH=/home/ANONHOWTO/.cargo/bin:/usr/local/bin:/usr/bin:/bin
Environment=LD_LIBRARY_PATH=/usr/local/lib:/opt/linux-wallpaperengine/lib

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now skwd-daemon.service
systemctl --user status skwd-daemon.service --no-pager
```

Final Hyprland binding:

```ini
exec-once = skwd-daemon
bind = SUPER, T, exec, skwd wall toggle
```

Do not use the old direct Quickshell launch as the main toggle:

```ini
# bind = SUPER, T, exec, sh -c 'cd /home/ANONHOWTO/opt/skwd-wall && /usr/bin/quickshell -p shell.qml'
```

Wallpaper Engine renderer wrapper used when installing `linux-wallpaperengine` under `/opt`:

```bash
sudo tee /usr/local/bin/linux-wallpaperengine >/dev/null <<'EOF'
#!/bin/bash
export LD_LIBRARY_PATH="/opt/linux-wallpaperengine/lib:$LD_LIBRARY_PATH"
cd /opt/linux-wallpaperengine
exec ./linux-wallpaperengine "$@"
EOF

sudo chmod +x /usr/local/bin/linux-wallpaperengine
```

Steam path placeholders used by the skwd-wall config:

```text
/home/ANONHOWTO/.steam/debian-installation
/home/ANONHOWTO/.steam/debian-installation/steamapps/common/wallpaper_engine/assets
/home/ANONHOWTO/.steam/debian-installation/steamapps/workshop/content/431960
```

### Graphite UI demo video

A short desktop demo can make this section easier to understand because Kando, skwd-wall, Waybar, and the wallpaper switcher are visual tools. The demo used for this draft shows the finished Hyprland Graphite desktop rather than the security stack itself.

```markdown
Demo video: https://files.catbox.moe/y4bcib.mp4
```

### Waybar Graphite CSS

The Graphite look in the demo used a small Waybar stylesheet. This is not security-critical, but it helps make the Hyprland desktop feel like a finished daily-driver environment after the boot, rollback, and FIDO2 work is complete.

Install the Waybar/font pieces first:

```bash
sudo apt install -y waybar fonts-jetbrains-mono fonts-noto-color-emoji
```

If the exact Nerd Font family is not installed, either install a JetBrainsMono Nerd Font manually or change the `font-family` line to a font available on the system.

Example install path:

```bash
mkdir -p ~/.config/waybar
nano ~/.config/waybar/style.css
```

Paste the CSS below:

```css
/* ---- Graphite Waybar ---- */

* {
  font-family: JetBrainsMono Nerd Font;
  font-size: 12px;
  border: none;
}

/* Bar */
window#waybar {
  background: #1e2127;
  color: #d6dae0;
  border-bottom: 1px solid #e2e6ec;
  margin: 6px 10px;
  border-radius: 10px;
}

/* Workspaces */
#workspaces button:hover {
  padding: 4px 8px;
  color: #b9bec6;
  background: transparent;
  border-radius: 6px;
}

#workspaces button.active {
  background: #2a2f38;
  color: #e2e6ec;
}

#workspaces button:hover {
  background: #3a3f4b;
}

/* Modules */
#clock,
#cpu,
#memory,
#network,
#pulseaudio,
#tray {
  padding: 0 10px;
  color: #d6dae0;
}

/* Battery states */
#battery {
  color: #8fb573;
}

#battery.warning {
  color: #d6b97b;
}

#battery.critical {
  color: #c96b6b;
}

/* Tooltip */
tooltip {
  background: #2a2f38;
  color: #d6dae0;
  border: 1px solid #3a3f4b;
}
```

Then restart Waybar:

```bash
pkill waybar 2>/dev/null || true
waybar &
```

If Waybar is started by Hyprland, reload Hyprland or restart the user session instead.

Decision-making:

- Keep the CSS simple and readable.
- Use a dark Graphite bar with subtle borders instead of bright accent colors.
- Keep battery warning/critical colors distinct.
- Keep tooltip colors consistent with the bar.
- Install fonts before debugging CSS; missing Nerd Font glyphs can look like broken Waybar modules even when the CSS is fine.

## App list for a fresh Debian workstation

Core CLI:

```bash
sudo apt install -y \
  nala curl wget git ca-certificates gnupg lsb-release \
  build-essential dkms linux-headers-amd64 \
  unzip p7zip-full xz-utils zip \
  rsync rclone \
  fastfetch btop htop nvtop ncdu tree \
  ripgrep fd-find fzf jq bat eza zoxide tldr \
  plocate lsof strace file \
  lm-sensors smartmontools nvme-cli usbutils pciutils fwupd
```

Desktop:

```bash
sudo apt install -y \
  kdeconnect pavucontrol pipewire wireplumber blueman \
  gparted partitionmanager filelight baobab \
  spectacle flameshot okular gwenview ark kate
```

Wayland/Hyprland helpers:

```bash
sudo apt install -y \
  waybar rofi wofi swaylock swayidle \
  grim slurp swappy wl-clipboard cliphist \
  playerctl brightnessctl mako-notifier \
  foot kitty alacritty
```

Security:

```bash
sudo apt install -y \
  yubikey-manager libpam-u2f pamu2fcfg \
  keepassxc ufw gufw fail2ban
```

Media and gaming:

```bash
sudo apt install -y \
  vlc mpv ffmpeg gimp \
  steam-installer mangohud gamemode gamescope goverlay
```

---

## What worked and what did not

### Worked

- LUKS2 + LVM + Btrfs root.
- Separate Btrfs `/home`.
- Snapper root snapshots.
- apt pre/post snapshots through helper scripts.
- PAM U2F for sudo.
- PAM U2F for SDDM.
- PAM U2F for hyprlock once the actual lock program was identified.
- FIDO2 LUKS unlock with dracut.
- Normal LUKS passphrase fallback by removing the key.
- Custom `09_dracut_fido2` GRUB entry.
- `GRUB_DEFAULT=0` once the custom entry was first.
- grub-btrfs manual generation.
- Custom path/timer refresh replacing flaky `grub-btrfsd`.
- zsh quality-of-life setup with explicit PATH/XDG values.

### Did not work cleanly

- `fido2-device=auto` with Debian initramfs-tools.
- Assuming `/boot` was large enough.
- Creating extra dracut images without checking `/boot` space.
- Putting backup GRUB scripts inside `/etc/grub.d`; GRUB processed them too.
- Relying on exact GRUB labels before verifying generated entries.
- `grub-btrfsd` auto-refresh in this setup.
- Overlapping manual `update-grub` with auto-refresh.
- Pasting labels instead of raw paths into wallpaper config.
- Treating Ollama wallpaper analysis as required.
- Assuming `/usr/local/sbin` would be in sudo's secure path.

---

## Final checklist

After the build:

```bash
cat /proc/cmdline | tr ' ' '\n' | grep -E 'rd.auto|root=|BOOT_IMAGE'
sudo grep -A5 -B2 "dracut FIDO2" /boot/grub/grub.cfg
sudo grub-script-check /boot/grub/grub.cfg
sudo grub-script-check /boot/grub/grub-btrfs.cfg
systemctl is-enabled grub-btrfs-refresh.path
systemctl is-enabled grub-btrfs-refresh.timer
df -h /boot
sudo snapper -c root list | tail -20
```

Create final checkpoint:

```bash
sudo snapper -c root create --description "Golden state FIDO2 dracut LUKS and grub-btrfs working"
sudo /usr/local/sbin/grub-btrfs-safe-refresh
```

After kernel upgrades:

```bash
sudo update-dracut-fido2-grub
sudo /usr/local/sbin/grub-btrfs-safe-refresh
```

Keep:

- both FIDO2 keys tested,
- LUKS passphrase saved safely,
- LUKS recovery key saved safely,
- normal Debian boot entry in GRUB,
- recent golden Snapper snapshot,
- live USB available.

---

The final result is not the simplest Debian install, but it is a resilient one: FIDO2 where it helps, passwords where fallback matters, snapshots where updates can go wrong, and GRUB entries that give you a way back.

Secure is good. Recoverable is better.



---
## References

- systemd-cryptenroll manual: https://www.freedesktop.org/software/systemd/man/latest/systemd-cryptenroll.html
- systemd crypttab options: https://www.freedesktop.org/software/systemd/man/latest/crypttab.html
- dracut: https://github.com/dracutdevs/dracut
- Snapper: https://github.com/openSUSE/snapper
- grub-btrfs: https://github.com/Antynea/grub-btrfs
- pam-u2f / Yubico: https://developers.yubico.com/pam-u2f/
- Kando: https://github.com/kando-menu/kando
- Kando website: https://kando.menu/
- skwd-wall: https://github.com/liixini/skwd-wall
- skwd: https://github.com/liixini/skwd
