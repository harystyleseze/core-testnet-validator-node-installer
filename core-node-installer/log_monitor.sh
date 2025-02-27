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

    echo "Error occurred in log_monitor.sh"
    echo "Exit code: $exit_code"
    echo "Line number: $line_no"
    echo "Command: $last_command"
    echo "Function trace: $func_trace"

    dialog --title "Error" \
           --msgbox "An error occurred in the log monitor.\nPlease check the logs for details." 8 50
    
    return "$exit_code"
}

# Check if running in correct directory
if [[ ! -f "$(dirname "$0")/utils.sh" ]]; then
    echo "Error: Required files not found. Please run this script from the core-node-installer directory."
    exit 1
fi

# Source utils
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh" || { echo "Error loading utils.sh"; exit 1; }

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
    
    # Check if log file exists
    if [[ ! -f "$log_file" ]]; then
        dialog --title "Error" --msgbox "Log file not found: $log_file" 8 50
        return 1
    }
    
    # Create temporary file for formatted logs
    local temp_file
    temp_file=$(mktemp) || { dialog --title "Error" --msgbox "Failed to create temporary file" 8 40; return 1; }
    
    # Ensure temp file is cleaned up
    trap 'rm -f "$temp_file"' EXIT
    
    # Watch the log file and update the display every 2 seconds
    watch -n 2 "tail -n $lines \"$log_file\" 2>/dev/null | while read -r line; do
        if [[ \$line =~ ERROR|FATAL|WARN ]]; then
            echo -e '\033[0;31m'\$line'\033[0m'
        elif [[ \$line =~ INFO|SUCCESS ]]; then
            echo -e '\033[0;32m'\$line'\033[0m'
        else
            echo \$line
        fi
    done > \"$temp_file\" 2>/dev/null && dialog --title \"$title\" --tailbox \"$temp_file\" 25 100" || true
}

# Function to show log statistics
show_log_stats() {
    local log_file="$1"
    
    # Check if log file exists
    if [[ ! -f "$log_file" ]]; then
        dialog --title "Error" --msgbox "Log file not found: $log_file" 8 50
        return 1
    }
    
    local temp_file
    temp_file=$(mktemp) || { dialog --title "Error" --msgbox "Failed to create temporary file" 8 40; return 1; }
    
    # Ensure temp file is cleaned up
    trap 'rm -f "$temp_file"' EXIT
    
    {
        echo "=== Log Statistics ==="
        echo
        echo "Total Lines: $(wc -l < "$log_file")"
        echo "Errors: $(grep -c "ERROR" "$log_file" || echo "0")"
        echo "Warnings: $(grep -c "WARN" "$log_file" || echo "0")"
        echo "Info Messages: $(grep -c "INFO" "$log_file" || echo "0")"
        echo
        echo "=== Last Error ==="
        grep "ERROR" "$log_file" 2>/dev/null | tail -n 1 || echo "No errors found"
        echo
        echo "=== Recent Activity ==="
        tail -n 5 "$log_file" 2>/dev/null || echo "No recent activity"
    } > "$temp_file"

    dialog --title "Log Statistics" --textbox "$temp_file" 20 70 || true
}

# Function to search logs
search_logs() {
    local log_file="$1"
    
    # Check if log file exists
    if [[ ! -f "$log_file" ]]; then
        dialog --title "Error" --msgbox "Log file not found: $log_file" 8 50
        return 1
    }

    local search_term
    search_term=$(dialog --title "Search Logs" \
                        --inputbox "Enter search term:" 8 40 \
                        2>&1 >/dev/tty) || return 1

    if [ -n "$search_term" ]; then
        local temp_file
        temp_file=$(mktemp) || { dialog --title "Error" --msgbox "Failed to create temporary file" 8 40; return 1; }
        
        # Ensure temp file is cleaned up
        trap 'rm -f "$temp_file"' EXIT
        
        grep -i "$search_term" "$log_file" > "$temp_file" 2>/dev/null || true
        
        if [ -s "$temp_file" ]; then
            dialog --title "Search Results: $search_term" \
                   --textbox "$temp_file" 20 100 || true
        else
            dialog --title "Search Results" \
                   --msgbox "No matches found for: $search_term" 8 40 || true
        fi
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
                       2>&1 >/dev/tty) || return 1

        case $choice in
            1)
                show_live_logs "$log_file" "$title" || true
                ;;
            2)
                show_log_stats "$log_file" || true
                ;;
            3)
                search_logs "$log_file" || true
                ;;
            4)
                if [[ -f "$log_file" ]]; then
                    export_file="$HOME/core_logs_$(date +%Y%m%d_%H%M%S).log"
                    if cp "$log_file" "$export_file"; then
                        dialog --title "Export Logs" \
                               --msgbox "Logs exported to: $export_file" 8 50 || true
                    else
                        dialog --title "Error" \
                               --msgbox "Failed to export logs" 8 40 || true
                    fi
                else
                    dialog --title "Error" \
                           --msgbox "Log file not found: $log_file" 8 50 || true
                fi
                ;;
            5)
                if [[ -f "$log_file" ]]; then
                    if dialog --title "Clear Logs" \
                             --yesno "Are you sure you want to clear the logs?" 8 40; then
                        backup_file "$log_file"
                        if true > "$log_file"; then
                            dialog --title "Success" \
                                   --msgbox "Logs cleared successfully. Backup created." 8 40 || true
                        else
                            dialog --title "Error" \
                                   --msgbox "Failed to clear logs" 8 40 || true
                        fi
                    fi
                else
                    dialog --title "Error" \
                           --msgbox "Log file not found: $log_file" 8 50 || true
                fi
                ;;
            6)
                return 0
                ;;
            *)
                return 1
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
                       2>&1 >/dev/tty) || return 1

        case $choice in
            1)
                if [ -f "$CORE_LOG" ]; then
                    show_log_dashboard "$CORE_LOG" "Core Node Logs" || true
                else
                    dialog --title "Error" \
                           --msgbox "Core node logs not found. Is the node installed and running?" 8 60 || true
                fi
                ;;
            2)
                if [ -f "$INSTALL_LOG" ]; then
                    show_log_dashboard "$INSTALL_LOG" "Installation Logs" || true
                else
                    dialog --title "Error" \
                           --msgbox "Installation log not found." 8 40 || true
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

# Run log monitor if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if ! check_dialog; then
        echo "Error: Failed to install or find dialog. Please install it manually."
        exit 1
    fi
    show_log_monitor_menu
fi 