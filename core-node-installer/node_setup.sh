#!/bin/bash

# Exit on error
set -e

# Error handling
trap 'handle_error $? $LINENO $BASH_LINENO "$BASH_COMMAND" $(printf "::%s" ${FUNCNAME[@]:-})' ERR

# Check if running in correct directory
if [[ ! -f "$(dirname "$0")/utils.sh" ]]; then
    echo "Error: Required files not found. Please run this script from the core-node-installer directory."
    exit 1
fi

# Source utils first to get access to functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh" || { echo "Error loading utils.sh"; exit 1; }

# Installation directories
INSTALL_DIR="$HOME/core-node"
CORE_CHAIN_DIR="$INSTALL_DIR/core-chain"
NODE_DIR="$CORE_CHAIN_DIR/node"

handle_error() {
    local exit_code=$1
    local line_no=$2
    local bash_lineno=$3
    local last_command=$4
    local func_trace=$5

    log_message "Error occurred in node_setup.sh" "error"
    log_message "Exit code: $exit_code" "error"
    log_message "Line number: $line_no" "error"
    log_message "Command: $last_command" "error"
    log_message "Function trace: $func_trace" "error"

    show_error "An error occurred while setting up the node.\nPlease check the logs for details."
    return "$exit_code"
}

install_dependencies() {
    log_message "Installing dependencies"
    show_progress "Installing required packages..."
    
    # Define required packages
    local required_packages=(
        "git"
        "gcc"
        "make"
        "curl"
        "lz4"
        "unzip"
    )
    
    if [ -f /etc/debian_version ]; then
        show_progress "Detected Debian/Ubuntu system..."
        
        # Update package list
        show_progress "Updating package lists..."
        if ! sudo apt update; then
            show_error "Failed to update package lists"
            return 1
        fi
        
        # Install packages
        show_progress "Installing required packages..."
        if ! sudo apt install -y "${required_packages[@]}"; then
            show_error "Failed to install required packages"
            return 1
        fi
    elif [ -f /etc/redhat-release ]; then
        show_progress "Detected RedHat/CentOS system..."
        if ! sudo yum install -y "${required_packages[@]}"; then
            show_error "Failed to install required packages"
            return 1
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        show_progress "Detected macOS system..."
        if ! command -v brew &>/dev/null; then
            show_warning "Homebrew is not installed. Installing..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
        for package in "${required_packages[@]}"; do
            if ! brew list "$package" &>/dev/null; then
                show_progress "Installing $package..."
                if ! brew install "$package"; then
                    show_error "Failed to install $package"
                    return 1
                fi
            fi
        done
    else
        show_error "Unsupported distribution. Please install dependencies manually:\n${required_packages[*]}"
        return 1
    fi

    # Verify all required packages are installed
    local FAILED=0
    for package in "${required_packages[@]}"; do
        show_progress "Verifying $package installation..."
        if ! command -v "$package" &>/dev/null; then
            show_error "$package is not installed or not in PATH"
            FAILED=1
        else
            show_status "$package is installed" "success"
        fi
    done

    if [ $FAILED -eq 1 ]; then
        show_error "Some required packages are missing. Please install them manually."
        return 1
    fi

    show_success "All dependencies installed and verified successfully!"
    return 0
}

clone_core_repository() {
    log_message "Cloning Core repository"
    show_progress "Cloning Core Chain repository..."
    
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    if [ -d "$CORE_CHAIN_DIR" ]; then
        show_progress "Core Chain directory already exists. Updating..."
        cd "$CORE_CHAIN_DIR"
        git fetch --all
        git fetch --tags
    else
        git clone https://github.com/coredao-org/core-chain
        cd "$CORE_CHAIN_DIR"
        git fetch --tags
    fi

    # Get latest tag name
    latestTag=$(git describe --tags `git rev-list --tags --max-count=1`)
    show_progress "Checking out latest tag: $latestTag"
    git checkout $latestTag

    check_status "Repository cloned/updated and tag checked out successfully!" "Failed to clone/update repository"
}

