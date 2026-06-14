# `/etc/Yubico/u2f_keys` placeholder

Do not publish your real `/etc/Yubico/u2f_keys`.

Generate locally:

```bash
mkdir -p ~/.config/Yubico
chmod 700 ~/.config/Yubico

# key 1
pamu2fcfg -u "$USER" > ~/.config/Yubico/u2f_keys
chmod 600 ~/.config/Yubico/u2f_keys

# key 2
pamu2fcfg -n >> ~/.config/Yubico/u2f_keys

# system-wide copy for SDDM/hyprlock/sudo
sudo mkdir -p /etc/Yubico
sudo cp ~/.config/Yubico/u2f_keys /etc/Yubico/u2f_keys
sudo chown root:root /etc/Yubico/u2f_keys
sudo chmod 0644 /etc/Yubico/u2f_keys
```

Example structure only:

```text
<USER>:<key1-public-mapping>,<key2-public-mapping>
```
