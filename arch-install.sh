#!/bin/bash

# Function to display messages
display_message() {
    echo -e "\033[1;32m$1\033[0m"
}

# Function to list available disks
list_disks() {
    display_message "Available disks:"
    lsblk -d -o NAME,SIZE
}

# Function to select a disk
select_disk() {
    list_disks
    read -p "Select a disk (e.g., /dev/sda): " SELECTED_DISK
}

# Function to detect the boot mode (UEFI or Legacy)
detect_boot_mode() {
    if [ -d /sys/firmware/efi ]; then
        BOOT_MODE="UEFI"
    else
        BOOT_MODE="Legacy"
    fi
}

# Function to create partitions for EFI, boot, root, swap, and home
create_partitions() {
    detect_boot_mode

    display_message "Creating partitions..."

    if [ "$BOOT_MODE" == "UEFI" ]; then
        read -p "Enter size for EFI partition (e.g., 512M): " EFI_SIZE
        parted --script $SELECTED_DISK \
            mklabel gpt \
            mkpart ESP fat32 1MiB $EFI_SIZE \
            set 1 boot on
        EFI_PARTITION="${SELECTED_DISK}1"
    else
        read -p "Enter size for boot partition (e.g., 512M): " BOOT_SIZE
        parted --script $SELECTED_DISK \
            mklabel msdos \
            mkpart primary ext4 1MiB $BOOT_SIZE \
            set 1 boot on
        BOOT_PARTITION="${SELECTED_DISK}1"
    fi

    read -p "Enter size for root partition (e.g., 50G): " ROOT_SIZE
    read -p "Enter size for swap partition (e.g., 2G): " SWAP_SIZE
    read -p "Enter size for home partition (leave empty for the rest of the space): " HOME_SIZE

    parted --script $SELECTED_DISK \
        mkpart primary ext4 $EFI_SIZE +$BOOT_SIZE \
        mkpart primary ext4 +$BOOT_SIZE +$ROOT_SIZE \
        mkpart primary linux-swap +$ROOT_SIZE +$SWAP_SIZE \
        mkpart primary ext4 +$SWAP_SIZE $HOME_SIZE

    if [ "$BOOT_MODE" == "UEFI" ]; then
        BOOT_PARTITION="${SELECTED_DISK}2"
    fi

    ROOT_PARTITION="${SELECTED_DISK}3"
    SWAP_PARTITION="${SELECTED_DISK}4"
    HOME_PARTITION="${SELECTED_DISK}5"
}

# Function to format partitions
format_partitions() {
    display_message "Formatting partitions..."
    if [ "$BOOT_MODE" == "UEFI" ]; then
        mkfs.fat -F32 $EFI_PARTITION
    else
        mkfs.ext4 $BOOT_PARTITION
    fi
    mkfs.ext4 $ROOT_PARTITION
    mkswap $SWAP_PARTITION
    swapon $SWAP_PARTITION
    mkfs.ext4 $HOME_PARTITION
}

# Function to mount partitions
mount_partitions() {
    display_message "Mounting partitions..."
    mount $ROOT_PARTITION /mnt
    mkdir -p /mnt/boot
    if [ "$BOOT_MODE" == "UEFI" ]; then
        mkdir -p /mnt/boot/efi
        mount $EFI_PARTITION /mnt/boot/efi
    else
        mount $BOOT_PARTITION /mnt/boot
    fi
    mkdir -p /mnt/home
    mount $HOME_PARTITION /mnt/home
}

# Function to install the base system
install_base_system() {
    display_message "Installing the base system..."
    pacstrap /mnt base linux linux-firmware
}

# Function to generate fstab
generate_fstab() {
    display_message "Generating fstab..."
    genfstab -U /mnt >> /mnt/etc/fstab
}

# Function to chroot into the new system
chroot_into_system() {
    display_message "Chrooting into the new system..."
    arch-chroot /mnt
}

# Function to set up user account
setup_user_account() {
    display_message "Setting up user account..."
    read -p "Enter your username: " USERNAME
    read -s -p "Enter your password: " PASSWORD

    # Create user and set password
    useradd -m -G wheel $USERNAME
    echo "$USERNAME:$PASSWORD" | chpasswd --root /mnt

    # Add user to sudoers file
    echo "$USERNAME ALL=(ALL) ALL" >> /mnt/etc/sudoers
}

# Function to detect CPU type (Intel or AMD)
detect_cpu_type() {
    CPU_VENDOR=$(lscpu | grep -oP '(?<=Vendor ID:\s+)(\S+)')
    if [ "$CPU_VENDOR" == "GenuineIntel" ]; then
        CPU_TYPE="Intel"
    elif [ "$CPU_VENDOR" == "AuthenticAMD" ]; then
        CPU_TYPE="AMD"
    else
        CPU_TYPE="Unknown"
    fi
}

# Function to install CPU-specific driver packages
install_cpu_drivers() {
    display_message "Installing CPU-specific driver packages for $CPU_TYPE..."
    if [ "$CPU_TYPE" == "Intel" ]; then
        # Install Intel microcode
        pacstrap /mnt intel-ucode
    elif [ "$CPU_TYPE" == "AMD" ]; then
        # Install AMD microcode
        pacstrap /mnt amd-ucode
    fi
}