build_geth() {
    log_message "Building geth"
    show_progress "Building geth binary..."
    
    cd "$CORE_CHAIN_DIR"

    # Check Go version and install correct version if needed
    local required_go_version="1.21.8"  # Updated to latest stable Go 1.21
    local current_go_version=""
    
    if command -v go &>/dev/null; then
        current_go_version=$(go version | awk '{print $3}' | sed 's/go//')
    fi

    if [[ -z "$current_go_version" ]] || [[ "$(printf '%s\n' "$required_go_version" "$current_go_version" | sort -V | head -n1)" != "$required_go_version" ]]; then
        show_warning "Installing Go version $required_go_version..."
        
        # Download and install Go
        local os_arch="linux-amd64"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            os_arch="darwin-amd64"
        fi
        local go_archive="go${required_go_version}.${os_arch}.tar.gz"
        local go_url="https://go.dev/dl/${go_archive}"
        
        show_progress "Downloading Go ${required_go_version}..."
        if ! wget -O go.tar.gz "$go_url"; then
            show_error "Failed to download Go"
            return 1
        fi

        show_progress "Installing Go ${required_go_version}..."
        sudo rm -rf /usr/local/go
        sudo tar -C /usr/local -xzf go.tar.gz
        rm go.tar.gz

        # Update PATH in shell config files
        for shell_rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
            if [ -f "$shell_rc" ]; then
                if ! grep -q "/usr/local/go/bin" "$shell_rc"; then
                    echo "export PATH=\$PATH:/usr/local/go/bin" >> "$shell_rc"
                fi
            fi
        done

        # Update current session PATH
        export PATH=$PATH:/usr/local/go/bin
        
        # Verify Go installation
        if ! command -v go &>/dev/null; then
            show_error "Go installation failed"
            return 1
        fi
        
        show_success "Go ${required_go_version} installed successfully!"
    fi

    # Set GOPATH and add to PATH
    export GOPATH=$HOME/go
    export PATH=$PATH:$GOPATH/bin

    # Clean any previous build artifacts
    show_progress "Cleaning previous build artifacts..."
    make clean || true

    # Update and verify dependencies
    show_progress "Updating Go modules..."
    if ! go mod tidy; then
        show_error "Failed to update Go modules"
        return 1
    fi

    # Download all dependencies
    show_progress "Downloading dependencies..."
    if ! go mod download; then
        show_error "Failed to download dependencies"
        return 1
    fi

    # Verify dependencies
    show_progress "Verifying dependencies..."
    if ! go mod verify; then
        show_error "Module verification failed"
        return 1
    fi

    # Build geth from the latest tag
    show_progress "Building geth from latest tag..."
    if ! make geth; then
        show_error "Failed to build geth. Please check the logs for details."
        return 1
    fi

    # Verify the binary was created
    if [ ! -f "./build/bin/geth" ]; then
        show_error "Geth binary not found after build."
        return 1
    fi

    # Install the binary to /usr/local/bin
    show_progress "Installing geth binary to /usr/local/bin..."
    if ! sudo cp "./build/bin/geth" /usr/local/bin/; then
        show_error "Failed to install geth binary to /usr/local/bin"
        return 1
    fi

    # Verify geth installation
    if ! command -v geth &>/dev/null; then
        show_error "Geth installation verification failed"
        return 1
    fi

    show_success "Geth built and installed successfully!"
    return 0
}

setup_node_directory() {
    log_message "Setting up node directory"
    show_progress "Setting up node directory..."
    
    mkdir -p "$NODE_DIR/logs"
    mkdir -p "$CORE_CHAIN_DIR/testnet2"
    
    # Copy local config files
    if [[ ! -f "$SCRIPT_DIR/config.toml" ]] || [[ ! -f "$SCRIPT_DIR/genesis.json" ]]; then
        show_error "Required config files not found.\nPlease ensure config.toml and genesis.json are present."
        return 1
    fi

    cp "$SCRIPT_DIR/config.toml" "$CORE_CHAIN_DIR/testnet2/config.toml"
    cp "$SCRIPT_DIR/genesis.json" "$CORE_CHAIN_DIR/testnet2/genesis.json"

    show_status "Node directory setup completed!" "success"
}

