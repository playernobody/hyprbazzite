# ===========================================================================
# HyprBazzite - Custom bootc image based on Bazzite with Hyprland
# ===========================================================================

# ---------------------------------------------------------------------------
# Stage 1: Download external assets (fonts, themes)
# ---------------------------------------------------------------------------
FROM fedora:latest AS assets

# Install download utilities
RUN dnf5 -y install curl unzip && \
    dnf5 -y clean all

# JetBrains Mono Nerd Font
RUN curl -fsSL -o /tmp/jb-mono.zip \
    https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/JetBrainsMono.zip && \
    unzip -o /tmp/jb-mono.zip -d /fonts/ && \
    rm -f /tmp/jb-mono.zip

# Dracula GTK Theme
RUN mkdir -p /themes/Dracula && \
    curl -fsSL -L https://github.com/dracula/gtk/archive/master.zip -o /tmp/dracula-gtk.zip && \
    unzip -q /tmp/dracula-gtk.zip -d /tmp && \
    mv /tmp/gtk-master/* /themes/Dracula/ && \
    rm -rf /tmp/dracula-gtk.zip /tmp/gtk-master

# Dracula Qt5 Color Scheme
RUN mkdir -p /qt5ct/colors && \
    curl -fsSL -o /qt5ct/colors/Dracula.conf \
    https://raw.githubusercontent.com/dracula/qt5/master/Dracula.conf

# ---------------------------------------------------------------------------
# Stage 2: Build context (for reference, not copied into final image)
# ---------------------------------------------------------------------------
FROM scratch AS ctx
COPY build_files /

# ===========================================================================
# Stage 3: Final Image
# ===========================================================================
FROM ghcr.io/ublue-os/bazzite-nvidia-open:stable

# Build arguments for versioning
ARG SHA_HEAD_SHORT=unknown
ARG BUILD_STAMP

# ---------------------------------------------------------------------------
# Step 1: Image metadata and build identification
# ---------------------------------------------------------------------------
RUN build_id="${BUILD_STAMP:-stable.$(date -u +%Y%m%d)-${SHA_HEAD_SHORT:-unknown}}" && \
    echo "TBLUE_BUILD_ID=$build_id" >> /usr/lib/os-release && \
    sed -i "s/^PRETTY_NAME=.*/PRETTY_NAME=\"HyprBazzite ($build_id)\"/" /usr/lib/os-release && \
    sed -i 's/^NAME=.*/NAME="HyprBazzite"/' /usr/lib/os-release

# ---------------------------------------------------------------------------
# Step 2: Enable COPR repositories
# ---------------------------------------------------------------------------
RUN --mount=type=cache,dst=/var/cache \
    dnf5 -y copr enable lionheartp/Hyprland && \
    dnf5 -y copr enable sdegler/hyprland && \
    dnf5 -y copr enable erikreider/SwayNotificationCenter && \
    dnf5 -y copr enable fed500/wvkbd && \
    dnf5 -y copr enable hhd-dev/hhd && \
    dnf5 -y copr enable atim/starship && \
    dnf5 -y clean all

# ---------------------------------------------------------------------------
# Step 3: Remove Plasma desktop packages
# ---------------------------------------------------------------------------
RUN --mount=type=cache,dst=/var/cache \
    dnf5 -y remove --setopt=protected_packages= \
    akonadi-server kate dolphin konsole khelper okular\
    "kwin*" "kdepim*" "konqueror*" "ark*" "kwrite*" "fedora-chromium-config-kde*" "kcm-plasmalogin*" "kscreen*" "kscreenlocker*" "powerdevil*" "steamdeck-kde-presets-desktop*" "kwalletmanager5*" "kamera*" "kedit*" "kinfocenter*" "kwrite*" "krdc*" "krdp*" "krfb*" "kio-gdrive*" "kio-extras*" "kio-admin*" "kdeplasma-addons*" "kdesu*" "libkgapi*" "mariadb*" "kdsoap*" "colord-kde*" "signon-kwallet*" "libkcddb*" "libkexiv2*" "libkgapi*" "kcm*" "layer-shell-qt*" "kdeconnect*" "kdeconnect*" "pam-kwallet*" "plasma-*" "kde-*" "kf5-*" "kf6-*" && \
    dnf5 -y clean all

