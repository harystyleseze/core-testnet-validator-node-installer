#!/bin/bash

# Prevent running entire script as root
if [ "$(id -u)" = "0" ]; then
   echo "This script should NOT be run as root"
   echo "The script will use sudo for commands that require elevated privileges"
   exit 1
fi

# Exit on error
set -e

# Error handling
trap 'handle_error $? $LINENO $BASH_LINENO "$BASH_COMMAND" $(printf "::%s" ${FUNCNAME[@]:-})' ERR

handle_error() {
    local exit_code=$1
    local line_no=$2
    local bash_lineno=$3
    local last_command=$4
    local func_trace=$5

    log_message "Error occurred in install.sh" "error"
    log_message "Exit code: $exit_code" "error"
    log_message "Line number: $line_no" "error"
    log_message "Command: $last_command" "error"
    log_message "Function trace: $func_trace" "error"

    show_error "An error occurred while running the installer.\nPlease check the logs for details."
    exit "$exit_code"
}

# Function to detect OS and package manager
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/redhat-release ]; then
        echo "redhat"
    elif [ -f /etc/arch-release ]; then
        echo "arch"
    else
        echo "unknown"
    fi
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install dialog
install_dialog() {
    local os_type=$(detect_os)
    local install_cmd=""
    local package_name="dialog"
    
    echo -e "${PRIMARY}${BOLD}Dialog is not installed. Would you like to install it? (y/n)${NC}"
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        case $os_type in
            "macos")
                if ! command_exists brew; then
                    echo -e "${YELLOW}${BOLD}Homebrew is not installed. Would you like to install it? (y/n)${NC}"
                    read -r brew_response
                    if [[ "$brew_response" =~ ^[Yy]$ ]]; then
                        show_progress "Installing Homebrew..."
                        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                        show_status "Homebrew installed successfully" "success"
                    else
                        show_error "Cannot proceed without Homebrew on macOS."
                        exit 1
                    fi
                fi
                install_cmd="brew install"
                ;;
            "debian")
                install_cmd="sudo apt-get update && sudo apt-get install -y"
                ;;
            "redhat")
                install_cmd="sudo yum install -y"
                ;;
            "arch")
                install_cmd="sudo pacman -S --noconfirm"
                ;;
            *)
                show_error "Unsupported operating system. Please install dialog manually."
                exit 1
                ;;
        esac

        show_progress "Installing dialog..."
        if ! eval "$install_cmd $package_name"; then
            show_error "Failed to install dialog. Please install it manually."
            exit 1
        fi
        show_status "Dialog installed successfully!" "success"
    else
        show_error "Cannot proceed without dialog. Please install it manually."
        exit 1
    fi
}

# Check if running in correct directory
if [[ ! -f "$(dirname "$0")/utils.sh" ]]; then
    echo "Error: Required files not found. Please run this script from the core-node-installer directory."
    exit 1
fi

# Source utils first to get access to functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh" || { echo "Error loading utils.sh"; exit 1; }

# Install required dependencies
echo "Checking and installing required dependencies..."
install_dependencies

# Source other scripts
source "$SCRIPT_DIR/hardware_check.sh" || { show_error "Error loading hardware_check.sh"; exit 1; }
source "$SCRIPT_DIR/node_setup.sh" || { show_error "Error loading node_setup.sh"; exit 1; }
source "$SCRIPT_DIR/log_monitor.sh" || { show_error "Error loading log_monitor.sh"; exit 1; }

# Initialize dialog styling
style_dialog

show_welcome_screen() {
    show_header "Core Testnet Node Installer"
    dialog --colors \
           --title "Welcome" \
           --msgbox "\nWelcome to the Core Testnet Node Installer!\n\nThis tool will help you set up a Core testnet validator node on your system.\n\nBefore proceeding, we'll check if your system meets the minimum requirements.\n\nPress OK to continue." 12 70 || return 1
}