download_snapshot() {
    log_message "Downloading blockchain snapshot"
    show_progress "Downloading blockchain snapshot..."
    
    cd "$CORE_CHAIN_DIR"
    
    # Show progress dialog
    (wget -q --show-progress https://snap.coredao.org/coredao-snapshot-testnet-20240327-pruned.tar.lz4 2>&1) | \
    dialog --title "Downloading Snapshot" --gauge "Please wait..." 10 70 0

    show_progress "Decompressing snapshot..."
    lz4 -d coredao-snapshot-testnet-20240327-pruned.tar.lz4 coredao-snapshot-testnet-20240327-pruned.tar
    
    show_progress "Extracting snapshot..."
    tar -xf coredao-snapshot-testnet-20240327-pruned.tar -C "$NODE_DIR"

    check_status "Snapshot downloaded and extracted successfully!" "Failed to download/extract snapshot"
}

initialize_genesis() {
    log_message "Initializing genesis block"
    show_progress "Initializing genesis block..."
    
    cd "$CORE_CHAIN_DIR"
    ./build/bin/geth --datadir "$NODE_DIR" init ./testnet2/genesis.json

    check_status "Genesis block initialized successfully!" "Failed to initialize genesis block"
}

create_startup_script() {
    log_message "Creating startup script"
    
    # Ensure logs directory exists
    mkdir -p "$NODE_DIR/logs"
    
    # Create the startup script with proper paths and logging
    cat > "$INSTALL_DIR/start-node.sh" << 'EOF'
#!/bin/bash

# Set working directory
NODE_BASE_DIR="$(dirname "$0")"
cd "$NODE_BASE_DIR/core-chain"

# Ensure logs directory exists
mkdir -p ./node/logs

# Start geth with specified configuration
./build/bin/geth --config ./testnet2/config.toml \
                 --datadir ./node \
                 --cache 8000 \
                 --rpc.allow-unprotected-txs \
                 --networkid 1114 \
                 --verbosity 4 \
                 2>&1 | tee ./node/logs/core.log
EOF

    chmod +x "$INSTALL_DIR/start-node.sh"
    show_success "Startup script created at $INSTALL_DIR/start-node.sh"
}

show_live_logs() {
    local log_file="$NODE_DIR/logs/core.log"
    
    if [ ! -f "$log_file" ]; then
        dialog --colors \
               --title "${ERROR}Error${NC}" \
               --msgbox "\nLog file not found at:\n$log_file\n\nPlease ensure the node is running." 10 60
        return 1
    }

    dialog --colors \
           --title "${PRIMARY}Live Logs${NC}" \
           --backtitle "Core Node Installer" \
           --tailbox "$log_file" 30 100
}

show_last_50_lines() {
    local log_file="$NODE_DIR/logs/core.log"
    
    if [ ! -f "$log_file" ]; then
        dialog --colors \
               --title "${ERROR}Error${NC}" \
               --msgbox "\nLog file not found at:\n$log_file\n\nPlease ensure the node is running." 10 60
        return 1
    }

    local log_content
    log_content=$(tail -n 50 "$log_file" | sed 's/^[0-9]\+|//g')
    dialog --colors \
           --title "${PRIMARY}Last 50 Log Lines${NC}" \
           --backtitle "Core Node Installer" \
           --msgbox "$log_content" 30 100
}

show_error_logs() {
    local log_file="$NODE_DIR/logs/core.log"
    
    if [ ! -f "$log_file" ]; then
        dialog --colors \
               --title "${ERROR}Error${NC}" \
               --msgbox "\nLog file not found at:\n$log_file\n\nPlease ensure the node is running." 10 60
        return 1
    }

    local error_logs
    error_logs=$(grep -i "error\|failed\|fatal" "$log_file" | tail -n 50 | sed 's/^[0-9]\+|//g')
    if [ -z "$error_logs" ]; then
        error_logs="No errors found in the logs."
    fi
    dialog --colors \
           --title "${PRIMARY}Error Logs${NC}" \
           --backtitle "Core Node Installer" \
           --msgbox "$error_logs" 30 100
}

show_log_monitor_menu() {
    while true; do
        local choice
        choice=$(dialog --colors \
                       --title "${PRIMARY}Log Monitor${NC}" \
                       --backtitle "Core Node Installer" \
                       --cancel-label "Back" \
                       --menu "\nSelect a log viewing option:" 15 60 4 \
                       1 "View Live Logs" \
                       2 "View Last 50 Lines" \
                       3 "View Error Logs" \
                       2>&1 >/dev/tty)

        case $? in
            0) # User selected an option
                case $choice in
                    1) show_live_logs ;;
                    2) show_last_50_lines ;;
                    3) show_error_logs ;;
                esac
                ;;
            1) # Back
                return 0
                ;;
        esac
    done
}

