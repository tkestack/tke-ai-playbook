#!/bin/bash

################################################################################
# Ubuntu 24.04 Kernel Upgrade Script
# Target: linux-image-6.8.0-87-generic
################################################################################

set -euo pipefail

# Configuration
readonly TARGET_KERNEL="6.8.0-87-generic"
readonly LOG_FILE="/var/log/kernel_upgrade_$(date +%Y%m%d_%H%M%S).log"
readonly MIN_BOOT_SPACE_MB=512

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

################################################################################
# Functions
################################################################################

log() {
    local level=$1
    shift
    local color=${NC}
    case $level in
        INFO)  color=${GREEN} ;;
        WARN)  color=${YELLOW} ;;
        ERROR) color=${RED} ;;
    esac
    echo -e "${color}[$level]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

check_root() {
    [[ $EUID -eq 0 ]] || { log ERROR "Must run as root"; exit 1; }
}

check_os() {
    grep -q "Ubuntu 24.04" /etc/os-release || {
        log WARN "Designed for Ubuntu 24.04, current OS may differ"
        read -p "Continue? (yes/no): " -r
        [[ $REPLY =~ ^[Yy]es$ ]] || { log INFO "Cancelled"; exit 0; }
    }
}

check_disk_space() {
    # Note: No separate /boot partition, using root partition
    local available_mb=$(df / | tail -1 | awk '{print int($4/1024)}')
    
    if [[ $available_mb -lt $MIN_BOOT_SPACE_MB ]]; then
        log ERROR "Insufficient disk space. Available: ${available_mb}MB, Required: ${MIN_BOOT_SPACE_MB}MB"
        exit 1
    fi
    log INFO "Disk space check passed: ${available_mb}MB available"
}

get_current_kernel() {
    CURRENT_KERNEL=$(uname -r)
    log INFO "Current kernel: $CURRENT_KERNEL"
}

install_kernel() {
    log INFO "Installing kernel $TARGET_KERNEL..."
    
    apt update >> "$LOG_FILE" 2>&1 || { log ERROR "apt update failed"; exit 1; }
    
    # Check availability
    apt-cache search "linux-image-$TARGET_KERNEL" | grep -q "linux-image-$TARGET_KERNEL" || {
        log ERROR "Kernel $TARGET_KERNEL not found in repositories"
        exit 1
    }
    
    # Install packages
    local packages=(
        "linux-image-$TARGET_KERNEL"
        "linux-headers-$TARGET_KERNEL"
        "linux-modules-$TARGET_KERNEL"
        "linux-modules-extra-$TARGET_KERNEL"
    )
    
    DEBIAN_FRONTEND=noninteractive apt install -y "${packages[@]}" >> "$LOG_FILE" 2>&1 || {
        log ERROR "Kernel installation failed"
        exit 1
    }
    
    log INFO "Kernel installed successfully"
}

update_grub() {
    log INFO "Updating GRUB configuration..."
    update-grub >> "$LOG_FILE" 2>&1 || log WARN "GRUB update had warnings"
    
    grep -q "vmlinuz-$TARGET_KERNEL" /boot/grub/grub.cfg && \
        log INFO "GRUB configuration verified" || \
        log WARN "Target kernel not found in GRUB config"
}

cleanup_old_kernels() {
    log INFO "Checking old kernels..."
    
    local old_kernels=$(dpkg -l | \
        awk '/^ii.*linux-image-[0-9]/ && !/'"$TARGET_KERNEL"'/ && !/'"$CURRENT_KERNEL"'/ {print $2}')
    
    if [[ -z "$old_kernels" ]]; then
        log INFO "No old kernels to remove"
        return
    fi
    
    log INFO "Found old kernels:"
    echo "$old_kernels"
    read -p "Remove old kernels? (yes/no): " -r
    
    if [[ $REPLY =~ ^[Yy]es$ ]]; then
        echo "$old_kernels" | xargs apt remove -y >> "$LOG_FILE" 2>&1
        apt autoremove -y >> "$LOG_FILE" 2>&1
        log INFO "Old kernels removed"
    fi
}

create_verification_script() {
    cat > /root/verify_kernel.sh << EOF
#!/bin/bash
EXPECTED="$TARGET_KERNEL"
CURRENT=\$(uname -r)

if [[ "\$CURRENT" == "\$EXPECTED" ]]; then
    echo "[SUCCESS] Kernel upgraded to \$CURRENT"
    rm -f /root/verify_kernel.sh
else
    echo "[FAILED] Current: \$CURRENT, Expected: \$EXPECTED"
    exit 1
fi
EOF
    chmod +x /root/verify_kernel.sh
    log INFO "Verification script created: /root/verify_kernel.sh"
}

prompt_reboot() {
    cat << EOF

========================================
Kernel Upgrade Summary
========================================
Previous: $CURRENT_KERNEL
Target:   $TARGET_KERNEL
Log:      $LOG_FILE
========================================

EOF
    
    read -p "Reboot now? (yes/no): " -r
    if [[ $REPLY =~ ^[Yy]es$ ]]; then
        log INFO "Rebooting..."
        sleep 3
        reboot
    else
        log WARN "Reboot required. Run manually: sudo reboot"
        echo "After reboot, verify with: sudo /root/verify_kernel.sh"
    fi
}

################################################################################
# Main
################################################################################

main() {
    log INFO "Starting kernel upgrade to $TARGET_KERNEL"
    
    check_root
    check_os
    check_disk_space
    get_current_kernel
    
    # Check if already on target kernel
    if [[ "$CURRENT_KERNEL" == "$TARGET_KERNEL" ]]; then
        log INFO "Already running $TARGET_KERNEL"
        exit 0
    fi
    
    install_kernel
    update_grub
    create_verification_script
    cleanup_old_kernels
    prompt_reboot
    
    log INFO "Upgrade completed"
}

main "$@"
