#!/usr/bin/env bash
# =============================================================================
# dwm install script — BreadOnPenguins' stack on minimal Arch Linux
# Run AFTER first boot from archinstall (minimal profile).
# Run as your normal user, NOT root.
#
# What this installs:
#   xorg, dwm, st, dmenu, dwmblocks (BreadOnPenguins builds)
#   BreadOnPenguins scripts + dots (picom, dunst configs)
#   firefox, nvim, feh, slock, pywal, zsh + oh-my-zsh + plugins
#   All fonts, statusbar scripts, and keybinds wired to working tools
#   .xinitrc ready to go — type 'startx' from TTY to launch
# =============================================================================

set -euo pipefail

RED=$'\e[31m'; GRN=$'\e[32m'; YLW=$'\e[33m'; BLU=$'\e[34m'; RST=$'\e[0m'
info()  { printf '\n%s==>%s %s\n' "$BLU" "$RST" "$*"; }
ok()    { printf '%s ok%s  %s\n' "$GRN" "$RST" "$*"; }
warn()  { printf '%s[!]%s  %s\n' "$YLW" "$RST" "$*"; }
die()   { printf '%s[x]%s  %s\n' "$RED" "$RST" "$*" >&2; exit 1; }

# =============================================================================
# SANITY CHECKS
# =============================================================================
[[ "$EUID" -eq 0 ]] && die "Run as your normal user, not root. The script uses sudo where needed."
command -v pacman &>/dev/null || die "pacman not found — this script targets Arch Linux."
ping -c1 -W3 archlinux.org &>/dev/null || die "No network connection. Connect first."

SUCKLESS="$HOME/suckless"
SCRIPTS="$HOME/scripts"
DOTS="$HOME/dots"

# =============================================================================
# 1. SYSTEM UPDATE + CORE DEPS
# =============================================================================
info "Updating system and installing core dependencies..."
sudo pacman -Syu --noconfirm
sudo pacman -S --needed --noconfirm \
    base-devel git curl wget \
    xorg-server xorg-xinit xorg-xrdb \
    libx11 libxft libxinerama libxcb \
    xclip xdotool xdg-utils \
    zsh \
    firefox neovim \
    picom dunst libnotify \
    feh slock \
    scrot imagemagick \
    mpv ffmpeg \
    playerctl pamixer \
    fzf bc sed \
    ttf-hack-nerd ttf-jetbrains-mono-nerd noto-fonts-emoji \
    python \
    alsa-utils
ok "Core dependencies installed."

# =============================================================================
# 2. YAY (AUR HELPER)
# =============================================================================
info "Installing yay (AUR helper)..."
if ! command -v yay &>/dev/null; then
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    cd /tmp/yay && makepkg -si --noconfirm
    cd "$HOME"
    rm -rf /tmp/yay
    ok "yay installed."
else
    ok "yay already installed, skipping."
fi

# =============================================================================
# 3. AUR PACKAGES
# =============================================================================
info "Installing AUR packages..."

# pywal — try pywal16 first (better), fall back to python-pywal
if yay -S --needed --noconfirm python-pywal16 2>/dev/null; then
    ok "python-pywal16 installed."
elif yay -S --needed --noconfirm python-pywal 2>/dev/null; then
    ok "python-pywal installed (pywal16 unavailable)."
else
    warn "pywal not available from AUR. Colour theming won't work until installed manually."
fi

# nsxiv for wallpapermenu script
yay -S --needed --noconfirm nsxiv 2>/dev/null \
    || warn "nsxiv not installed — wallpapermenu script won't work."

ok "AUR packages done."

# =============================================================================
# 4. CLONE REPOS
# =============================================================================
info "Cloning suckless repos..."
mkdir -p "$SUCKLESS"

clone_or_update() {
    local url="$1" dest="$2"
    if [[ -d "$dest/.git" ]]; then
        warn "$(basename "$dest") already cloned, skipping."
    else
        git clone "$url" "$dest"
        ok "Cloned $(basename "$dest")."
    fi
}