show_log_history() {
    local lines=$1
    local log_file="$NODE_DIR/logs/core.log"
    local temp_file=$(mktemp)
    
    {
        echo "Last $lines Lines of Node Logs"
        echo "=========================="
        echo
        tail -n "$lines" "$log_file" 2>/dev/null || echo "No logs available yet"
    } > "$temp_file"

    dialog --colors \
           --title "Log History" \
           --backtitle "Core Node Installer" \
           --ok-label "Back" \
           --extra-button \
           --extra-label "Main Menu" \
           --textbox "$temp_file" 20 120

    rm -f "$temp_file"
    
    case $? in
        0) # Back button
            return 1
            ;;
        3) # Main Menu button
            return 255
            ;;
    esac
}

show_error_logs() {
    local log_file="$NODE_DIR/logs/core.log"
    local temp_file=$(mktemp)
    
    {
        echo "Error Logs"
        echo "=========="
        echo
        grep -i "error\|failed\|fatal" "$log_file" 2>/dev/null || echo "No error logs found"
    } > "$temp_file"

    dialog --colors \
           --title "Error Logs" \
           --backtitle "Core Node Installer" \
           --ok-label "Back" \
           --extra-button \
           --extra-label "Main Menu" \
           --textbox "$temp_file" 20 120

    rm -f "$temp_file"
    
    case $? in
        0) # Back button
            return 1
            ;;
        3) # Main Menu button
            return 255
            ;;
    esac
}

check_node_installed() {
    # Check for core directory
    if [[ ! -d "$CORE_CHAIN_DIR" ]]; then
        log_message "Node not installed: Core chain directory not found at $CORE_CHAIN_DIR" "error"
        return 1
    fi

    # Check for geth binary
    if [[ ! -f "$CORE_CHAIN_DIR/build/bin/geth" ]]; then
        log_message "Node not installed: Geth binary not found at $CORE_CHAIN_DIR/build/bin/geth" "error"
        return 1
    }

    # Check for node directory
    if [[ ! -d "$NODE_DIR" ]]; then
        log_message "Node not installed: Node directory not found at $NODE_DIR" "error"
        return 1
    }

    # Check for config files
    if [[ ! -f "$CORE_CHAIN_DIR/testnet2/config.toml" ]] || [[ ! -f "$CORE_CHAIN_DIR/testnet2/genesis.json" ]]; then
        log_message "Node not installed: Configuration files missing in $CORE_CHAIN_DIR/testnet2/" "error"
        return 1
    }

    return 0
}

show_navigation_buttons() {
    local title="$1"
    shift
    local menu_items=("$@")
    
    local options=()
    local i=1
    for item in "${menu_items[@]}"; do
        options+=("$i" "$item")
        ((i++))
    done
    
    dialog --colors \
           --title "$title" \
           --backtitle "Core Node Installer" \
           --ok-label "Select" \
           --cancel-label "Back" \
           --extra-button \
           --extra-label "Main Menu" \
           --menu "\nChoose an option:" 15 60 "${#menu_items[@]}" \
           "${options[@]}" \
           2>&1 >/dev/tty
    
    return $?
}

show_post_build_menu() {
    while true; do
        choice=$(show_navigation_buttons "Core Node Setup" \
            "Start Node" \
            "Start Node with Consensus Key" \
            "Generate Consensus Key" \
            "View Consensus Key" \
            "Download Snapshot" \
            "View Node Status" \
            "Back to Main Menu")
        
        local ret=$?
        case $ret in
            0) # Selected an option
                case $choice in
                    1)
                        if initialize_genesis && start_node; then
                            return 0
                        fi
                        ;;
                    2)
                        if initialize_genesis && start_node_with_consensus; then
                            return 0
                        fi
                        ;;
                    3)
                        generate_consensus_key
                        ;;
                    4)
                        view_consensus_key
                        ;;
                    5)
                        download_snapshot_with_progress || true
                        ;;
                    6)
                        show_node_status
                        ;;
                    7)
                        return 0
                        ;;
                esac
                ;;
            1) # Back button
                return 1
                ;;
            3) # Main Menu button
                return 255
                ;;
        esac
    done
}

