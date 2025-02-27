#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Display error message
show_error() {
    dialog --title "Error" --msgbox "$1" 8 50
}

# Display success message
show_success() {
    dialog --title "Success" --msgbox "$1" 8 50
}

# Display progress
show_progress() {
    echo -e "${GREEN}$1${NC}"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Please run as root${NC}"
        exit 1
    fi
}

# Function to check if a command was successful
check_status() {
    if [ $? -eq 0 ]; then
        show_success "$1"
    else
        show_error "$2"
        exit 1
    fi
}

# Function to get system information
get_system_info() {
    CPU_CORES=$(nproc)
    TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
    FREE_DISK=$(df -h / | awk 'NR==2 {print $4}' | sed 's/[A-Za-z]//g')
    INTERNET_SPEED=$(speedtest-cli --simple 2>/dev/null | awk '/Download:/{print $2}')
}

# Function to create a backup of a file
backup_file() {
    if [ -f "$1" ]; then
        cp "$1" "$1.backup.$(date +%Y%m%d_%H%M%S)"
    fi
}

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> core_installer.log
}

# Function to check internet connectivity
check_internet() {
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        show_error "No internet connection. Please check your connection and try again."
        exit 1
    fi
}

# Function to display a countdown timer
countdown() {
    local seconds=$1
    while [ $seconds -gt 0 ]; do
        echo -ne "${YELLOW}Waiting for $seconds seconds...${NC}\r"
        sleep 1
        : $((seconds--))
    done
    echo -e "\n"
}