verify_requirements() {
    dialog --colors \
           --title "Hardware Requirements Check" \
           --yesno "\nBefore proceeding with the installation, we need to verify your system meets the minimum requirements:\n\n▸ CPU: 4 cores\n▸ RAM: 8 GB\n▸ Storage: 1 TB free space\n▸ Internet: 10 Mbps\n\nWould you like to check your system requirements now?" 15 70

    if [ $? -eq 0 ]; then
        if check_hardware_requirements; then
            dialog --colors \
                   --title "Success" \
                   --yesno "\n✓ Your system meets all the requirements!\n\nWould you like to proceed with the installation?" 10 60
            return $?
        else
            dialog --colors \
                   --title "Error" \
                   --msgbox "\n✗ Your system does not meet the minimum requirements.\n\nPlease upgrade your hardware and try again." 10 60
            return 1
        fi
    else
        return 1
    fi
}

show_main_menu() {
    while true; do
        local node_installed=false
        if check_node_installed; then
            node_installed=true
        fi

        choice=$(dialog --colors \
                       --title "Core Node Installer - Main Menu" \
                       --backtitle "Core Node Installer" \
                       --ok-label "Select" \
                       --cancel-label "Exit" \
                       --menu "\nChoose an option:" 17 70 9 \
                       1 "Check Hardware Requirements" \
                       2 "Install/Upgrade Core Node" \
                       3 "$([ "$node_installed" = true ] && echo "Node Management" || echo "Node Management (Node not installed)")" \
                       4 "$([ "$node_installed" = true ] && echo "Generate Consensus Key" || echo "Generate Consensus Key (Node not installed)")" \
                       5 "$([ "$node_installed" = true ] && echo "View Consensus Key" || echo "View Consensus Key (Node not installed)")" \
                       6 "$([ "$node_installed" = true ] && echo "View Logs" || echo "View Logs (Node not installed)")" \
                       7 "$([ "$node_installed" = true ] && echo "View Node Status" || echo "View Status (Node not installed)")" \
                       8 "Admin Dashboard" \
                       9 "Exit" \
                       2>&1 >/dev/tty) || exit 0

        case $choice in
            1)
                if verify_requirements; then
                    show_success "Hardware requirements verified."
                    dialog --colors \
                           --title "Proceed with Installation?" \
                           --backtitle "Core Node Installer" \
                           --yesno "\nSystem requirements met!\n\nWould you like to proceed with the installation?" 10 50
                    
                    if [ $? -eq 0 ]; then
                        setup_node
                    fi
                fi
                ;;
            2)
                if verify_requirements; then
                    setup_node
                fi
                ;;
            3)
                if [ "$node_installed" = true ]; then
                    show_node_management
                else
                    show_error "Node is not installed.\nPlease install the node first."
                fi
                ;;
            4)
                if [ "$node_installed" = true ]; then
                    generate_consensus_key
                else
                    show_error "Node is not installed.\nPlease install the node first."
                fi
                ;;
            5)
                if [ "$node_installed" = true ]; then
                    view_consensus_key
                else
                    show_error "Node is not installed.\nPlease install the node first."
                fi
                ;;
            6)
                if [ "$node_installed" = true ]; then
                    show_log_monitor_menu
                else
                    show_error "Node is not installed.\nPlease install the node first."
                fi
                ;;
            7)
                if [ "$node_installed" = true ]; then
                    show_node_status
                else
                    show_error "Node is not installed.\nPlease install the node first."
                fi
                ;;
            8)
                show_admin_dashboard
                ;;
            9)
                clear
                show_header "Thank you for using Core Node Installer!"
                exit 0
                ;;
        esac
    done
}

