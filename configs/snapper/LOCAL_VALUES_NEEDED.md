# Snapper notes

Useful local checks:

```bash
sudo snapper -c root list
sudo snapper -c root get-config
sudo systemctl status snapper-timeline.timer snapper-cleanup.timer snapper-boot.timer --no-pager
sudo btrfs subvolume list /
```

The apt hook in `80snapper.example` expects:

```text
/usr/local/sbin/snapper-apt-pre
/usr/local/sbin/snapper-apt-post
```
