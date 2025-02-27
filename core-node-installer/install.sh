#!/bin/bash

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
           --title "$(echo -e "${PRIMARY}${BOLD}Welcome${NC}")" \
           --msgbox "\n${PRIMARY}${BOLD}Welcome to the Core Testnet Node Installer!${NC}\n\nThis tool will help you set up a Core testnet validator node on your system.\n\nBefore proceeding, we'll check if your system meets the minimum requirements.\n\nPress OK to continue." 12 70 || return 1
}

verify_requirements() {
    dialog --colors \
           --title "$(echo -e "${PRIMARY}${BOLD}Hardware Requirements Check${NC}")" \
           --yesno "\n${BOLD}Before proceeding with the installation, we need to verify your system meets the minimum requirements:${NC}\n\n${PRIMARY}▸ CPU:${NC} 4 cores\n${PRIMARY}▸ RAM:${NC} 8 GB\n${PRIMARY}▸ Storage:${NC} 1 TB free space\n${PRIMARY}▸ Internet:${NC} 10 Mbps\n\nWould you like to check your system requirements now?" 15 70

    if [ $? -eq 0 ]; then
        if check_hardware_requirements; then
            dialog --colors \
                   --title "$(echo -e "${GREEN}${BOLD}Success${NC}")" \
                   --yesno "\n${GREEN}${BOLD}✓ Your system meets all the requirements!${NC}\n\nWould you like to proceed with the installation?" 10 60
            return $?
        else
            dialog --colors \
                   --title "$(echo -e "${RED}${BOLD}Error${NC}")" \
                   --msgbox "\n${RED}${BOLD}✗ Your system does not meet the minimum requirements.${NC}\n\nPlease upgrade your hardware and try again." 10 60
            return 1
        fi
    else
        return 1
    fi
}

show_main_menu() {
    local requirements_met=false

    while true; do
        choice=$(dialog --colors \
                       --title "$(echo -e "${PRIMARY}${BOLD}Core Node Installer - Main Menu${NC}")" \
                       --menu "\nChoose an option:" 15 70 6 \
                       1 "${PRIMARY}▸${NC} Check Hardware Requirements" \
                       2 "${PRIMARY}▸${NC} Install Core Node" \
                       3 "${PRIMARY}▸${NC} Log Monitoring Dashboard" \
                       4 "${PRIMARY}▸${NC} Start/Stop Node" \
                       5 "${PRIMARY}▸${NC} View Installation Log" \
                       6 "${PRIMARY}▸${NC} Exit" \
                       2>&1 >/dev/tty) || return 1

        case $choice in
            1)
                if verify_requirements; then
                    requirements_met=true
                    show_success "Hardware requirements verified.\nYou can now proceed with the installation."
                fi
                ;;
            2)
                if [ "$requirements_met" = true ] || verify_requirements; then
                    setup_node || true
                else
                    show_error "Please verify hardware requirements before installation."
                fi
                ;;
            3)
                show_log_monitor_menu || true
                ;;
            4)
                if [ "$requirements_met" = true ] || [ -f "$INSTALL_DIR/start-node.sh" ]; then
                    manage_node || true
                else
                    show_error "Please install the node first."
                fi
                ;;
            5)
                if [ -f "core_installer.log" ]; then
                    dialog --colors \
                           --title "$(echo -e "${PRIMARY}${BOLD}Installation Log${NC}")" \
                           --textbox "core_installer.log" 20 70 || true
                else
                    show_error "No installation log found."
                fi
                ;;
            6)
                clear
                show_header "Thank you for using Core Node Installer!"
                exit 0
                ;;
            *)
                clear
                exit 1
                ;;
        esac
    done
}

manage_node() {
    if [ ! -f "$INSTALL_DIR/start-node.sh" ]; then
        dialog --title "Error" \
               --msgbox "Node is not installed. Please install the node first." 8 50 || return 1
        return 1
    fi

    while true; do
        choice=$(dialog --title "Node Management" \
                       --menu "Choose an option:" 12 60 3 \
                       1 "Start Node" \
                       2 "Stop Node" \
                       3 "Back to Main Menu" \
                       2>&1 >/dev/tty) || return 1

        case $choice in
            1)
                if pgrep -f "geth.*--networkid 1114" > /dev/null; then
                    dialog --title "Error" \
                           --msgbox "Node is already running!" 8 40 || true
                else
                    dialog --title "Starting Node" \
                           --infobox "Starting Core node..." 5 40
                    "$INSTALL_DIR/start-node.sh" &
                    sleep 2
                    dialog --title "Success" \
                           --msgbox "Node started successfully!" 8 40 || true
                fi
                ;;
            2)
                if pgrep -f "geth.*--networkid 1114" > /dev/null; then
                    dialog --title "Stopping Node" \
                           --infobox "Stopping Core node..." 5 40
                    pkill -f "geth.*--networkid 1114" || true
                    sleep 2
                    dialog --title "Success" \
                           --msgbox "Node stopped successfully!" 8 40 || true
                else
                    dialog --title "Error" \
                           --msgbox "Node is not running!" 8 40 || true
                fi
                ;;
            3)
                return 0
                ;;
            *)
                return 1
                ;;
        esac
    done
}

# Main execution
if show_welcome_screen; then
    show_main_menu
else
    show_error "Failed to show welcome screen"
    exit 1
fi