clone_or_update https://github.com/BreadOnPenguins/dwm      "$SUCKLESS/dwm"
clone_or_update https://github.com/BreadOnPenguins/st       "$SUCKLESS/st"
clone_or_update https://github.com/BreadOnPenguins/dmenu    "$SUCKLESS/dmenu"
clone_or_update https://github.com/torrinfail/dwmblocks     "$SUCKLESS/dwmblocks"
clone_or_update https://github.com/BreadOnPenguins/scripts  "$SCRIPTS"
clone_or_update https://github.com/BreadOnPenguins/dots     "$DOTS"

# =============================================================================
# 5. PATCH dwm CONFIG — browser, MODKEY, keybinds
# =============================================================================
info "Patching dwm config.def.h..."
DWM_CFG="$SUCKLESS/dwm/config.def.h"

python3 - "$DWM_CFG" <<'PYEOF'
import re, sys
path = sys.argv[1]
s = open(path).read()

# --- browser ---
s = s.replace('#define BROWSER "qutebrowser"', '#define BROWSER "firefox"')

# --- MODKEY: ensure Super (Mod4Mask) ---
s = re.sub(r'#define MODKEY \w+', '#define MODKEY Mod4Mask // windows key', s)

# --- keybind replacements ---
# Each tuple: (old_fragment_to_match, new_full_line)
# We match on a unique substring and replace the whole line.
replacements = [
    # togglebar: move from Super+Shift+b to Super+b (matching dwl muscle memory)
    ('XK_b,      togglebar',
     '\t{ MODKEY,                       XK_b,          togglebar,      {0} },'),
    # quit dwm: add Super+Shift+q as alias (dwl muscle memory)
    # dwm keeps Super+Shift+Backspace as primary, we add Shift+q too
    ('{ MODKEY|ControlMask|ShiftMask, XK_q,           quit,                   {1} }',
     '\t{ MODKEY|ControlMask|ShiftMask, XK_q,  quit,          {1} },  /* restart dwm */\n\t{ MODKEY|ShiftMask,             XK_q,  quit,          {0} },  /* quit dwm (dwl muscle memory) */'),
    # fullscreen on Super+e (matching dwl's togglefullscreen bind)
    # dwm config already has XK_f as togglefullscreen from our fff replacement
    # add Super+e as well
    ('{ MODKEY,                                               XK_f,      togglefullscreen',
     '\t{ MODKEY,                       XK_e,          togglefullscreen, {0} },\n\t{ MODKEY,                       XK_f,          togglefullscreen, {0} },'),
    # monocle on Super+m (matching dwl) — dwm has Super+Shift+m
    ('{ MODKEY|ShiftMask,                             XK_m,      setlayout,      {.v = &layouts[2]} }',
     '\t{ MODKEY,                       XK_m,          setlayout,      {.v = &layouts[2]} },  /* monocle */'),
    # termusic -> htop
    ('"st", "-e", "termusic"',
     '\t{ MODKEY,                       XK_m,          spawn,      {.v = (const char*[]){ "st", "-e", "htop", NULL } } },'),
    # fff -> lf (if available) or file manager placeholder
    ('"st", "-e", "fff"',
     '\t{ MODKEY,                       XK_f,          togglefullscreen, {0} },'),
    # darktable -> keep p as nvim scratch
    ('"darktable"',
     '\t{ MODKEY,                       XK_p,          spawn,      {.v = (const char*[]){ "st", "-e", "nvim", NULL } } },'),
    # dmenunotes -> removed (n is nvim)
    ('"dmenunotes"', ''),
    # cliphist sel -> txtcliphist
    ('"cliphist", "sel"',
     '\t{ MODKEY,                               XK_v,  spawn,      SHCMD("txtcliphist") },'),
    # cliphist add -> remove (no direct equivalent)
    ('"cliphist", "add"', ''),
    # dmenuvids -> mpv via dmenu
    ('"dmenuvids"',
     '\t{ MODKEY|ShiftMask,             XK_a,          spawn,      SHCMD("mpv") },'),
    # dmenuaudioswitch -> audioswitch script
    ('"dmenuaudioswitch"',
     '\t{ MODKEY|ControlMask,           XK_a,          spawn,      SHCMD("audioswitch") },'),
    # rip -> remove
    ('"rip"', ''),
    # rec -> record script
    ('"rec"',
     '\t{ MODKEY,                               XK_r,  spawn,      SHCMD("record") },'),
    # define -> define script
    ('"define"',
     '\t{ MODKEY|ShiftMask,             XK_grave,      spawn,      SHCMD("define") },'),
    # wallpapermenu -> wallpapermenu script
    ('"wallpapermenu"',
     '\t{ MODKEY|ShiftMask,             XK_w,          spawn,      SHCMD("wallpapermenu") },'),
    # vb -> remove
    ('"vb"', ''),
    # dmenutemp -> temp script
    ('"dmenutemp"',
     '\t{ MODKEY|ShiftMask,             XK_F2,         spawn,      SHCMD("temp") },'),
    # phototransfer -> remove
    ('"phototransfer"', ''),
    # slock suspend -> systemctl suspend (slock still installed for F8)
    ('SHCMD("slock systemctl suspend -i")',
     'SHCMD("slock && systemctl suspend")'),
    # status-timer -> timer script
    ('SHCMD("status-timer")',
     'SHCMD("timer")'),
    # status-timer cleanup -> remove
    ('SHCMD("status-timer cleanup")', ''),
    # screenshot -> screenshot script (already correct, keep)
    # Add screenshot keybind explicitly (Super+Shift+s)
]

