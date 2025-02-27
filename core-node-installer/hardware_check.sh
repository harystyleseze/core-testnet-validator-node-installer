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

    # Check CPU cores
    if [ "$CPU_CORES" -ge "$REQUIRED_CPU_CORES" ]; then
        format_requirement "CPU Cores" "$REQUIRED_CPU_CORES" "$CPU_CORES" "pass" >> "$TEMP_FILE"
    else
        format_requirement "CPU Cores" "$REQUIRED_CPU_CORES" "$CPU_CORES" "fail" >> "$TEMP_FILE"
        FAILED=1
    fi

    # Check RAM
    if [ "$TOTAL_RAM" -ge "$REQUIRED_RAM_GB" ]; then
        format_requirement "RAM" "${REQUIRED_RAM_GB}GB" "${TOTAL_RAM}GB" "pass" >> "$TEMP_FILE"
    else
        format_requirement "RAM" "${REQUIRED_RAM_GB}GB" "${TOTAL_RAM}GB" "fail" >> "$TEMP_FILE"
        FAILED=1
    fi

    # Check Disk Space
    if [ "${FREE_DISK%.*}" -ge "$REQUIRED_DISK_GB" ]; then
        format_requirement "Disk Space" "${REQUIRED_DISK_GB}GB" "${FREE_DISK}GB" "pass" >> "$TEMP_FILE"
    else
        format_requirement "Disk Space" "${REQUIRED_DISK_GB}GB" "${FREE_DISK}GB" "fail" >> "$TEMP_FILE"
        FAILED=1
    fi

    # Check Internet Speed
    if [ -n "$INTERNET_SPEED" ] && [ "${INTERNET_SPEED%.*}" -ge "$REQUIRED_INTERNET_SPEED" ]; then
        format_requirement "Internet Speed" "${REQUIRED_INTERNET_SPEED}Mbps" "${INTERNET_SPEED}Mbps" "pass" >> "$TEMP_FILE"
    else
        format_requirement "Internet Speed" "${REQUIRED_INTERNET_SPEED}Mbps" "${INTERNET_SPEED:-0}Mbps" "fail" >> "$TEMP_FILE"
        FAILED=1
    fi

    # Display results with new styling
    dialog --colors \
           --title "System Requirements Check" \
           --backtitle "Core Node Installer" \
           --cr-wrap \
           --no-collapse \
           --textbox "$TEMP_FILE" 15 70

    # Clean up
    rm -f "$TEMP_FILE"

    if [ "$FAILED" = "1" ]; then
        show_error "Your system does not meet the minimum requirements.\nPlease review the requirements and try again after upgrading your hardware."
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
