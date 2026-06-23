# Scripts

## install_dwm_arch.sh

Post-archinstall setup script for a minimal Arch + dwm environment.

Run after first boot from archinstall (minimal profile), as your normal user.

Installs: xorg, BreadOnPenguins' dwm/st/dmenu/dwmblocks builds,
her scripts + dots configs, firefox, neovim, feh, slock, picom,
dunst, pywal, zsh + oh-my-zsh, JetBrains Mono + Hack Nerd Fonts.

Usage:
    curl -O https://raw.githubusercontent.com/AlfieMcPhee/scripts/main/install_dwm_arch.sh
    chmod +x install_dwm_arch.sh
    ./install_dwm_arch.sh