for fragment, replacement in replacements:
    if fragment in s:
        # Find the full line containing this fragment and replace it
        lines = s.split('\n')
        new_lines = []
        for line in lines:
            if fragment in line:
                if replacement:
                    new_lines.append(replacement)
                    print(f"  replaced: {fragment[:50]}")
                else:
                    print(f"  removed:  {fragment[:50]}")
                # skip original line
            else:
                new_lines.append(line)
        s = '\n'.join(new_lines)
    else:
        print(f"  NOT FOUND (already changed?): {fragment[:50]}")

# Add screenshot bind if not present
if 'XK_s.*screenshot' not in s and 'screenshot' not in s:
    screenshot = '\t{ MODKEY|ShiftMask, XK_s, spawn, SHCMD("screenshot") },'
    s = s.replace('TAGKEYS(                        XK_1,                      0)',
                  screenshot + '\n\tTAGKEYS(                        XK_1,                      0)')
    print("  added: screenshot bind (Super+Shift+S)")

open(path, 'w').write(s)
print("config.def.h patched.")
PYEOF

ok "dwm config.def.h patched."

# =============================================================================
# 6. BUILD SUCKLESS TOOLS
# =============================================================================
info "Building dwm..."
cd "$SUCKLESS/dwm"
rm -f config.h
sudo make clean install
ok "dwm installed."

info "Patching st config.h (keybinds + font)..."
cd "$SUCKLESS/st"

python3 - "$SUCKLESS/st/config.h" <<'STEOF'
import re, sys
path = sys.argv[1]
s = open(path).read()

# Change MODKEY from Alt (Mod1Mask) to Ctrl+Shift for standard terminal behaviour
# This makes copy/paste Ctrl+Shift+C / Ctrl+Shift+V
# and font size Ctrl+Shift+K / Ctrl+Shift+J
s = s.replace(
    '#define MODKEY Mod1Mask',
    '#define MODKEY (ControlMask|ShiftMask)'
)
s = s.replace(
    '#define TERMMOD (Mod1Mask|ShiftMask)',
    '#define TERMMOD (ControlMask|ShiftMask)'
)

# Set JetBrains Mono Nerd Font as default (matches bar font)
s = re.sub(
    r'static char \*font = "[^"]*";',
    'static char *font = "JetBrainsMono Nerd Font:pixelsize=15:antialias=true:autohint=true";',
    s
)

open(path, 'w').write(s)
print("  MODKEY: Alt -> Ctrl+Shift (copy=Ctrl+Shift+C, paste=Ctrl+Shift+V)")
print("  TERMMOD: Alt+Shift -> Ctrl+Shift (font size=Ctrl+Shift+K/J)")
print("  Font: JetBrainsMono Nerd Font")
STEOF

info "Building st..."
sudo make clean install
ok "st installed."

info "Building dmenu..."
cd "$SUCKLESS/dmenu"
rm -f config.h
sudo make clean install
ok "dmenu installed."