show_admin_dashboard() {
    while true; do
        choice=$(dialog --colors \
                       --title "Admin Dashboard" \
                       --backtitle "Core Node Installer" \
                       --ok-label "Select" \
                       --cancel-label "Back" \
                       --menu "\nAdmin Operations:" 15 70 6 \
                       1 "Clean Build Core Chain" \
                       2 "Delete Core Chain" \
                       3 "Reset Node Configuration" \
                       4 "Repair Installation" \
                       5 "View System Status" \
                       6 "Back to Main Menu" \
                       2>&1 >/dev/tty) || return 0

        case $choice in
            1)
                dialog --colors \
                       --title "Confirm Clean Build" \
                       --backtitle "Core Node Installer" \
                       --yesno "\nWarning: This will clean and rebuild the core-chain.\nAll existing build artifacts will be removed.\n\nAre you sure?" 10 60
                if [ $? -eq 0 ]; then
                    (cd "$CORE_CHAIN_DIR" && make clean && build_geth) 2>&1 | \
                    dialog --programbox "Cleaning and Rebuilding..." 20 70
                fi
                ;;
            2)
                dialog --colors \
                       --title "Confirm Delete" \
                       --backtitle "Core Node Installer" \
                       --yesno "\nWarning: This will completely remove the core-chain directory.\nAll data will be lost.\n\nAre you sure?" 10 60
                if [ $? -eq 0 ]; then
                    if rm -rf "$CORE_CHAIN_DIR"; then
                        show_success "Core chain directory deleted successfully!"
                    fi
                fi
                ;;
            3)
                dialog --colors \
                       --title "Confirm Reset" \
                       --backtitle "Core Node Installer" \
                       --yesno "\nWarning: This will reset all node configurations to default.\nCustom settings will be lost.\n\nAre you sure?" 10 60
                if [ $? -eq 0 ]; then
                    if [ -f "$NODE_DIR/config.toml" ]; then
                        mv "$NODE_DIR/config.toml" "$NODE_DIR/config.toml.backup"
                    fi
                    cp "$SCRIPT_DIR/config.toml" "$NODE_DIR/config.toml"
                    show_success "Node configuration reset to default!"
                fi
                ;;
            4)
                repair_installation
                ;;
            5)
                show_system_status
                ;;
            6)
                return 0
                ;;
        esac
    done
}

repair_installation() {
    while true; do
        choice=$(dialog --colors \
                       --title "Repair Installation" \
                       --backtitle "Core Node Installer" \
                       --ok-label "Select" \
                       --cancel-label "Back" \
                       --menu "\nChoose repair option:" 15 60 4 \
                       1 "Verify Files" \
                       2 "Fix Permissions" \
                       3 "Reinstall Dependencies" \
                       4 "Back" \
                       2>&1 >/dev/tty) || return 0

        case $choice in
            1)
                (cd "$CORE_CHAIN_DIR" && \
                 git fsck && \
                 git reset --hard HEAD && \
                 make clean) 2>&1 | \
                dialog --programbox "Verifying files..." 20 70
                show_success "File verification complete!"
                ;;
            2)
                (chmod -R u+rw "$INSTALL_DIR" && \
                 chmod +x "$INSTALL_DIR/start-node.sh" && \
                 chmod +x "$CORE_CHAIN_DIR/build/bin/geth") 2>&1 | \
                dialog --programbox "Fixing permissions..." 20 70
                show_success "Permissions fixed!"
                ;;
            3)
                install_dependencies
                ;;
            4)
                return 0
                ;;
        esac
    done
}

show_system_status() {
    local temp_file=$(mktemp)
    
    {
        echo "System Status Report"
        echo "==================="
        echo
        echo "Core Chain Version: $(cd "$CORE_CHAIN_DIR" && git describe --tags 2>/dev/null || echo 'N/A')"
        echo "Geth Version: $("$CORE_CHAIN_DIR/build/bin/geth" version 2>/dev/null || echo 'N/A')"
        echo "Go Version: $(go version 2>/dev/null || echo 'N/A')"
        echo
        echo "Node Status: $(pgrep -f "geth.*--networkid 1114" > /dev/null && echo 'Running' || echo 'Stopped')"
        echo "Installation Directory: $INSTALL_DIR"
        echo "Free Disk Space: $(df -h "$INSTALL_DIR" | awk 'NR==2 {print $4}')"
        echo
        echo "Last Log Entry:"
        tail -n 5 "$NODE_DIR/logs/core.log" 2>/dev/null || echo "No logs found"
    } > "$temp_file"

    dialog --colors \
           --title "System Status" \
           --backtitle "Core Node Installer" \
           --ok-label "Back" \
           --textbox "$temp_file" 20 70

    rm -f "$temp_file"
}

# Main execution
if show_welcome_screen; then
    show_main_menu
else
    show_error "Failed to show welcome screen"
    exit 1
fi