download_snapshot_with_progress() {
    local pid
    local temp_file=$(mktemp)
    
    (
        wget -q --show-progress https://snap.coredao.org/coredao-snapshot-testnet-20240327-pruned.tar.lz4 2>&1 | \
        stdbuf -oL tr '\r' '\n' | grep -o '[0-9]*%' | cut -d'%' -f1 > "$temp_file" &
        pid=$!
        
        while kill -0 $pid 2>/dev/null; do
            local progress=$(tail -n 1 "$temp_file" 2>/dev/null || echo "0")
            echo "XXX"
            echo "$progress"
            echo "Downloading snapshot... ($progress%)\n\nPress ESC to cancel"
            echo "XXX"
            sleep 1
        done
    ) | dialog --colors \
               --title "Downloading Snapshot" \
               --backtitle "Core Node Installer" \
               --gauge "" 10 70 0 \
               --cancel-label "Cancel" \
               2>&1
    
    if [ $? -eq 1 ]; then
        pkill -P $pid wget 2>/dev/null
        rm -f "$temp_file"
        show_error "Download cancelled by user"
        return 1
    fi
    
    rm -f "$temp_file"
    return 0
}

show_node_status() {
    local temp_file=$(mktemp)
    
    {
        echo "Core Node Status"
        echo "================"
        echo
        if pgrep -f "geth.*--networkid 1114" > /dev/null; then
            echo "Node Status: Running"
            echo "Process ID: $(pgrep -f "geth.*--networkid 1114")"
        else
            echo "Node Status: Not Running"
        fi
        echo
        echo "Installation Directory: $INSTALL_DIR"
        echo "Data Directory: $NODE_DIR"
        echo "Log File: $NODE_DIR/logs/core.log"
        echo
        echo "Last 5 Log Entries:"
        echo "-------------------"
        tail -n 5 "$NODE_DIR/logs/core.log" 2>/dev/null || echo "No logs available yet"
    } > "$temp_file"

    local choice
    choice=$(dialog --colors \
           --title "Node Status" \
           --backtitle "Core Node Installer" \
           --ok-label "Back" \
           --extra-button \
           --extra-label "Main Menu" \
           --textbox "$temp_file" 20 70)

    rm -f "$temp_file"
    
    case $? in
        0) # Back button
            return 1
            ;;
        3) # Main Menu button
            return 255
            ;;
    esac
}

show_node_management() {
    while true; do
        local node_status="Stopped"
        if pgrep -f "geth.*--networkid 1114" > /dev/null; then
            node_status="Running"
        fi
        
        choice=$(show_navigation_buttons "Node Management" \
            "Start Node (Without Consensus)" \
            "Start Node with Consensus Key" \
            "Stop Node" \
            "Generate Consensus Key" \
            "View Consensus Key" \
            "View Logs" \
            "View Node Status" \
            "Back to Main Menu")
        
        local ret=$?
        case $ret in
            0) # Selected an option
                case $choice in
                    1)
                        if [ "$node_status" = "Running" ]; then
                            show_error "Node is already running!"
                        else
                            start_node
                        fi
                        ;;
                    2)
                        if [ "$node_status" = "Running" ]; then
                            show_error "Node is already running!"
                        else
                            start_node_with_consensus
                        fi
                        ;;
                    3)
                        if [ "$node_status" = "Stopped" ]; then
                            show_error "Node is not running!"
                        else
                            stop_node
                        fi
                        ;;
                    4)
                        generate_consensus_key
                        ;;
                    5)
                        view_consensus_key
                        ;;
                    6)
                        show_log_monitor_menu
                        ;;
                    7)
                        show_node_status
                        ;;
                    8)
                        return 0
                        ;;
                esac
                ;;
            1) # Back button
                return 1
                ;;
            3) # Main Menu button
                return 0
                ;;
        esac
    done
}

stop_node() {
    show_progress "Stopping Core node..."
    if pkill -f "geth.*--networkid 1114"; then
        show_success "Node stopped successfully!"
    else
        show_error "Failed to stop node"
    fi
}