info "Building dwmblocks (with termhandler fix)..."
cd "$SUCKLESS/dwmblocks"
# Fix known gcc incompatibility: termhandler() needs int parameter
sed -i 's/void termhandler()/void termhandler(int signum)/' dwmblocks.c
# Write a clean blocks config using his statusbar scripts
cat > blocks.def.h <<'EOF'
static Block blocks[] = {
	/* command        interval  signal */
	{ "systemstats",  5,        0 },
	{ "disks",        30,       0 },
	{ "timedate",     60,       0 },
};

/* Maximum possible number of digits for an unsigned int */
#define CMDLENGTH 50
#define DELIMITER " "
#define CLICKABLE_BLOCKS
EOF
rm -f blocks.h
sudo make clean install
ok "dwmblocks installed."

# =============================================================================
# 7. INSTALL SCRIPTS TO PATH
# =============================================================================
info "Installing scripts to ~/.local/bin..."
mkdir -p "$HOME/.local/bin"

# Find all executable scripts and symlink to ~/.local/bin
# This makes them available from xinitrc (before zsh loads)
find "$SCRIPTS" -type f \
    ! -name "*.py" \
    ! -name "*.md" \
    ! -name "LICENSE" \
    ! -name "README*" \
    | while read -r script; do
        chmod +x "$script"
        name=$(basename "$script")
        ln -sf "$script" "$HOME/.local/bin/$name"
    done

# Add ~/.local/bin to PATH permanently
grep -q 'local/bin' "$HOME/.zshrc" 2>/dev/null \
    || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
grep -q 'local/bin' "$HOME/.bashrc" 2>/dev/null \
    || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"

ok "Scripts symlinked to ~/.local/bin."

# =============================================================================
# 8. COPY DOTS CONFIGS
# =============================================================================
info "Copying dots configs (picom, dunst, zsh, wal templates)..."
mkdir -p "$HOME/.config"

# Only copy dirs that exist in dots
for dir in picom dunst rmpc; do
    if [[ -d "$DOTS/.config/$dir" ]]; then
        cp -r "$DOTS/.config/$dir" "$HOME/.config/"
        ok "Copied $dir config."
    fi
done

