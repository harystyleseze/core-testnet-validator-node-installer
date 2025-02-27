#!/bin/bash

# Source utils
source ./utils.sh

# Required specifications
REQUIRED_CPU_CORES=4
REQUIRED_RAM_GB=8
REQUIRED_DISK_GB=1.024  # 1 TB
REQUIRED_INTERNET_SPEED=10  # 10 Mbps

check_hardware_requirements() {
    log_message "Starting hardware requirements check"
    
    # Install required tools if not present
    if ! command -v speedtest-cli &> /dev/null; then
        show_progress "Installing speedtest-cli..."
        if [ -f /etc/debian_version ]; then
            sudo apt-get update && sudo apt-get install -y speedtest-cli
        elif [ -f /etc/redhat-release ]; then
            sudo yum install -y speedtest-cli
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            brew install speedtest-cli
        else
            show_error "Could not install speedtest-cli. Please install it manually."
            return 1
        fi
    fi

    # Get system information
    get_system_info

    # Create temporary file for dialog checklist
    TEMP_FILE=$(mktemp)

    # Add header to temp file
    echo -e "\n  System Requirements Check\n  ────────────────────────\n" >> "$TEMP_FILE"

    # Check CPU cores
    if [ "$CPU_CORES" -ge "$REQUIRED_CPU_CORES" ]; then
        echo -e "  ✓ CPU Cores:        ${CPU_CORES} cores\n    Required:         ${REQUIRED_CPU_CORES} cores\n" >> "$TEMP_FILE"
    else
        echo -e "  ✗ CPU Cores:        ${CPU_CORES} cores\n    Required:         ${REQUIRED_CPU_CORES} cores\n" >> "$TEMP_FILE"
        FAILED=1
    fi

    # Check RAM
    if [ "$TOTAL_RAM" -ge "$REQUIRED_RAM_GB" ]; then
        echo -e "  ✓ Memory:           ${TOTAL_RAM} GB\n    Required:         ${REQUIRED_RAM_GB} GB\n" >> "$TEMP_FILE"
    else
        echo -e "  ✗ Memory:           ${TOTAL_RAM} GB\n    Required:         ${REQUIRED_RAM_GB} GB\n" >> "$TEMP_FILE"
        FAILED=1
    fi

    # Check Disk Space
    if [ "${FREE_DISK%.*}" -ge "$REQUIRED_DISK_GB" ]; then
        echo -e "  ✓ Storage:          ${FREE_DISK} GB\n    Required:         ${REQUIRED_DISK_GB} GB\n" >> "$TEMP_FILE"
    else
        echo -e "  ✗ Storage:          ${FREE_DISK} GB\n    Required:         ${REQUIRED_DISK_GB} GB\n" >> "$TEMP_FILE"
        FAILED=1
    fi

    # Check Internet Speed
    if [ -n "$INTERNET_SPEED" ] && [ "${INTERNET_SPEED%.*}" -ge "$REQUIRED_INTERNET_SPEED" ]; then
        echo -e "  ✓ Internet Speed:   ${INTERNET_SPEED} Mbps\n    Required:         ${REQUIRED_INTERNET_SPEED} Mbps\n" >> "$TEMP_FILE"
    else
        echo -e "  ✗ Internet Speed:   ${INTERNET_SPEED:-0} Mbps\n    Required:         ${REQUIRED_INTERNET_SPEED} Mbps\n" >> "$TEMP_FILE"
        FAILED=1
    fi

    # Display results with new styling
    dialog --colors \
           --title " System Requirements " \
           --backtitle "Core Node Installer" \
           --cr-wrap \
           --no-collapse \
           --textbox "$TEMP_FILE" 20 50

    # Clean up
    rm -f "$TEMP_FILE"

    if [ "$FAILED" = "1" ]; then
        dialog --colors \
               --title " Requirements Not Met " \
               --backtitle "Core Node Installer" \
               --msgbox "\n  ⚠️  System requirements not met\n\n  Please ensure your system meets the\n  minimum requirements before proceeding.\n\n  Review the previous screen for details." \
               12 45
        log_message "Hardware check failed"
        return 1
    fi

    dialog --colors \
           --title " Requirements Met " \
           --backtitle "Core Node Installer" \
           --msgbox "\n  ✓ All system requirements met!\n\n  Your system is ready for\n  Core Node installation.\n\n  Press ENTER to continue." \
           12 45
    log_message "Hardware check passed"
    return 0
}

# Run hardware check if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_dialog
    check_hardware_requirements
fi
