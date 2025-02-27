#!/bin/bash

# Source utils
source ./utils.sh

# Required specifications
REQUIRED_CPU_CORES=4
REQUIRED_RAM_GB=8
REQUIRED_DISK_GB=1024  # 1 TB
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
        else
            show_error "Could not install speedtest-cli. Please install it manually."
            return 1
        fi
    fi

    # Get system information
    get_system_info

    # Create temporary file for dialog checklist
    TEMP_FILE=$(mktemp)

    # Check CPU cores
    if [ "$CPU_CORES" -ge "$REQUIRED_CPU_CORES" ]; then
        echo "CPU Cores: ✓ ($CPU_CORES cores available)" >> "$TEMP_FILE"
    else
        echo "CPU Cores: ✗ (Required: $REQUIRED_CPU_CORES, Available: $CPU_CORES)" >> "$TEMP_FILE"
        FAILED=1
    fi

    # Check RAM
    if [ "$TOTAL_RAM" -ge "$REQUIRED_RAM_GB" ]; then
        echo "RAM: ✓ ($TOTAL_RAM GB available)" >> "$TEMP_FILE"
    else
        echo "RAM: ✗ (Required: ${REQUIRED_RAM_GB}GB, Available: ${TOTAL_RAM}GB)" >> "$TEMP_FILE"
        FAILED=1
    fi

    # Check Disk Space
    if [ "${FREE_DISK%.*}" -ge "$REQUIRED_DISK_GB" ]; then
        echo "Disk Space: ✓ ($FREE_DISK GB available)" >> "$TEMP_FILE"
    else
        echo "Disk Space: ✗ (Required: ${REQUIRED_DISK_GB}GB, Available: ${FREE_DISK}GB)" >> "$TEMP_FILE"
        FAILED=1
    fi

    # Check Internet Speed
    if [ -n "$INTERNET_SPEED" ] && [ "${INTERNET_SPEED%.*}" -ge "$REQUIRED_INTERNET_SPEED" ]; then
        echo "Internet Speed: ✓ ($INTERNET_SPEED Mbps)" >> "$TEMP_FILE"
    else
        echo "Internet Speed: ✗ (Required: ${REQUIRED_INTERNET_SPEED}Mbps, Available: ${INTERNET_SPEED:-Unknown}Mbps)" >> "$TEMP_FILE"
        FAILED=1
    fi

    # Display results
    dialog --title "Hardware Requirements Check" --textbox "$TEMP_FILE" 15 60

    # Clean up
    rm -f "$TEMP_FILE"

    if [ "$FAILED" = "1" ]; then
        show_error "Your system does not meet the minimum requirements. Please upgrade your hardware and try again."
        log_message "Hardware check failed"
        return 1
    fi

    show_success "Your system meets all the minimum requirements!"
    log_message "Hardware check passed"
    return 0
}

# Run hardware check if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_dialog
    check_hardware_requirements
fi
