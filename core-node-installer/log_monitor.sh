#!/bin/bash

# Source utils
source ./utils.sh

# Log file paths
CORE_LOG="$INSTALL_DIR/core-chain/node/logs/core.log"
INSTALL_LOG="core_installer.log"

# Function to format log entries with colors
format_log_entry() {
    local line="$1"
    # Add colors based on log level/content
    if [[ $line =~ ERROR|FATAL|WARN ]]; then
        echo -e "${RED}$line${NC}"
    elif [[ $line =~ INFO|SUCCESS ]]; then
        echo -e "${GREEN}$line${NC}"
    else
        echo -e "${NC}$line"
    fi
}

# Function to show live log dashboard
show_live_logs() {
    local log_file="$1"
    local title="$2"
    local lines=${3:-20}
    
    # Create a temporary file for formatted logs
    local temp_file=$(mktemp)
    
    # Watch the log file and update the display every 2 seconds
    watch -n 2 "tail -n $lines $log_file | while read -r line; do
        if [[ \$line =~ ERROR|FATAL|WARN ]]; then
            echo -e '\033[0;31m'\$line'\033[0m'
        elif [[ \$line =~ INFO|SUCCESS ]]; then
            echo -e '\033[0;32m'\$line'\033[0m'
        else
            echo \$line
        fi
    done > $temp_file && dialog --title \"$title\" --tailbox $temp_file 25 100"
    
    rm -f "$temp_file"
}

# Function to show log statistics
show_log_stats() {
    local log_file="$1"
    local temp_file=$(mktemp)
    
    {
        echo "=== Log Statistics ==="
        echo
        echo "Total Lines: $(wc -l < "$log_file")"
        echo "Errors: $(grep -c "ERROR" "$log_file")"
        echo "Warnings: $(grep -c "WARN" "$log_file")"
        echo "Info Messages: $(grep -c "INFO" "$log_file")"
        echo
        echo "=== Last Error ==="
        grep "ERROR" "$log_file" | tail -n 1
        echo
        echo "=== Recent Activity ==="
        tail -n 5 "$log_file"
    } > "$temp_file"

    dialog --title "Log Statistics" --textbox "$temp_file" 20 70
    rm -f "$temp_file"
}

# Function to search logs
search_logs() {
    local log_file="$1"
    local search_term

    # Get search term from user
    search_term=$(dialog --title "Search Logs" \
                        --inputbox "Enter search term:" 8 40 \
                        2>&1 >/dev/tty)

    if [ $? -eq 0 ] && [ -n "$search_term" ]; then
        local temp_file=$(mktemp)
        grep -i "$search_term" "$log_file" > "$temp_file"
        
        if [ -s "$temp_file" ]; then
            dialog --title "Search Results: $search_term" \
                   --textbox "$temp_file" 20 100
        else
            dialog --title "Search Results" \
                   --msgbox "No matches found for: $search_term" 8 40
        fi
        rm -f "$temp_file"
    fi
}

# Function to show log dashboard menu
show_log_dashboard() {
    local log_file="$1"
    local title="$2"

    while true; do
        choice=$(dialog --title "Log Dashboard - $title" \
                       --menu "Choose an option:" 15 60 6 \
                       1 "View Live Logs" \
                       2 "Show Log Statistics" \
                       3 "Search Logs" \
                       4 "Export Logs" \
                       5 "Clear Logs" \
                       6 "Back to Main Menu" \
                       2>&1 >/dev/tty)

        case $choice in
            1)
                show_live_logs "$log_file" "$title"
                ;;
            2)
                show_log_stats "$log_file"
                ;;
            3)
                search_logs "$log_file"
                ;;
            4)
                export_file="$HOME/core_logs_$(date +%Y%m%d_%H%M%S).log"
                cp "$log_file" "$export_file"
                dialog --title "Export Logs" \
                       --msgbox "Logs exported to: $export_file" 8 50
                ;;
            5)
                if dialog --title "Clear Logs" \
                         --yesno "Are you sure you want to clear the logs?" 8 40; then
                    backup_file "$log_file"
                    true > "$log_file"
                    dialog --title "Success" \
                           --msgbox "Logs cleared successfully. Backup created." 8 40
                fi
                ;;
            6)
                return
                ;;
        esac
    done
}

# Main log monitoring menu
show_log_monitor_menu() {
    while true; do
        choice=$(dialog --title "Log Monitoring Dashboard" \
                       --menu "Choose log type to view:" 15 60 3 \
                       1 "Core Node Logs" \
                       2 "Installation Logs" \
                       3 "Back to Main Menu" \
                       2>&1 >/dev/tty)

        case $choice in
            1)
                if [ -f "$CORE_LOG" ]; then
                    show_log_dashboard "$CORE_LOG" "Core Node Logs"
                else
                    dialog --title "Error" \
                           --msgbox "Core node logs not found. Is the node installed and running?" 8 60
                fi
                ;;
            2)
                if [ -f "$INSTALL_LOG" ]; then
                    show_log_dashboard "$INSTALL_LOG" "Installation Logs"
                else
                    dialog --title "Error" \
                           --msgbox "Installation log not found." 8 40
                fi
                ;;
            3)
                return
                ;;
        esac
    done
}

# Run log monitor if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_dialog
    show_log_monitor_menu
fi 