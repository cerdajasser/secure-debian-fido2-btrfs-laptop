# PAM U2F snippets

Safe pattern used:

```text
auth sufficient pam_u2f.so cue authfile=/etc/Yubico/u2f_keys
```

Use near the top of these PAM files, before normal password auth:

```text
/etc/pam.d/sudo
/etc/pam.d/sddm
/etc/pam.d/hyprlock
/etc/pam.d/login
/etc/pam.d/su
```

Why `sufficient`:

- key works when present;
- password fallback remains available;
- less chance of lockout during testing.

Avoid `auth required pam_u2f.so` until you fully understand the lockout risk.
