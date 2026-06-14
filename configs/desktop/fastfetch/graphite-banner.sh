#!/usr/bin/env bash

# Graphite Fastfetch banner launcher.
# Safe to source from ~/.zshrc.

if [[ -t 1 && "${TERM:-}" != "dumb" && -z "${NO_FASTFETCH:-}" ]]; then
  if command -v fastfetch >/dev/null 2>&1; then
    fastfetch -c "$HOME/.config/fastfetch/config-graphite.jsonc"
  fi
fi
