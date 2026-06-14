# Secure Debian FIDO2 + Btrfs Setup Files

Minimal public bundle for the secure Debian laptop setup.

This contains only files useful for recreating the setup:

```text
scripts/
configs/
docs/
ARTICLE.md   # only if provided with --article
```

## Important files

```text
scripts/update-dracut-fido2-grub
scripts/grub-btrfs-safe-refresh
scripts/snapper-apt-pre
scripts/snapper-apt-post

configs/boot-luks-dracut/crypttab.example
configs/boot-luks-dracut/*fido2*.conf
configs/grub/default-grub.example
configs/grub/09_dracut_fido2.example
configs/auth-pam-yubikey/pam-u2f-snippets.md
configs/auth-pam-yubikey/u2f_keys.PLACEHOLDER.md
configs/snapper/80snapper.example
configs/snapper/root-config.example
configs/grub-btrfs/grub-btrfs-config.example
configs/systemd/grub-btrfs-refresh.*
```

Desktop extras, if included:

```text
configs/desktop/waybar-graphite/
configs/desktop/kando/
configs/desktop/skwd-wall/
configs/desktop/LockScreen.sh.example
configs/shell/zshrc.example
```

## Read before using

Do not blindly copy these files. Replace placeholders and check local values first:

```bash
lsblk -f
findmnt -no SOURCE /
sudo grub-probe --target=fs_uuid /boot
uname -r
```

See:

```text
docs/placeholders.md
docs/local-verification-commands.md
docs/do-not-publish.md
```
