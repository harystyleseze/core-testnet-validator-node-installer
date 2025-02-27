#!/bin/bash

# Source utils and other scripts
source ./utils.sh
source ./hardware_check.sh
source ./node_setup.sh
source ./log_monitor.sh

show_welcome_screen() {
    dialog --title "Core Testnet Node Installer" \
           --msgbox "\nWelcome to the Core Testnet Node Installer!\n\nThis tool will help you set up a Core testnet validator node on your system.\n\nBefore proceeding, we'll check if your system meets the minimum requirements.\n\nPress OK to continue." 12 60
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
                       2>&1 >/dev/tty)

        case $choice in
            1)
                check_hardware_requirements
                ;;
            2)
                if check_hardware_requirements; then
                    setup_node
                else
                    dialog --title "Error" \
                           --msgbox "Hardware requirements not met. Please upgrade your system before proceeding." 8 60
                fi
                ;;
            3)
                show_log_monitor_menu
                ;;
            4)
                manage_node
                ;;
            5)
                if [ -f "core_installer.log" ]; then
                    dialog --title "Installation Log" --textbox "core_installer.log" 20 70
                else
                    dialog --title "Error" --msgbox "No installation log found." 8 40
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
               --msgbox "Node is not installed. Please install the node first." 8 50
        return
    }

    while true; do
        choice=$(dialog --title "Node Management" \
                       --menu "Choose an option:" 12 60 3 \
                       1 "Start Node" \
                       2 "Stop Node" \
                       3 "Back to Main Menu" \
                       2>&1 >/dev/tty)

        case $choice in
            1)
                if pgrep -f "geth.*--networkid 1114" > /dev/null; then
                    dialog --title "Error" \
                           --msgbox "Node is already running!" 8 40
                else
                    dialog --title "Starting Node" \
                           --infobox "Starting Core node..." 5 40
                    $INSTALL_DIR/start-node.sh &
                    sleep 2
                    dialog --title "Success" \
                           --msgbox "Node started successfully!" 8 40
                fi
                ;;
            2)
                if pgrep -f "geth.*--networkid 1114" > /dev/null; then
                    dialog --title "Stopping Node" \
                           --infobox "Stopping Core node..." 5 40
                    pkill -f "geth.*--networkid 1114"
                    sleep 2
                    dialog --title "Success" \
                           --msgbox "Node stopped successfully!" 8 40
                else
                    dialog --title "Error" \
                           --msgbox "Node is not running!" 8 40
                fi
                ;;
            3)
                return
                ;;
            *)
                return
                ;;
        esac
    done
}

# Main execution
check_dialog
show_welcome_screen
show_main_menu