generate_consensus_key() {
    if ! check_node_installed; then
        show_error "Node is not installed.\nPlease install the node first."
        return 1
    fi

    # Get password from user with validation
    local password=""
    local confirm_password=""
    local valid_password=false

    while [ "$valid_password" = false ]; do
        password=$(dialog --colors \
                         --title "${PRIMARY}Create Consensus Key${NC}" \
                         --backtitle "Core Node Installer" \
                         --insecure \
                         --passwordbox "\nEnter a strong password for your consensus key:\n\n- Minimum 8 characters\n- At least one number\n- At least one special character" \
                         15 60 \
                         2>&1 >/dev/tty) || return 1

        # Validate password strength
        if [ ${#password} -lt 8 ]; then
            dialog --colors \
                   --title "${ERROR}Invalid Password${NC}" \
                   --msgbox "\nPassword must be at least 8 characters long." 8 50
            continue
        fi

        confirm_password=$(dialog --colors \
                                --title "${PRIMARY}Confirm Password${NC}" \
                                --backtitle "Core Node Installer" \
                                --insecure \
                                --passwordbox "\nConfirm your password:" 8 50 \
                                2>&1 >/dev/tty) || return 1

        if [ "$password" != "$confirm_password" ]; then
            dialog --colors \
                   --title "${ERROR}Password Mismatch${NC}" \
                   --msgbox "\nPasswords do not match. Please try again." 8 50
            continue
        fi

        valid_password=true
    done

    # Save password to file securely
    echo "$password" > "$NODE_DIR/password.txt"
    chmod 600 "$NODE_DIR/password.txt"

    # Show progress during key generation
    dialog --colors \
           --title "${PRIMARY}Generating Consensus Key${NC}" \
           --backtitle "Core Node Installer" \
           --infobox "\nGenerating your consensus key...\nThis may take a moment." 6 50
    
    # Generate consensus key
    cd "$CORE_CHAIN_DIR"
    local output
    output=$(./build/bin/geth account new --datadir ./node --password "$NODE_DIR/password.txt" 2>&1)
    local address
    address=$(echo "$output" | grep -o "0x[0-9a-fA-F]\{40\}")

    if [ -n "$address" ]; then
        # Save address to file
        echo "$address" > "$NODE_DIR/validator_address.txt"
        chmod 600 "$NODE_DIR/validator_address.txt"

        # Show success message with options
        while true; do
            local choice
            choice=$(dialog --colors \
                           --title "${PRIMARY}Consensus Key Generated${NC}" \
                           --backtitle "Core Node Installer" \
                           --ok-label "Select" \
                           --cancel-label "Back" \
                           --menu "\nConsensus key generated successfully!\n\nValidator Address: $address\n\nWhat would you like to do next?" \
                           17 70 4 \
                           1 "View Key Details" \
                           2 "Start Node with This Key" \
                           3 "Go to Node Management" \
                           4 "Go to Main Menu" \
                           2>&1 >/dev/tty)

            case $? in
                0) # User selected an option
                    case $choice in
                        1) view_consensus_key ;;
                        2) start_node_with_consensus ;;
                        3) show_node_management; return $? ;;
                        4) return 255 ;; # Return to main menu
                    esac
                    ;;
                1) # Back
                    return 0
                    ;;
            esac
        done
    else
        show_error "Failed to generate consensus key.\nError: $output"
        return 1
    fi
}

view_consensus_key() {
    if ! check_node_installed; then
        show_error "Node is not installed.\nPlease install the node first."
        return 1
    fi

    cd "$CORE_CHAIN_DIR"
    
    # Get list of accounts
    local accounts_output
    accounts_output=$(./build/bin/geth account list --datadir ./node 2>&1)
    
    # Get saved validator address
    local saved_address=""
    if [ -f "$NODE_DIR/validator_address.txt" ]; then
        saved_address=$(cat "$NODE_DIR/validator_address.txt")
    fi
    
    # Create detailed output
    local output="Consensus Key Information\n"
    output+="========================\n\n"
    output+="Available Accounts:\n$accounts_output\n"
    
    if [ -n "$saved_address" ]; then
        output+="\nActive Validator Address:\n$saved_address"
    fi
    
    # Show key information with options
    while true; do
        local choice
        choice=$(dialog --colors \
                       --title "${PRIMARY}Consensus Key Details${NC}" \
                       --backtitle "Core Node Installer" \
                       --ok-label "Select" \
                       --cancel-label "Back" \
                       --menu "\n$output\n\nWhat would you like to do next?" \
                       20 70 4 \
                       1 "Generate New Key" \
                       2 "Start Node with This Key" \
                       3 "Go to Node Management" \
                       4 "Go to Main Menu" \
                       2>&1 >/dev/tty)

        case $? in
            0) # User selected an option
                case $choice in
                    1) generate_consensus_key; return $? ;;
                    2) start_node_with_consensus ;;
                    3) show_node_management; return $? ;;
                    4) return 255 ;; # Return to main menu
                esac
                ;;
            1) # Back
                return 0
                ;;
        esac
    done
}

