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

    echo "Error occurred in install.sh"
    echo "Exit code: $exit_code"
    echo "Line number: $line_no"
    echo "Command: $last_command"
    echo "Function trace: $func_trace"

    dialog --title "Error" \
           --msgbox "An error occurred while running the installer.\nPlease check the logs for details." 8 50
    
    exit "$exit_code"
}

# Check if running in correct directory
if [[ ! -f "$(dirname "$0")/utils.sh" ]]; then
    echo "Error: Required files not found. Please run this script from the core-node-installer directory."
    exit 1
fi

# Source utils and other scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh" || { echo "Error loading utils.sh"; exit 1; }
source "$SCRIPT_DIR/hardware_check.sh" || { echo "Error loading hardware_check.sh"; exit 1; }
source "$SCRIPT_DIR/node_setup.sh" || { echo "Error loading node_setup.sh"; exit 1; }
source "$SCRIPT_DIR/log_monitor.sh" || { echo "Error loading log_monitor.sh"; exit 1; }

show_welcome_screen() {
    dialog --title "Core Testnet Node Installer" \
           --msgbox "\nWelcome to the Core Testnet Node Installer!\n\nThis tool will help you set up a Core testnet validator node on your system.\n\nBefore proceeding, we'll check if your system meets the minimum requirements.\n\nPress OK to continue." 12 60 || return 1
}

show_main_menu() {
    while true; do
        choice=$(dialog --title "Core Node Installer - Main Menu" \
                       --menu "Choose an option:" 15 60 6 \
                       1 "Check Hardware Requirements" \
                       2 "Install Core Node" \
                       3 "Log Monitoring Dashboard" \
                       4 "Start/Stop Node" \
                       5 "View Installation Log" \
                       6 "Exit" \
                       2>&1 >/dev/tty) || return 1

        case $choice in
            1)
                check_hardware_requirements || true
                ;;
            2)
                if check_hardware_requirements; then
                    setup_node || true
                else
                    dialog --title "Error" \
                           --msgbox "Hardware requirements not met. Please upgrade your system before proceeding." 8 60 || true
                fi
                ;;
            3)
                show_log_monitor_menu || true
                ;;
            4)
                manage_node || true
                ;;
            5)
                if [ -f "core_installer.log" ]; then
                    dialog --title "Installation Log" --textbox "core_installer.log" 20 70 || true
                else
                    dialog --title "Error" --msgbox "No installation log found." 8 40 || true
                fi
                ;;
            6)
                clear
                echo "Thank you for using Core Node Installer!"
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

# Check if dialog is installed before starting
if ! check_dialog; then
    echo "Error: Failed to install or find dialog. Please install it manually."
    exit 1
fi

# Main execution
if show_welcome_screen; then
    show_main_menu
else
    echo "Error: Failed to show welcome screen"
    exit 1
fi
