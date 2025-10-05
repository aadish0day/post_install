#!/usr/bin/env bash
set -euo pipefail

# Update system and packages
echo "Updating system and packages..."
sudo pacman -Sy --noconfirm
sudo pacman -S --needed reflector --noconfirm

# Prompt user to configure mirrors
read -rp "Do you want to configure the mirror list for India using reflector? (y/n): " configure_mirrors
if [[ $configure_mirrors =~ ^[Yy]$ ]]; then
	echo "Configuring mirror list for India..."
	sudo reflector --latest 5 --country India --protocol https --sort rate --save /etc/pacman.d/mirrorlist
else
	echo "Skipping mirror configuration."
fi

# Update system and packages after mirror update
sudo pacman -Syu --noconfirm

# Function to install packages if not already installed
install_if_needed() {
	local pkg
	local failures=()
	local to_install=()

	for pkg in "$@"; do
		if ! pacman -Qi "$pkg" &>/dev/null; then
			to_install+=("$pkg")
		else
			echo "$pkg is already installed. Skipping..."
		fi
	done

	if [ ${#to_install[@]} -gt 0 ]; then
		echo "Installing: ${to_install[*]}"
		if ! sudo pacman -S --noconfirm --needed "${to_install[@]}"; then
			echo "Some packages failed to install, checking..."
			for pkg in "${to_install[@]}"; do
				if ! pacman -Qi "$pkg" &>/dev/null; then
					echo "Failed to install $pkg"
					failures+=("$pkg")
				fi
			done
			if [ ${#failures[@]} -gt 0 ]; then
				echo "Failed to install the following packages: ${failures[*]}"
				return 1
			fi
		fi
	fi
}

# Function to install paru
install_paru() {
	echo "Installing paru..."
	if ! pacman -Qq base-devel &>/dev/null; then
		echo "Installing base-devel package group..."
		sudo pacman -S --needed base-devel git --noconfirm
	fi

	cd /tmp || exit 1

	if ! git clone https://aur.archlinux.org/paru-bin.git; then
		echo "Failed to clone paru-bin repository."
		cd - || exit 1
		return 1
	fi

	cd paru-bin || {
		echo "Failed to enter paru-bin directory."
		cd - || exit 1
		return 1
	}

	makepkg -si --noconfirm || {
		echo "Failed to build and install paru."
		cd - || exit 1
		return 1
	}

	cd - || exit 1
	rm -rf /tmp/paru-bin
	echo "paru has been successfully installed."
}

# Function to install AUR packages
install_aur_packages() {
	local pkg
	for pkg in "$@"; do
		if ! pacman -Qi "$pkg" &>/dev/null; then
			if [[ "$pkg" == "i3lock-color" ]] && pacman -Qq "i3lock" &>/dev/null; then
				sudo pacman -Rns --noconfirm "i3lock"
			fi
			paru -S --noconfirm --needed "$pkg" || echo "Failed to install $pkg"
		else
			echo "$pkg is already installed."
		fi
	done
}

# List of general packages
packages=(
	android-tools aria2 atool bat cantarell-fonts chromaprint doxygen duf fastfetch fd ffmpegthumbnailer
	fluidsynth fzf gcc gettext git git-lfs gst-libav gst-plugins-ugly gvfs gvfs-afc gvfs-gphoto2 gvfs-mtp gvfs-nfs
	gvfs-smb highlight htop img2pdf imagemagick inxi jq jpegoptim kitty less libavtp libdca libgme liblrdf libltc
	libtool linux-headers lsd lz4 make man-db man-pages maven mediainfo mjpegtools mkinitcpio mpv mpv-mpris ncdu
	neovim nodejs noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra npm obs-studio p7zip pacman-contrib pacutils
	papirus-icon-theme parallel pipewire pipewire-alsa pipewire-audio pipewire-jack pipewire-pulse pipewire-zeroconf
	pkgfile plocate playerctl pv qalculate-qt qbittorrent ripgrep sd spandsp starship soundtouch svt-hevc tar
	tree tree-sitter-cli trash-cli tmux ttf-jetbrains-mono ttf-jetbrains-mono-nerd tumbler unzip wireplumber xz
	yazi yt-dlp zathura zathura-cb zathura-djvu zathura-pdf-poppler zathura-ps zip zoxide zsh zstd
)

# List of gaming packages
gaming_packages=(
	alsa-lib alsa-plugins gamemode giflib gnutls gst-plugins-base-libs gtk3 innoextract
	lib32-alsa-lib lib32-alsa-plugins lib32-gamemode lib32-giflib lib32-gnutls
	lib32-gst-plugins-base-libs lib32-gtk3 lib32-libpulse lib32-libva lib32-libxcomposite
	lib32-ocl-icd lib32-sdl2 lib32-sqlite lib32-v4l-utils lib32-vkd3d lib32-vulkan-icd-loader
	libayatana-appindicator libpulse libva libxcomposite ocl-icd python-protobuf sdl2 sqlite
	v4l-utils vkd3d vulkan-icd-loader wine-gecko wine-mono wine-staging winetricks
)

# List of X11 tiling desktop essentials
x11_tilling_depen=(
	accountsservice acpi alsa-firmware archlinux-xdg-menu arandr awesome-terminal-fonts
	bluez bluez-utils blueman brightnessctl clipmenu dex ding-libs dmidecode dmraid dmenu
	dnssec-anchors dracut dunst feh flameshot fsarchiver gammastep gssproxy gtksourceview3
	haveged hdparm hwdetect hwinfo inetutils jemalloc libgsf libinstpatch liblqr
	libmaxminddb libmbim libopenraw libpipeline libqmi libqrtr-glib libwnck3 libx86emu
	libxres logrotate lsb-release modemmanager netctl network-manager-applet nitrogen ntp
	numlockx nwg-look os-prober perl-xml-writer picom polkit-gnome polybar poppler-glib
	ppp python-annotated-types python-defusedxml python-orjson python-pyaml python-pydantic
	python-pydantic-core python-pyqt5 python-pyqt5-sip python-typing_extensions rofi scrot
	sg3_utils sysstat systemd-resolvconf tcl thunar thunar-archive-plugin thunar-volman
	ttf-opensans usb_modeswitch usbutils wmname xarchiver xbindkeys xclip xdg-desktop-portal
	xdg-desktop-portal-gtk xdg-user-dirs-gtk xfce4-terminal xorg-xbacklight xorg-xdpyinfo xss-lock
)

# List of Wayland tiling desktop essentials
wayland_tilling_depen=(
	cliphist foot grim kanshi mako nm-connection-editor seatd slurp sway swaybg swayidle swaylock waybar
	wf-recorder wl-clipboard wofi xdg-desktop-portal xdg-desktop-portal-wlr
)

# List of KDE Plasma desktop environment packages
kde_plasma_packages=(

)

# List of AUR packages
aur_packages=(
	"advcpmv"
	"ani-cli"
	"dracula-gtk-theme"
	"hakuneko-desktop"
	"i3lock-color"
	"thorium-browser-bin"
	"vesktop-bin"
	"visual-studio-code-bin"
	# "wlogout"
	# "dxvk-bin"
	# "moc"
)

# List of ASUS specific packages
asus_packages=(
	"vulkan-amdgpu-pro"
	"lib32-vulkan-amdgpu-pro"
	"amdgpu-pro-oglp"
	"lib32-amdgpu-pro-oglp"
	"opencl-headers"
	"amf-amdgpu-pro"
	# "opencl-amd"
)

# Install base packages
echo "Installing base packages..."
install_if_needed "${packages[@]}"

# Initialize Git LFS for the current user
if command -v git &>/dev/null && command -v git-lfs &>/dev/null; then
	echo "Initializing Git LFS..."
	git lfs install --skip-repo
fi

# Ask user for gaming package installation
read -rp "Do you want to install gaming packages? (y/n): " install_gaming
if [[ $install_gaming =~ ^[Yy]$ ]]; then
	install_if_needed "${gaming_packages[@]}"
else
	echo "Skipping gaming package installation."
fi

# Ask user to install X11 tiling-specific packages
read -rp "Do you want to install X11 tiling-specific packages? (y/n): " install_x11
if [[ $install_x11 =~ ^[Yy]$ ]]; then
	install_if_needed "${x11_tilling_depen[@]}"
else
	echo "Skipping X11 tiling package installation."
fi

# Ask user to install Wayland tiling-specific packages
read -rp "Do you want to install Wayland tiling-specific packages? (y/n): " install_wayland
if [[ $install_wayland =~ ^[Yy]$ ]]; then
	install_if_needed "${wayland_tilling_depen[@]}"
else
	echo "Skipping Wayland tiling package installation."
fi

# Ask user to install KDE Plasma desktop environment
read -rp "Do you want to install KDE Plasma desktop environment? (y/n): " install_kde
if [[ $install_kde =~ ^[Yy]$ ]]; then
	install_if_needed "${kde_plasma_packages[@]}"
else
	echo "Skipping KDE Plasma desktop environment installation."
fi

# Install paru if not present
if ! command -v paru &>/dev/null; then
	install_paru || {
		echo "Failed to install paru. AUR packages will not be installed."
		exit 1
	}
fi

# Install AUR packages
echo "Installing AUR packages..."
install_aur_packages "${aur_packages[@]}"

# Ask if the user wants to install ASUS specific packages
read -rp "Do you want to install ASUS specific drivers? (y/n): " install_asus
if [[ $install_asus =~ ^[Yy]$ ]]; then
	install_aur_packages "${asus_packages[@]}"
else
	echo "Skipping ASUS specific packages."
fi

# Enable and restart services
echo "Enabling and starting services..."
# systemctl enable --now bluetooth.service
if systemctl list-unit-files | grep -q "dbus-broker.service"; then
	systemctl --user enable --now dbus-broker.service
elif systemctl list-unit-files | grep -q "dbus-daemon.service"; then
	systemctl --user enable --now dbus-daemon.service
else
	echo "No dbus backend service found, skipping..."
fi

# Enable SDDM if KDE Plasma is installed
if pacman -Qi sddm &>/dev/null; then
	echo "Enabling SDDM display manager..."
	sudo systemctl enable --now sddm.service
fi

if systemctl --user list-unit-files | grep -q "xdg-desktop-portal.service"; then
	systemctl --user start xdg-desktop-portal.service
fi
if systemctl --user list-unit-files | grep -q "xdg-desktop-portal-gtk.service"; then
	systemctl --user start xdg-desktop-portal-gtk.service
fi
if systemctl --user list-unit-files | grep -q "xdg-desktop-portal-wlr.service"; then
	systemctl --user start xdg-desktop-portal-wlr.service
fi

# Ask to set Zathura as default PDF viewer
read -rp "Do you want to set Zathura as the default PDF viewer? (y/n): " set_pdf_default
if [[ $set_pdf_default =~ ^[Yy]$ ]]; then
	if command -v zathura &>/dev/null; then
		echo "Setting Zathura as the default PDF viewer..."
		xdg-mime default org.pwmt.zathura.desktop application/pdf
	else
		echo "Zathura is not installed; skipping default PDF assignment."
	fi
else
	echo "Skipping setting default PDF viewer."
fi

# Set thorium-browser as default browser if installed
if command -v thorium-browser &>/dev/null; then
	echo "Setting thorium-browser as the default browser..."
	xdg-settings set default-web-browser thorium-browser.desktop
	current_browser=$(xdg-settings get default-web-browser)
	echo "Current default browser: $current_browser"
fi

# Change default shell to zsh if installed
if command -v zsh &>/dev/null; then
	echo "Changing default shell to zsh..."
	chsh -s "$(command -v zsh)" "$USER"
fi

echo "Installation process completed! Please reboot your system."
