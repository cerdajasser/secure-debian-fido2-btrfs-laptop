# Local values needed for boot/LUKS/dracut

Do not copy someone else's UUIDs or mapper paths.

Get your values with:

```bash
lsblk -f
sudo blkid
findmnt -no SOURCE /
sudo grub-probe --target=fs_uuid /boot
uname -r
cat /proc/cmdline
```

Common placeholders:

| Placeholder | How to get it |
|---|---|
| `<LUKS_UUID>` | `lsblk -f` or `sudo blkid /dev/<encrypted-partition>` |
| `<BOOT_FS_UUID>` | `sudo grub-probe --target=fs_uuid /boot` |
| `<KERNEL_VERSION>` | `uname -r` |
| `<ROOT_MAPPER>` | `findmnt -no SOURCE /` |
| `<VG_NAME>` | `lvs` or inspect `findmnt -no SOURCE /` |
| `<ENCRYPTED_PARTITION>` | `lsblk -f`; example `/dev/nvme1n1p3` |