# Copy wal templates if present
if [[ -d "$DOTS/.config/wal" ]]; then
    mkdir -p "$HOME/.config/wal"
    cp -r "$DOTS/.config/wal"/* "$HOME/.config/wal/" 2>/dev/null || true
    ok "Copied wal templates."
fi

# =============================================================================
# 9. ZSH + OH MY ZSH
# =============================================================================
info "Setting up zsh + oh-my-zsh..."

if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
        "" --unattended
    ok "oh-my-zsh installed."
else
    ok "oh-my-zsh already installed, skipping."
fi

# Plugins
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]; then
    git clone https://github.com/zsh-users/zsh-autosuggestions \
        "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi
if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]]; then
    git clone https://github.com/zsh-users/zsh-syntax-highlighting \
        "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
fi

# Write .zshrc (won't overwrite if already exists and has oh-my-zsh)
if ! grep -q "oh-my-zsh" "$HOME/.zshrc" 2>/dev/null; then
cat > "$HOME/.zshrc" <<'EOF'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git sudo zsh-autosuggestions zsh-syntax-highlighting)
source "$ZSH/oh-my-zsh.sh"

export PATH="$HOME/.local/bin:$PATH"
export EDITOR="nvim"

alias v="nvim"
alias vim="nvim"
alias ll="ls -la --color=auto"
alias update="sudo pacman -Syu"
alias reload="source ~/.zshrc"
EOF
ok ".zshrc written."
else
    # Ensure PATH is in existing .zshrc
    grep -q 'local/bin' "$HOME/.zshrc" \
        || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
    ok ".zshrc already configured, left intact."
fi

# Set zsh as default shell
if [[ "$SHELL" != "$(which zsh)" ]]; then
    chsh -s "$(which zsh)"
    ok "zsh set as default shell (takes effect on next login)."
else
    ok "zsh already default shell."
fi

# =============================================================================
# 10. WALLPAPER
# =============================================================================
info "Setting up wallpaper directory..."
mkdir -p "$HOME/Pictures/Wallpapers"

# Download a minimal dark wallpaper if none exists
if [[ -z "$(ls -A "$HOME/Pictures/Wallpapers" 2>/dev/null)" ]]; then
    warn "No wallpapers found. Creating a solid dark fallback..."
    convert -size 1920x1080 xc:'#1a1a2e' \
        "$HOME/Pictures/Wallpapers/default.png" 2>/dev/null \
        || magick -size 1920x1080 xc:'#1a1a2e' \
        "$HOME/Pictures/Wallpapers/default.png" 2>/dev/null \
        || warn "imagemagick couldn't create fallback — add a wallpaper to ~/Pictures/Wallpapers manually."
fi

WALLPAPER="$(find "$HOME/Pictures/Wallpapers" -maxdepth 2 -type f \( -name "*.png" -o -name "*.jpg" \) | head -1)"
ok "Wallpaper: ${WALLPAPER:-none found}"

# =============================================================================
# 11. WRITE .xinitrc
# =============================================================================
info "Writing ~/.xinitrc..."
cat > "$HOME/.xinitrc" <<XINITEOF
#!/bin/sh
# dwm session

# Keyboard layout
setxkbmap gb

# Compositor
picom --daemon 2>/dev/null &

# Notifications
dunst &

# Wallpaper + colour scheme
WALL="\$(find \$HOME/Pictures/Wallpapers -type f \\( -name '*.png' -o -name '*.jpg' \\) | head -1)"
if [ -n "\$WALL" ]; then
    feh --bg-scale "\$WALL" &
    wal -i "\$WALL" -n -q &
fi

# Status bar
dwmblocks &

# Launch dwm
exec dwm
XINITEOF
chmod +x "$HOME/.xinitrc"
ok ".xinitrc written."

# =============================================================================
# 12. KEYBOARD LAYOUT (xrdb)
# =============================================================================
info "Setting default xrdb colours (Nord fallback before pywal runs)..."
cat > "$HOME/.Xresources" <<'EOF'
dwm.normbordercolor: #4c566a
dwm.normbgcolor:     #2e3440
dwm.normfgcolor:     #d8dee9
dwm.selbordercolor:  #a3be8c
dwm.selbgcolor:      #b48ead
dwm.selfgcolor:      #eceff4
EOF
ok ".Xresources written with Nord defaults."

# =============================================================================
# 13. START ALIAS
# =============================================================================
info "Adding 'start' alias..."
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/start" <<'EOF'
#!/bin/sh
startx
EOF
chmod +x "$HOME/.local/bin/start"
ok "'start' command ready — type 'start' at TTY to launch dwm."

# =============================================================================
# DONE
# =============================================================================
cat <<DONE

${GRN}=== Install complete ===${RST}

${YLW}Next steps:${RST}

  1. ${BLU}Add a wallpaper${RST} to ~/Pictures/Wallpapers/ if you want
     something other than the solid dark fallback.

  2. ${BLU}Type 'startx'${RST} (or 'start') from the TTY to launch dwm.

  3. ${BLU}Once inside dwm:${RST}
       Super+Return       open terminal (st)
       Super+d            dmenu launcher
       Super+w            firefox
       Super+n            nvim
       Super+Shift+w      wallpaper picker (pywal theming)
       Super+Ctrl+\       reload colours after picking wallpaper
       Super+Shift+b      toggle bar
       Super+q            close window
       Super+Shift+Bksp   quit dwm

  4. ${BLU}Set a wallpaper via pywal${RST} (inside dwm):
       Press Super+Shift+W → pick a wallpaper → pywal generates colours
       Then press Super+Ctrl+\\ to reload xrdb colours in dwm

  5. ${BLU}Copy/paste in st${RST}: Ctrl+Shift+C to copy, Ctrl+Shift+V to paste

${YLW}Source files live in:${RST}
  ~/suckless/dwm     — edit config.def.h, rm config.h, make clean install
  ~/suckless/st      — edit config.h directly
  ~/suckless/dmenu
  ~/scripts          — his statusbar + helper scripts
  ~/dots             — picom, dunst, wal configs

DONE
