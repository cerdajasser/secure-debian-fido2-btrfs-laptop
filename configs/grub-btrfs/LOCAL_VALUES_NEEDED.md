# grub-btrfs notes

Generate/check locally:

```bash
sudo /etc/grub.d/41_snapshots-btrfs
sudo update-grub
sudo grub-script-check /boot/grub/grub-btrfs.cfg
sudo grep -nEi "snapshot|grub-btrfs" /boot/grub/grub.cfg | head -80
```

This bundle intentionally does not include full generated GRUB configs.
