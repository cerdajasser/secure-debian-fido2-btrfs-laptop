# Shell notes

Useful install packages:

```bash
sudo apt install -y zsh fzf zoxide direnv zsh-autosuggestions zsh-syntax-highlighting zsh-completions eza bat fd-find ripgrep fastfetch fonts-jetbrains-mono
```

Set zsh as login shell:

```bash
chsh -s "$(command -v zsh)"
```

Debian command aliases often needed:

```zsh
alias bat='batcat'
alias fd='fdfind'
```
