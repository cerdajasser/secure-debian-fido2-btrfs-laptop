# Local verification commands

Run these locally.

## Storage and Btrfs

```bash
lsblk -f
findmnt / /home /boot /boot/efi
sudo btrfs subvolume list /
```

## LUKS/FIDO2

```bash
sudo cryptsetup luksDump /dev/<encrypted-partition>
sudo systemd-cryptenroll /dev/<encrypted-partition>
```

Public summary instead of full `luksDump`:

```text
LUKS version: 2
FIDO2 token enrolled: yes
Recovery key enrolled: yes
Normal passphrase fallback: yes
Early boot unlock path: dracut + systemd-cryptsetup
crypttab option: fido2-device=auto
```

## GRUB

```bash
cat /proc/cmdline
sudo grep -A8 -B3 "dracut FIDO2" /boot/grub/grub.cfg
sudo grub-script-check /boot/grub/grub-btrfs.cfg
```

## Services

```bash
systemctl is-enabled snapper-timeline.timer snapper-cleanup.timer snapper-boot.timer
systemctl is-enabled grub-btrfs-refresh.path grub-btrfs-refresh.timer
systemctl --user status skwd-daemon.service --no-pager
```