# ---------------------------------------------------------------------------
# Step 4: Install HyprBazzite packages
# ---------------------------------------------------------------------------
RUN --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    dnf5 -y install --skip-unavailable \
    # Core Hyprland & Session Management
    hyprland hyprland-qtutils hyprland-guiutils uwsm hyprland-uwsm hyprlock hypridle hyprpicker \
    # Launchers, Bar & Notifications
    waybar rofi SwayNotificationCenter wlogout \
    # Wallpaper 
    awww matugen \
    # File Management (Nemo + Thumbnails + GVFS for mounting)
    nemo nemo-fileroller tumbler gvfs gvfs-mtp gvfs-gphoto2 \
    # Theming & Icons
    qt5ct qt6ct kvantum nwg-look jetbrains-mono jetbrains-mono-fonts breeze-icon-theme \
    # System Utilities
    blueman pavucontrol network-manager-applet lxqt-policykit brightnessctl \
    # Security
    gnome-keyring seahorse libsecret gcr \
    # Shell & CLI Tools
    zsh starship lsd git chezmoi kitty tmux fastfetch jq ripgrep neovim \
    # Media & Clipboard
    wl-clipboard cliphist playerctl imv mpv grim slurp swappy grimblast \
    # Hardware & Gaming
    lact openrgb openrgb-udev-rules gparted btop lutris rom-properties steam-devices \
    # Tools 
    hhd adjustor hhd-ui wvkbd xdg-desktop-portal-hyprland sddm wayland-protocols libdecor \
    && dnf5 -y autoremove && dnf5 -y clean all   

# ---------------------------------------------------------------------------
# Step 5: Copy system files and assets into image
# ---------------------------------------------------------------------------
COPY system_files/usr/ /usr/
COPY --from=assets /fonts /usr/share/fonts/
COPY --from=assets /themes/Dracula /usr/share/themes/Dracula
COPY --from=assets /qt5ct/colors /usr/share/qt5ct/colors

# ---------------------------------------------------------------------------
# Step 6: Fix terra-mesa GPG key issue
# ---------------------------------------------------------------------------
RUN sed -i 's/^gpgcheck=1/gpgcheck=0/' /etc/yum.repos.d/terra-mesa.repo 2>/dev/null || true && \
    sed -i 's/^repo_gpgcheck=1/repo_gpgcheck=0/' /etc/yum.repos.d/terra-mesa.repo 2>/dev/null || true

# ---------------------------------------------------------------------------
# Step 7: Set up user config symlinks (bootc-compliant)
# ---------------------------------------------------------------------------
RUN mkdir -p /usr/share/hyprbazzite/config && \
    cp -af /usr/lib/hyprbazzite/skel/.config/. /usr/share/hyprbazzite/config/ && \
    mkdir -p /etc/skel/.config && \
    for dir in $(ls /usr/share/hyprbazzite/config/); do \
        ln -sf /usr/share/hyprbazzite/config/$dir /etc/skel/.config/$dir; \
    done

# ---------------------------------------------------------------------------
# Step 8: Set permissions on scripts and executables
# ---------------------------------------------------------------------------
RUN chmod +x /usr/bin/wallpaper-cycle && \
    # Ensure all libexec scripts are executable
    find /usr/libexec/ -type f -exec chmod +x {} + && \
    # Ensure all Hyprland scripts are executable
    find /usr/lib/hyprbazzite/hypr/scripts/ -type f -exec chmod +x {} +

# ---------------------------------------------------------------------------
# Step 9: Configure user defaults, environment, and systemd presets
# ---------------------------------------------------------------------------
RUN usermod -s /bin/zsh root && \
    mkdir -p /etc/default && \
    echo 'SHELL=/bin/zsh' >> /etc/default/useradd && \
    # Set Qt platform theme (gtk3 for consistent theme propagation via GTK settings)
    mkdir -p /usr/lib/environment.d/ && \
    echo 'QT_QPA_PLATFORMTHEME=gtk3' >> /usr/lib/environment.d/10-qtct.conf && \
    echo 'QT_STYLE_OVERRIDE=Fusion' >> /usr/lib/environment.d/10-qtct.conf && \
    # Build font cache
    fc-cache -f && \
    # Set session file permissions
    chmod 0644 /usr/share/wayland-sessions/hyprland.desktop && \
    # Set SDDM theme permissions
    chmod -R 0755 /usr/share/sddm/themes && \
    chmod 0644 /usr/share/sddm/themes/hyprlockish/* && \
    # Enable systemd services via preset
    mkdir -p /usr/lib/systemd/system-preset && \
    echo "enable hhd.service" > /usr/lib/systemd/system-preset/50-hyprbazzite.preset && \
    echo "enable sddm.service" >> /usr/lib/systemd/system-preset/50-hyprbazzite.preset && \
    echo "enable tblue-hibernate-setup.service" >> /usr/lib/systemd/system-preset/50-hyprbazzite.preset && \
    # Copy dconf theme settings
    mkdir -p /etc/dconf/db/distro.d/ && \
    cp /usr/lib/hyprbazzite/dconf/db/distro.d/00-dracula-theme /etc/dconf/db/distro.d/

# ---------------------------------------------------------------------------
# Step 10: Cleanup - remove build artifacts from /var
# ---------------------------------------------------------------------------
RUN rm -rf /var/lib/flatpak/* && \
    rm -rf /var/cache/libdnf5/* && \
    rm -rf /var/lib/dnf && \
    rm -rf /var/log/dnf* && \
    rm -rf /var/log/hawkey.log && \
    find /run -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true && \
    find /tmp -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true && \
    # Validate final image
    bootc container lint