start_node_with_consensus() {
    if ! check_node_installed; then
        show_error "Node is not installed.\nPlease install the node first."
        return 1
    fi

    # Ensure directories exist
    ensure_node_directories

    local validator_address
    if [ -f "$NODE_DIR/validator_address.txt" ]; then
        validator_address=$(cat "$NODE_DIR/validator_address.txt")
    fi

    # Get validator address from user
    validator_address=$(dialog --colors \
                              --title "Start Node with Consensus Key" \
                              --backtitle "Core Node Installer" \
                              --inputbox "\nEnter validator address (0x...):\n[Press Enter to use saved: ${validator_address:-none}]" 10 60 "$validator_address" \
                              2>&1 >/dev/tty) || return 1

    if [ -z "$validator_address" ]; then
        show_error "Validator address is required"
        return 1
    fi

    # Verify password exists
    if [ ! -f "$NODE_DIR/password.txt" ]; then
        local password
        password=$(dialog --colors \
                         --title "Start Node with Consensus Key" \
                         --backtitle "Core Node Installer" \
                         --insecure \
                         --passwordbox "\nEnter password for consensus key:" 10 50 \
                         2>&1 >/dev/tty) || return 1

        echo "$password" > "$NODE_DIR/password.txt"
        chmod 600 "$NODE_DIR/password.txt"
    fi

    # Start node with consensus key
    cd "$CORE_CHAIN_DIR"
    nohup ./build/bin/geth --config ./testnet2/config.toml \
                          --datadir "$NODE_DIR" \
                          --unlock "$validator_address" \
                          --miner.etherbase "$validator_address" \
                          --password "$NODE_DIR/password.txt" \
                          --mine \
                          --allow-insecure-unlock \
                          --cache 8000 \
                          2>&1 | tee -a "$NODE_DIR/logs/core.log" &

    # Wait for node to start
    sleep 5
    if pgrep -f "geth.*--mine" > /dev/null; then
        show_success "Node started successfully with consensus key!\n\nLog file: $NODE_DIR/logs/core.log"
        return 0
    else
        show_error "Failed to start node with consensus key.\nCheck logs at: $NODE_DIR/logs/core.log"
        return 1
    fi
}

show_consensus_management() {
    while true; do
        choice=$(dialog --colors \
                       --title "Consensus Key Management" \
                       --backtitle "Core Node Installer" \
                       --ok-label "Select" \
                       --cancel-label "Back" \
                       --menu "\nManage consensus key:" 15 60 4 \
                       1 "Generate New Consensus Key" \
                       2 "View Consensus Key" \
                       3 "Start Node with Consensus Key" \
                       4 "Back" \
                       2>&1 >/dev/tty) || return 1

        case $choice in
            1)
                generate_consensus_key
                ;;
            2)
                view_consensus_key
                ;;
            3)
                start_node_with_consensus
                ;;
            4)
                return 0
                ;;
        esac
    done
}

