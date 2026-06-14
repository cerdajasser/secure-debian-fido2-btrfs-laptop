# Local values needed for GRUB

Do not copy another machine's GRUB entry directly.

Get values:

```bash
uname -r
findmnt -no SOURCE /
sudo grub-probe --target=fs_uuid /boot
cat /proc/cmdline
```

Check generated result:

```bash
sudo update-grub
sudo grep -A8 -B3 "dracut FIDO2" /boot/grub/grub.cfg
```

This bundle intentionally does not include full `/boot/grub/grub.cfg`.