# Function to install desktop environment
install_desktop_environment() {
    display_message "Select a desktop environment to install:"
    select DE in "1) GNOME" "2) KDE" "3) XFCE" "4) LXQt" "5) LXDE" "6) Cinnamon" "7) Mate" "8) Budgie" "9) i3"
    do
        case $DE in
            "1) GNOME")
                pacstrap /mnt gnome gnome-extra
                pacstrap /mnt gnome-software evince gnome-terminal gnome-calculator gnome-weather
                systemctl enable gdm
                break
                ;;
            "2) KDE")
                pacstrap /mnt plasma-meta
                pacstrap /mnt dolphin konsole okular kate kdenlive
                systemctl enable sddm
                break
                ;;
            "3) XFCE")
                pacstrap /mnt xfce4 xfce4-goodies
                pacstrap /mnt thunar xfce4-terminal mousepad
                systemctl enable lightdm
                break
                ;;
            "4) LXQt")
                pacstrap /mnt lxqt
                pacstrap /mnt pcmanfm-qt qterminal lximage-qt
                systemctl enable sddm
                break
                ;;
            "5) LXDE")
                pacstrap /mnt lxde
                pacstrap /mnt pcmanfm lxterminal leafpad
                systemctl enable lxdm
                break
                ;;
            "6) Cinnamon")
                pacstrap /mnt cinnamon
                pacstrap /mnt nemo gnome-terminal gedit
                systemctl enable lightdm
                break
                ;;
            "7) Mate")
                pacstrap /mnt mate mate-extra
                pacstrap /mnt caja mate-terminal pluma
                systemctl enable lightdm
                break
                ;;
            "8) Budgie")
                pacstrap /mnt budgie-desktop
                pacstrap /mnt nautilus gnome-terminal gedit
                systemctl enable lightdm
                break
                ;;
            "9) i3")
                pacstrap /mnt i3 dmenu
                systemctl enable lightdm
                break
                ;;
            *)
                echo "Invalid choice. Please select a valid desktop environment."
                ;;
        esac
    done
}

# Function to install additional software based on user input
install_additional_software() {
    display_message "Enter a list of additional software to install (space-separated):"
    read -p "e.g., firefox vscode base-devel: " ADDITIONAL_APPS
    pacstrap /mnt $ADDITIONAL_APPS
}

# Function to ask if the user wants to install security tools
ask_security_tools() {
    read -p "Do you want to install security tools for ethical hacking and penetration testing? (y/n): " INSTALL_SECURITY_TOOLS
    if [ "$INSTALL_SECURITY_TOOLS" == "y" ]; then
        display_message "Installing security tools..."
        pacstrap /mnt nmap metasploit aircrack-ng wireshark john hydra wifite

        display_message "Security tools installed successfully."
    fi
}

# Function to configure firewall (ufw)
configure_firewall() {
    display_message "Configuring firewall (ufw)..."
    pacstrap /mnt ufw
    arch-chroot /mnt ufw enable
    arch-chroot /mnt systemctl enable ufw
}

# Function to enable automatic updates
enable_automatic_updates() {
    display_message "Enabling automatic updates..."
    arch-chroot /mnt pacman -S --noconfirm pacman-contrib
    echo 'CheckSpace' >> /mnt/etc/pacman.conf
    echo 'ILoveCandy' >> /mnt/etc/pacman.conf
    echo 'Color' >> /mnt/etc/pacman.conf
}

# Function to configure sudoers file
configure_sudoers() {
    display_message "Configuring sudoers file..."
    echo "Defaults !tty_tickets" >> /mnt/etc/sudoers
    echo "Defaults timestamp_timeout=15" >> /mnt/etc/sudoers
}

# Function to disable root login
disable_root_login() {
    display_message "Disabling root login..."
    arch-chroot /mnt passwd -l root
}

# Function to enable hardening features
enable_hardening() {
    display_message "Enabling hardening features..."
    arch-chroot /mnt pacman -S --noconfirm harden-clients harden-servers
    arch-chroot /mnt systemctl enable harden-early.service
    arch-chroot /mnt systemctl enable harden-sshd.service
}

# Function to ask if the user wants to add the BlackArch repository
ask_blackarch_repo() {
    read -p "Do you want to add the BlackArch repository to Arch Linux? (y/n): " ADD_BLACKARCH_REPO
    if [ "$ADD_BLACKARCH_REPO" == "y" ]; then
        echo "[blackarch]" >> /mnt/etc/pacman.conf
        echo "Server = https://blackarch.org/blackarch/\$repo/os/\$arch" >> /mnt/etc/pacman.conf
    fi
}

# Main installation script
main_installation() {
    select_disk
    create_partitions
    format_partitions
    mount_partitions
    install_base_system
    generate_fstab
    chroot_into_system
    setup_user_account
    detect_cpu_type
    install_cpu_drivers
    install_desktop_environment
    install_additional_software
    ask_blackarch_repo
    ask_security_tools
    configure_firewall
    enable_automatic_updates
    configure_sudoers
    disable_root_login
    enable_hardening
    display_message "Installation completed successfully!"
}

# Run the main installation script
main_installation