setup_node() {
    # Check if node is already installed
    if check_node_installed; then
        dialog --colors \
               --title "Node Already Installed" \
               --backtitle "Core Node Installer" \
               --yesno "\nCore node is already installed.\n\nWould you like to upgrade it?" 10 50
        
        if [ $? -ne 0 ]; then
            return 0
        fi
    fi

    # Main installation steps
    local steps=(
        "Installing Dependencies" "install_dependencies"
        "Cloning Repository" "clone_core_repository"
        "Building Geth" "build_geth"
        "Setting up Node Directory" "setup_node_directory"
    )

    local total_steps=$((${#steps[@]} / 2))
    local current_step=1

    for ((i = 0; i < ${#steps[@]}; i += 2)); do
        local step_name="${steps[i]}"
        local step_function="${steps[i+1]}"

        dialog --colors \
               --title "Core Node Setup ($current_step/$total_steps)" \
               --backtitle "Core Node Installer" \
               --infobox "\nStep $current_step: $step_name" 5 70
        sleep 2

        if ! $step_function; then
            show_error "Failed at step: $step_name"
            return 1
        fi

        ((current_step++))
    done

    show_post_build_menu
    local ret=$?
    if [ $ret -eq 255 ]; then
        return 255  # Return to main menu
    fi
    return $ret
}

# Run setup if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if ! check_dialog; then
        show_error "Dialog is required but not installed.\nPlease install dialog to continue."
        exit 1
    fi
    setup_node
fi

get_validator_address() {
    local address=""
    local temp_file=$(mktemp)
    
    while true; do
        dialog --colors \
               --title "${PRIMARY}Validator Address${NC}" \
               --backtitle "Core Node Installer" \
               --ok-label "Continue" \
               --cancel-label "Back" \
               --extra-button \
               --extra-label "Main Menu" \
               --inputbox "\nEnter your validator address:\n\nTip: Use Ctrl+V or right-click to paste" 12 60 "$address" 2>"$temp_file"

        case $? in
            0) # Continue
                address=$(cat "$temp_file")
                # Validate address format
                if [[ "$address" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
                    rm -f "$temp_file"
                    echo "$address"
                    return 0
                else
                    dialog --colors \
                           --title "${ERROR}Invalid Address${NC}" \
                           --msgbox "\nPlease enter a valid Ethereum address (0x followed by 40 hexadecimal characters)" 8 60
                    continue
                fi
                ;;
            1) # Back
                rm -f "$temp_file"
                return 1
                ;;
            3) # Main Menu
                rm -f "$temp_file"
                return 255
                ;;
        esac
    done
}

show_main_menu() {
    while true; do
        local choice
        choice=$(dialog --colors \
                       --title "${PRIMARY}Core Node Installer${NC}" \
                       --backtitle "Core Node Installer" \
                       --cancel-label "Exit" \
                       --menu "\nSelect an option:" 15 60 8 \
                       1 "Start Node" \
                       2 "Stop Node" \
                       3 "Monitor Logs" \
                       4 "Node Status" \
                       5 "Update Node" \
                       6 "Configure Node" \
                       7 "Uninstall Node" \
                       2>&1 >/dev/tty)

        case $? in
            0) # User selected an option
                case $choice in
                    1) start_node ;;
                    2) stop_node ;;
                    3) show_log_monitor_menu ;;
                    4) show_node_status ;;
                    5) update_node ;;
                    6) configure_node ;;
                    7) uninstall_node ;;
                esac
                ;;
            1) # Exit
                clear
                echo "Thank you for using Core Node Installer!"
                exit 0
                ;;
        esac
    done
}

ensure_node_directories() {
    # Create required directories if they don't exist
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$CORE_CHAIN_DIR"
    mkdir -p "$NODE_DIR/logs"
    mkdir -p "$CORE_CHAIN_DIR/testnet2"

    # Set proper permissions
    chmod 755 "$INSTALL_DIR"
    chmod 755 "$CORE_CHAIN_DIR"
    chmod 755 "$NODE_DIR"
    chmod 755 "$NODE_DIR/logs"
    chmod 755 "$CORE_CHAIN_DIR/testnet2"

    log_message "Node directories created and permissions set" "info"
}

start_node() {
    log_message "Starting Core node" "info"
    show_progress "Starting Core node..."
    
    # Ensure directories exist
    ensure_node_directories
    
    # Check if node is already running
    if pgrep -f "geth.*--networkid 1114" > /dev/null; then
        show_error "Node is already running!"
        return 1
    }

    # Start the node in the background
    cd "$CORE_CHAIN_DIR"
    nohup ./build/bin/geth --config ./testnet2/config.toml \
                          --datadir "$NODE_DIR" \
                          --cache 8000 \
                          --rpc.allow-unprotected-txs \
                          --networkid 1114 \
                          --verbosity 4 \
                          2>&1 | tee -a "$NODE_DIR/logs/core.log" &

    # Wait a moment for the process to start
    sleep 5
    
    # Check if the process is running
    if ! pgrep -f "geth.*--networkid 1114" > /dev/null; then
        show_error "Failed to start node.\nCheck logs at: $NODE_DIR/logs/core.log"
        return 1
    fi

    show_success "Node started successfully!\n\nLog file: $NODE_DIR/logs/core.log"
    
    # Ask if user wants to view logs
    dialog --colors \
           --title "${PRIMARY}View Logs${NC}" \
           --yes-label "View Logs" \
           --no-label "Back" \
           --yesno "\nWould you like to view the node logs now?" 7 50
    
    case $? in
        0) # View logs
            show_live_logs
            ;;
        1) # Back to menu
            return 0
            ;;
    esac
}
