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
        "pv"
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
    dialog --title "Downloading Snapshot" --gauge "Please wait..." 10 70

    show_progress "Decompressing snapshot..."
    lz4 -d coredao-snapshot-testnet-20240327-pruned.tar.lz4 coredao-snapshot-testnet-20240327-pruned.tar
    
    show_progress "Extracting snapshot..."
    tar -xf coredao-snapshot-testnet-20240327-pruned.tar -C "$NODE_DIR"

    check_status "Snapshot downloaded and extracted successfully!" "Failed to download/extract snapshot"
}

check_node_running() {
    # Check if geth is running with our specific datadir
    if pgrep -f "geth.*--datadir.*$NODE_DIR" > /dev/null; then
        return 0  # Node is running
    fi
    return 1  # Node is not running
}

get_node_process_info() {
    ps aux | grep "geth.*--datadir.*$NODE_DIR" | grep -v grep || true
}

get_node_details() {
    local process_info=$(get_node_process_info)
    local details=""
    
    if [[ -n "$process_info" ]]; then
        local pid=$(echo "$process_info" | awk '{print $2}')
        local cpu=$(echo "$process_info" | awk '{print $3}')
        local mem=$(echo "$process_info" | awk '{print $4}')
        
        # Check if running as validator
        if echo "$process_info" | grep -q "mine.*--unlock"; then
            local validator_addr=$(echo "$process_info" | grep -o "unlock [^ ]*" | cut -d' ' -f2)
            details="Status: Running\n"
            details+="Validator Address: $validator_addr\n"
        else
            details="Status: Running\n"
        fi
        
        details+="Process ID: $pid\n"
        details+="CPU Usage: $cpu%\n"
        details+="Memory Usage: $mem%\n"
        
        # Get sync status if possible
        if [[ -S "$NODE_DIR/geth.ipc" ]]; then
            local sync_status
            sync_status=$(./build/bin/geth attach "$NODE_DIR/geth.ipc" --exec 'eth.syncing' 2>/dev/null)
            if [[ "$sync_status" == "false" ]]; then
                local block_number
                block_number=$(./build/bin/geth attach "$NODE_DIR/geth.ipc" --exec 'eth.blockNumber' 2>/dev/null)
                details+="\nSync Status: Synced\n"
                details+="Current Block: $block_number\n"
            else
                details+="\nSync Status: Syncing...\n"
            fi
        fi
    else
        details="Status: Not Running\n"
    fi
    
    echo -e "$details"
}

stop_node() {
    log_message "Attempting to stop Core node"
    show_progress "Stopping Core node..."

    local node_process
    node_process=$(get_node_process_info)

    if [[ -z "$node_process" ]]; then
        show_status "No running node process found" "info"
        return 0
    fi

    # Display current node process info
    dialog --colors \
           --title "Running Node Process" \
           --yesno "\nFound running node process:\n\n\Z3$node_process\Zn\n\nDo you want to stop it?" 12 70

    if [ $? -ne 0 ]; then
        return 1
    fi

    # Try graceful shutdown first
    if pkill -SIGTERM -f "geth.*--datadir.*$NODE_DIR"; then
        # Wait for up to 30 seconds for the process to stop
        local counter=0
        while check_node_running && [ $counter -lt 30 ]; do
            sleep 1
            counter=$((counter + 1))
        done
    fi

    # If process is still running, force kill
    if check_node_running; then
        dialog --colors \
               --title "Force Stop" \
               --yesno "\n\Z1Node did not stop gracefully.\Zn\n\nDo you want to force stop it?" 8 50

        if [ $? -eq 0 ]; then
            pkill -SIGKILL -f "geth.*--datadir.*$NODE_DIR"
            sleep 2
        else
            show_error "Node is still running. Cannot proceed."
            return 1
        fi
    fi

    if ! check_node_running; then
        show_success "Node stopped successfully!"
        return 0
    else
        show_error "Failed to stop node"
        return 1
    fi
}

initialize_genesis() {
    log_message "Initializing genesis block"

    # Check if node is running
    if check_node_running; then
        dialog --colors \
               --title "Node Running" \
               --yesno "\n\Z1Node is currently running!\Zn\n\nDo you want to stop it before initializing genesis?" 10 60

        if [ $? -eq 0 ]; then
            if ! stop_node; then
                show_error "Failed to stop the node. Cannot initialize genesis."
                return 1
            fi
        else
            show_error "Cannot initialize genesis while node is running."
            return 1
        fi
    fi

    show_progress "Initializing genesis block..."

    # Ensure the node directory exists
    mkdir -p "$NODE_DIR"

    # Change to CORE_CHAIN_DIR before executing geth
    if ! cd "$CORE_CHAIN_DIR"; then
        show_error "Failed to access core chain directory"
        return 1
    fi

    # Check if geth binary exists
    if [[ ! -f "./build/bin/geth" ]]; then
        show_error "Geth binary not found. Please ensure the node is properly installed."
        return 1
    fi

    # Capture the output of genesis initialization
    local init_output
    init_output=$(./build/bin/geth --datadir "$NODE_DIR" init "$CORE_CHAIN_DIR/testnet2/genesis.json" 2>&1)
    local init_status=$?

    # Check for specific error patterns
    if echo "$init_output" | grep -q "gap in the chain between ancients"; then
        dialog --colors \
               --title "Database Error" \
               --yesno "\n\Z1Database inconsistency detected!\Zn\n\nThere is a gap in the blockchain data. Would you like to:\n\n1. Reset the database and start fresh\n2. Download a new snapshot\n\nChoose 'Yes' to reset, 'No' to download snapshot." 15 60

        if [ $? -eq 0 ]; then
            # User chose to reset
            dialog --colors \
                   --title "Confirm Reset" \
                   --yesno "\n\Z1Warning: This will delete all existing chain data!\Zn\n\nAre you sure you want to proceed?" 10 60

            if [ $? -eq 0 ]; then
                show_progress "Removing existing chain data..."
                rm -rf "$NODE_DIR/geth/chaindata"
                rm -rf "$NODE_DIR/geth/lightchaindata"
                rm -rf "$NODE_DIR/geth/ancient"

                # Try initialization again
                if ! ./build/bin/geth --datadir "$NODE_DIR" init "$CORE_CHAIN_DIR/testnet2/genesis.json"; then
                    show_error "Failed to initialize genesis block after reset"
                    return 1
                fi
                show_success "Database reset and genesis initialized successfully!"
            else
                return 1
            fi
        else
            # User chose to download snapshot
            dialog --colors \
                   --title "Download Snapshot" \
                   --yesno "\nWould you like to download and apply a fresh snapshot now?" 8 60

            if [ $? -eq 0 ]; then
                if download_and_prepare_snapshot; then
                    show_success "Snapshot downloaded and prepared successfully!"
                    return 0
                else
                    show_error "Failed to download and prepare snapshot"
                    return 1
                fi
            else
                return 1
            fi
        fi
    elif [ $init_status -ne 0 ]; then
        # Handle other initialization errors
        dialog --colors \
               --title "Initialization Error" \
               --msgbox "\n\Z1Genesis initialization failed!\Zn\n\nError:\n$init_output" 15 70
        return 1
    fi

    show_success "Genesis block initialized successfully!"
    return 0
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
./build/bin/geth --config "$CORE_CHAIN_DIR/testnet2/config.toml" \
                 --datadir "$NODE_DIR" \
                 --cache 8000 \
                 --rpc.allow-unprotected-txs \
                 --networkid 1114 \
                 --verbosity 4 \
                 2>&1 | tee "$NODE_DIR/logs/core.log"
EOF

    chmod +x "$INSTALL_DIR/start-node.sh"
    show_success "Startup script created at $INSTALL_DIR/start-node.sh"
}

start_node() {
    log_message "Starting Core node"
    show_progress "Starting Core node..."
    
    # Check if node is already running
    if pgrep -f "geth.*--networkid 1114" > /dev/null; then
        show_error "Node is already running!"
        return 1
    fi

    # Create logs directory if it doesn't exist
    mkdir -p "$NODE_DIR/logs"

    # Start the node in the background
    cd "$CORE_CHAIN_DIR"
    nohup ./build/bin/geth --config "$CORE_CHAIN_DIR/testnet2/config.toml" \
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
        show_error "Failed to start node"
        return 1
    fi

    # Show log file location
    local log_file="$NODE_DIR/logs/core.log"
    
    show_success "Node started successfully!\n\nTo view logs, run:\ntail -f $log_file"
    
    # Ask if user wants to view logs
    dialog --colors \
           --title "View Logs" \
           --yesno "\nWould you like to view the node logs now?" 7 50
    
    if [ $? -eq 0 ]; then
        # Save current directory
        local current_dir=$(pwd)
        
        # Change to script directory to source log monitor
        cd "$SCRIPT_DIR"
        source "./log_monitor.sh"
        
        # Show live logs with navigation
        show_live_logs "$log_file" "Core Node Logs" 50
        local ret=$?
        
        # Handle navigation based on return code
        if [ $ret -eq 3 ]; then  # Main Menu selected
            cd "$current_dir"
            return 0
        fi
        
        # Return to original directory
        cd "$current_dir"
    fi
}

check_node_installed() {
    if [[ -d "$CORE_CHAIN_DIR" ]] && [[ -f "$CORE_CHAIN_DIR/build/bin/geth" ]]; then
        return 0
    fi
    return 1
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

# Function to validate password
validate_password() {
    local password="$1"
    local errors=()
    local requirements_met=0
    
    # Check minimum length
    if [ ${#password} -lt 8 ]; then
        errors+=("Password must be at least 8 characters long")
    else
        ((requirements_met++))
    fi
    
    # Check for uppercase letters
    if ! echo "$password" | grep -q "[A-Z]"; then
        errors+=("Password must contain at least one uppercase letter")
    else
        ((requirements_met++))
    fi
    
    # Check for lowercase letters
    if ! echo "$password" | grep -q "[a-z]"; then
        errors+=("Password must contain at least one lowercase letter")
    else
        ((requirements_met++))
    fi
    
    # Check for numbers
    if ! echo "$password" | grep -q "[0-9]"; then
        errors+=("Password must contain at least one number")
    else
        ((requirements_met++))
    fi
    
    # Check for special characters - Fixed pattern
    if ! printf "%s" "$password" | grep -q '[[:punct:]]'; then
        errors+=("Password must contain at least one special character")
    else
        ((requirements_met++))
    fi
    
    # If there are any errors, show them to the user
    if [ ${#errors[@]} -gt 0 ]; then
        local error_msg="Password requirements not met:\n\n"
        for error in "${errors[@]}"; do
            error_msg+="• \Z1$error\Zn\n"
        done
        error_msg+="\nRequirements met: $requirements_met/5"
        
        dialog --colors \
               --title "Password Requirements" \
               --msgbox "\n$error_msg" 15 60
        return 1
    fi
    
    return 0
}

# Function to check and install Python and bcrypt
check_bcrypt_dependencies() {
    local missing_deps=()
    
    # Check for Python3
    if ! command -v python3 >/dev/null 2>&1; then
        missing_deps+=("python3")
    fi

    # Check for pip
    if ! command -v pip3 >/dev/null 2>&1; then
        missing_deps+=("python3-pip")
    fi

    # If python and pip are available, check for bcrypt
    if command -v python3 >/dev/null 2>&1 && command -v pip3 >/dev/null 2>&1; then
        if ! python3 -c "import bcrypt" 2>/dev/null; then
            missing_deps+=("python3-bcrypt")
        fi
    fi

    # If any dependencies are missing, prompt to install
    if [ ${#missing_deps[@]} -gt 0 ]; then
        dialog --colors \
               --title "Missing Dependencies" \
               --yesno "\nThe following dependencies are required for secure password encryption:\n\n$(printf "• %s\n" "${missing_deps[@]}")\n\nWould you like to install them now?" 12 60
        
        if [ $? -eq 0 ]; then
            show_progress "Installing required dependencies..."
            
            # Install dependencies based on package manager
            if command -v apt-get >/dev/null 2>&1; then
                sudo apt-get update
                sudo apt-get install -y "${missing_deps[@]}"
                # Ensure bcrypt is installed via pip as well
                sudo pip3 install bcrypt
            elif command -v yum >/dev/null 2>&1; then
                sudo yum install -y python3 python3-pip
                sudo pip3 install bcrypt
            elif command -v pacman >/dev/null 2>&1; then
                sudo pacman -Sy --noconfirm python python-pip
                sudo pip3 install bcrypt
            else
                show_error "Unsupported package manager.\nPlease install Python3 and bcrypt manually."
                return 1
            fi
            
            # Verify installation
            if ! python3 -c "import bcrypt" 2>/dev/null; then
                show_error "Failed to install bcrypt.\nPlease install it manually."
                return 1
            fi
        else
            return 1
        fi
    fi
    
    return 0
}

# Function to encrypt password using bcrypt
encrypt_password() {
    local password="$1"
    local python_script=$(cat << 'EOF'
import bcrypt
import sys
import base64

password = sys.stdin.read().encode('utf-8')
salt = bcrypt.gensalt()
hashed = bcrypt.hashpw(password, salt)
print(base64.b64encode(hashed).decode('utf-8'))
EOF
)
    echo -n "$password" | python3 -c "$python_script"
}

# Function to verify password using bcrypt
verify_password() {
    local password="$1"
    local hashed="$2"
    local python_script=$(cat << 'EOF'
import bcrypt
import sys
import base64

password = sys.stdin.readline().strip().encode('utf-8')
hashed = base64.b64decode(sys.stdin.readline().strip())
if bcrypt.checkpw(password, hashed):
    sys.exit(0)
sys.exit(1)
EOF
)
    echo -e "$password\n$hashed" | python3 -c "$python_script"
}

# Function to securely write encrypted password to file
write_password_securely() {
    local password="$1"
    local password_file="$2"
    local old_umask
    
    # Check bcrypt dependencies first
    if ! check_bcrypt_dependencies; then
        return 1
    fi
    
    # Encrypt the password
    local encrypted_password
    encrypted_password=$(encrypt_password "$password")
    if [ $? -ne 0 ]; then
        log_message "Failed to encrypt password" "error"
        return 1
    fi
    
    # Save current umask
    old_umask=$(umask)
    
    # Set restrictive permissions before file creation (u=rw,g=,o=)
    umask 0177
    
    # Create file with secure permissions from the start
    # Use file descriptor to write directly without temporary files
    if ! (
        exec 3>"$password_file"
        printf "%s" "$encrypted_password" >&3
        exec 3>&-
    ); then
        # Restore original umask
        umask "$old_umask"
        return 1
    fi
    
    # Restore original umask
    umask "$old_umask"
    
    # Double-check file permissions (defense in depth)
    if ! chmod 0600 "$password_file"; then
        rm -f "$password_file"
        return 1
    fi
    
    # Verify file permissions
    local file_perms
    file_perms=$(stat -c '%a' "$password_file")
    if [ "$file_perms" != "600" ]; then
        rm -f "$password_file"
        return 1
    fi
    
    return 0
}

# Function to read and verify encrypted password
read_encrypted_password() {
    local password_file="$1"
    local entered_password="$2"
    
    # Read the encrypted password from file
    local stored_hash
    stored_hash=$(cat "$password_file")
    
    # Verify the password
    if ! verify_password "$entered_password" "$stored_hash"; then
        return 1
    fi
    
    return 0
}

generate_consensus_key() {
    log_message "Generating consensus key"
    show_progress "Preparing to generate a new consensus key..."

    local PASSWORD_FILE="$CORE_CHAIN_DIR/password.txt"
    local KEYSTORE_DIR="$NODE_DIR/keystore"
    local VALIDATOR_FILE="$CORE_CHAIN_DIR/validator_address.txt"

    mkdir -p "$NODE_DIR"

    # Show password requirements before asking for password
    dialog --colors \
           --title "Password Requirements" \
           --msgbox "\nYour password must meet the following requirements:\n\n\
• Minimum 8 characters long\n\
• At least one uppercase letter\n\
• At least one lowercase letter\n\
• At least one number\n\
• At least one special character (!@#$%^&*()_+-=[]{}|;:'\",.<>?/)" 15 70

    while true; do
        # Ask for password
        local password1 password2
        password1=$(dialog --insecure --no-cancel \
            --title "Set Password" \
            --passwordbox "\nEnter a password to protect your consensus key:" 10 60 3>&1 1>&2 2>&3)

        # Check if password is empty
        if [ -z "$password1" ]; then
            dialog --colors \
                   --title "Invalid Password" \
                   --msgbox "\n\Z1Password cannot be empty!\Zn" 7 40
            continue
        fi

        # Validate password strength
        if ! validate_password "$password1"; then
            dialog --colors \
                   --title "Invalid Password" \
                   --yesno "\nWould you like to try again?" 7 40
            if [ $? -ne 0 ]; then
                return 1
            fi
            continue
        fi

        password2=$(dialog --insecure --no-cancel \
            --title "Confirm Password" \
            --passwordbox "\nRe-enter your password:" 10 60 3>&1 1>&2 2>&3)

        if [[ "$password1" != "$password2" ]]; then
            dialog --colors \
                   --title "Password Mismatch" \
                   --yesno "\n\Z1Passwords do not match!\Zn\n\nWould you like to try again?" 8 50
            
            if [ $? -ne 0 ]; then
                return 1
            fi
            continue
        fi

        # Save password securely using the new function
        if ! write_password_securely "$password1" "$PASSWORD_FILE"; then
            log_message "Failed to securely write password file" "error"
            dialog --colors \
                   --title "Security Error" \
                   --yesno "\n\Z1Failed to securely save password!\Zn\n\nWould you like to try again?" 8 50
            
            if [ $? -ne 0 ]; then
                return 1
            fi
            continue
        fi

        # Generate account using password
        local output
        cd "$CORE_CHAIN_DIR"
        
        # Log the attempt
        log_message "Attempting to generate new consensus key"
        
        if ! output=$(./build/bin/geth --datadir "$NODE_DIR" account new --password "$PASSWORD_FILE" 2>&1); then
            local error_msg="\n\Z1Failed to generate consensus key!\Zn\n\nError details:\n$output"
            log_message "Failed to generate consensus key: $output" "error"
            
            dialog --colors \
                   --title "Error" \
                   --yesno "$error_msg\n\nWould you like to try again?" 12 70
            
            if [ $? -ne 0 ]; then
                return 1
            fi
            continue
        fi

        # Log success
        log_message "Successfully generated new consensus key"

        # Find the newest keystore file
        local keystore_file=$(find "$KEYSTORE_DIR" -type f -name "UTC--*" -printf '%T@ %p\n' | sort -n | tail -1 | cut -f2- -d" ")
        
        if [[ ! -f "$keystore_file" ]]; then
            log_message "Keystore file not found after generation" "error"
            dialog --colors \
                   --title "Error" \
                   --yesno "\n\Z1Keystore file not found!\Zn\n\nWould you like to try again?" 8 50
            
            if [ $? -ne 0 ]; then
                return 1
            fi
            continue
        fi

        # Extract address from keystore file
        local address=$(grep -o '"address":"[^"]*"' "$keystore_file" | cut -d'"' -f4)
        
        if [[ -z "$address" ]]; then
            dialog --colors \
                   --title "Error" \
                   --yesno "\n\Z1Failed to extract address from keystore!\Zn\n\nWould you like to try again?" 8 50
            
            if [ $? -ne 0 ]; then
                return 1
            fi
            continue
        fi

        # Save address for future use
        echo "0x$address" > "$VALIDATOR_FILE"

        # Show success message with address and keystore details
        dialog --colors \
               --title "✓ Consensus Key Generated" \
               --msgbox "\nValidator Address:\n\n\Zb\Z2 0x$address \Zn\n\nKeystore Location:\n$keystore_file\n\nPassword File:\n$PASSWORD_FILE\n\n\Z3⚠️  Please backup these files securely!\Zn" 15 70

        # Offer to start node
        dialog --colors \
               --title "Start Node with New Consensus Key" \
               --menu "\nChoose how to proceed:" 15 60 3 \
               1 "Start Node" \
               2 "Start Node as Validator (unlock & mine)" \
               3 "Return to Menu" 2> /tmp/consensus_next

        local next_action
        next_action=$(< /tmp/consensus_next)
        rm -f /tmp/consensus_next

        case "$next_action" in
            1)
                initialize_genesis && start_node
                ;;
            2)
                initialize_genesis && start_node_with_validator "$address"
                ;;
        esac

        break
    done

    return 0
}

# Function to check if a port is in use
check_port_in_use() {
    local port=$1
    
    # Try different methods to check port usage
    if command -v netstat >/dev/null 2>&1; then
        netstat -tuln | grep -q ":$port "
        return $?
    elif command -v ss >/dev/null 2>&1; then
        ss -tuln | grep -q ":$port "
        return $?
    elif command -v lsof >/dev/null 2>&1; then
        lsof -i ":$port" >/dev/null 2>&1
        return $?
    else
        # If no tools available, try a direct check
        (echo >/dev/tcp/localhost/$port) >/dev/null 2>&1
        return $?
    fi
}

# Function to cleanup existing node process
cleanup_node_process() {
    local force=$1
    
    # First try to find any existing geth process
    local pid
    pid=$(pgrep -f "geth.*--mine" 2>/dev/null || pgrep -f "build/bin/geth" 2>/dev/null)
    
    if [ ! -z "$pid" ]; then
        if [ "$force" = "force" ]; then
            log_message "Force stopping existing node process (PID: $pid)"
            kill -9 "$pid" 2>/dev/null
            sleep 2
        else
            log_message "Gracefully stopping existing node process (PID: $pid)"
            kill "$pid" 2>/dev/null
            
            # Wait up to 10 seconds for graceful shutdown
            local counter=0
            while [ $counter -lt 10 ] && kill -0 "$pid" 2>/dev/null; do
                sleep 1
                counter=$((counter + 1))
            done
            
            # If process still exists, force kill
            if kill -0 "$pid" 2>/dev/null; then
                log_message "Process still running, force stopping (PID: $pid)"
                kill -9 "$pid" 2>/dev/null
                sleep 2
            fi
        fi
    fi
}

start_node_with_validator() {
    local consensus_address="$1"
    local VALIDATOR_CONFIG_DIR="$CORE_CHAIN_DIR/validator_config"
    local VALIDATOR_PASSWORD_FILE="$CORE_CHAIN_DIR/password.txt"
    local NODE_KEYSTORE_DIR="$NODE_DIR/keystore"
    local TEMP_PASSWORD_FILE

    # Create temporary password file with appropriate permissions
    TEMP_PASSWORD_FILE=$(mktemp)
    chmod 600 "$TEMP_PASSWORD_FILE"
    
    # Ask for the validator password
    local entered_password
    entered_password=$(dialog --insecure --no-cancel \
        --title "Validator Password" \
        --passwordbox "\nEnter your validator password:" 10 60 3>&1 1>&2 2>&3)
    
    # Verify the password
    if ! read_encrypted_password "$VALIDATOR_PASSWORD_FILE" "$entered_password"; then
        rm -f "$TEMP_PASSWORD_FILE"
        show_error "Invalid validator password"
            return 1
    fi
    
    # Write the decrypted password to temporary file for geth
    echo -n "$entered_password" > "$TEMP_PASSWORD_FILE"

    # Start the node with the temporary password file
    local result=0
    if ! start_node_with_password "$consensus_address" "$TEMP_PASSWORD_FILE"; then
        result=1
    fi
    
    # Clean up
    rm -f "$TEMP_PASSWORD_FILE"
    return $result
}

view_consensus_key() {
    local VALIDATOR_FILE="$CORE_CHAIN_DIR/validator_address.txt"

    if [[ ! -f "$VALIDATOR_FILE" ]]; then
        dialog --colors \
               --title "Consensus Key" \
               --msgbox "\n\Z1No consensus key found.\Zn\n\nPlease generate one first." 8 50
        return
    fi

    local address
    address=$(< "$VALIDATOR_FILE")

    dialog --colors \
           --title "Consensus Key" \
           --msgbox "\nYour validator address is:\n\n\Zb\Z2$address\Zn\n\nStored at:\n$VALIDATOR_FILE" 12 60
}

show_post_build_menu() {
    while true; do
        choice=$(show_navigation_buttons "Core Node Setup" \
            "Start Node (Without Snapshot)" \
            "Download Snapshot First" \
            "Generate Consensus Key" \
            "View Consensus Key" \
            "View Node Status" \
            "Exit")

        case $choice in
            1)
                if initialize_genesis && start_node; then
                    return 0
                fi
                ;;
            2)
                download_snapshot_with_progress || true
                ;;
            3)
                generate_consensus_key
                ;;
            4)
                view_consensus_key
                ;;
            5)
                show_node_status
                ;;
            6)
                return 0
                ;;
        esac
    done
}

# Function to verify file MD5
verify_snapshot_md5() {
    local file="$1"
    local expected_md5="12e1b6d7e76e4badba8ab40542167305"
    
    # Show progress dialog
    dialog --colors \
           --title "Verifying Snapshot" \
           --infobox "\nCalculating MD5 checksum...\nThis may take a few minutes." 5 50
    
    # Calculate MD5
    local actual_md5
    actual_md5=$(md5sum "$file" | cut -d' ' -f1)
    
    # Compare MD5 hashes
    if [ "$actual_md5" = "$expected_md5" ]; then
        return 0
    fi
    return 1
}

download_snapshot_with_progress() {
    local snapshot_url="https://snap.coredao.org/coredao-snapshot-testnet-20240327-pruned.tar.lz4"
    local snapshot_file="coredao-snapshot-testnet-20240327-pruned.tar.lz4"
    local partial_file="${snapshot_file}.partial"
    local max_retries=5
    local retry_count=0
    local wait_time=5
    local success=0
    local cancelled=0
    
    cd "$CORE_CHAIN_DIR"
    
    # Check and install dependencies if needed
    if ! check_snapshot_dependencies; then
        return 1
    fi
    
    # Show initial progress dialog
    dialog --colors \
           --title "Preparing Download" \
           --infobox "\nGetting snapshot information..." 5 40
    
    # Get total file size with retry
    local total_size=""
    for ((i=1; i<=3; i++)); do
        total_size=$(curl -sI "$snapshot_url" | grep -i Content-Length | awk '{print $2}' | tr -d '\r')
        if [ -n "$total_size" ]; then
            break
        fi
        sleep $((i * 2))
    done
    
    if [ -z "$total_size" ]; then
        show_error "Could not determine snapshot size.\nPlease check your internet connection."
        return 1
    fi
    
    local total_size_hr=$(numfmt --to=iec-i --suffix=B "$total_size")
    
    while [ $retry_count -lt $max_retries ] && [ $success -eq 0 ] && [ $cancelled -eq 0 ]; do
        # Check for partial download
        local resume_offset=0
        if [ -f "$partial_file" ]; then
            resume_offset=$(stat -c%s "$partial_file")
            dialog --colors \
                   --title "Resume Download" \
                   --yesno "\nPartially downloaded file found ($resume_offset bytes).\nWould you like to resume the download?" 8 60
            
            if [ $? -ne 0 ]; then
                rm -f "$partial_file"
                resume_offset=0
            fi
        fi
        
        # Create named pipe for download control
        local pipe="/tmp/download_pipe_$$"
        mkfifo "$pipe"
        
        # Start download in background
        (
            if [ $resume_offset -gt 0 ]; then
                curl -L -C $resume_offset --connect-timeout 30 --retry 3 --retry-delay 5 --max-time 7200 "$snapshot_url" 2>&1 | \
                pv -s $((total_size - resume_offset)) >> "$partial_file" &
            else
                curl -L --connect-timeout 30 --retry 3 --retry-delay 5 --max-time 7200 "$snapshot_url" 2>&1 | \
                pv -s $total_size > "$partial_file" &
            fi
            echo $! > "$pipe"
        ) 2>&1 | \
        while read -r percent; do
            percent=${percent%%.*}
            if [ -n "$percent" ]; then
                # Calculate overall progress including resumed portion
                if [ $resume_offset -gt 0 ]; then
                    percent=$(( (resume_offset * 100 / total_size) + (percent * (total_size - resume_offset) / total_size) ))
                fi
            echo "XXX"
                echo "$percent"
                echo -e "\nDownloading Core Snapshot ($total_size_hr)...\n\nAttempt $(($retry_count + 1)) of $max_retries\n\nThis may take a while depending on your internet speed.\n\nPress ESC to cancel download."
            echo "XXX"
            fi
        done | dialog --title "Downloading Snapshot" \
               --backtitle "Core Node Installer" \
                     --gauge "" 12 70 0
    
        # Get the download process ID
        read pid < "$pipe"
        rm -f "$pipe"
        
        # Check if dialog was cancelled (ESC pressed)
    if [ $? -eq 1 ]; then
            kill $pid 2>/dev/null
            cancelled=1
            dialog --colors \
                   --title "Download Cancelled" \
                   --yesno "\nDownload was cancelled.\n\nWould you like to try again?" 8 50
            
            if [ $? -eq 0 ]; then
                cancelled=0
                continue
            else
                rm -f "$partial_file"
        return 1
            fi
        fi
        
        # Verify download completion
        if [ -f "$partial_file" ]; then
            local actual_size=$(stat -c%s "$partial_file")
            
            # Allow for small difference (1MB) in file size
            local size_diff=$((total_size - actual_size))
            if [ "${size_diff#-}" -lt 1048576 ]; then
                success=1
                mv "$partial_file" "$snapshot_file"
                break
            else
                # Show detailed size mismatch
                local actual_hr=$(numfmt --to=iec-i --suffix=B $actual_size)
                local percent_complete=$(( actual_size * 100 / total_size ))
                
                # Auto-retry with notification
                dialog --colors \
                       --title "Download Incomplete" \
                       --timeout 5 \
                       --no-cancel \
                       --infobox "\nDownload incomplete ($percent_complete% downloaded)\n\nReceived: $actual_hr\nExpected: $total_size_hr\n\nAutomatically retrying in 5 seconds...\nPress ESC to cancel." 10 60
            fi
        else
            # Auto-retry with notification
            dialog --colors \
                   --title "Download Failed" \
                   --timeout 5 \
                   --no-cancel \
                   --infobox "\nDownload failed.\n\nAutomatically retrying in 5 seconds...\nPress ESC to cancel." 8 50
        fi
        
        retry_count=$((retry_count + 1))
        wait_time=$((wait_time * 2))  # Exponential backoff
        
        if [ $retry_count -lt $max_retries ] && [ $success -eq 0 ] && [ $cancelled -eq 0 ]; then
            sleep 5  # Fixed 5-second wait before retry
        fi
    done
    
    if [ $success -eq 1 ]; then
        # Verify file integrity
        dialog --colors \
               --title "Verifying Download" \
               --infobox "\nVerifying downloaded snapshot..." 5 40
        
        if ! verify_snapshot_md5 "$snapshot_file"; then
            dialog --colors \
                   --title "Verification Failed" \
                   --yesno "\nMD5 checksum verification failed!\n\nWould you like to try downloading again?" 10 60
            
            if [ $? -eq 0 ]; then
                rm -f "$snapshot_file"
                download_snapshot_with_progress
                return $?
            else
                rm -f "$snapshot_file"
                show_error "Download verification failed"
                return 1
            fi
        fi
        
        show_success "Snapshot downloaded and verified successfully!"
    return 0
    else
        if [ $cancelled -eq 1 ]; then
            show_error "Download cancelled by user"
        else
            show_error "Failed to download after $max_retries attempts.\nPlease check your internet connection and try again later."
        fi
        rm -f "$partial_file"
        return 1
    fi
}

show_node_status() {
    local temp_file=$(mktemp)
    cd "$CORE_CHAIN_DIR"
    
    {
        echo "Core Node Status"
        echo "================"
        echo
        
        # Get detailed node status
        echo -e "$(get_node_details)"
        echo
        
        echo "Installation Details"
        echo "-------------------"
        echo "Installation Directory: $INSTALL_DIR"
        echo "Data Directory: $NODE_DIR"
        echo "Log File: $NODE_DIR/logs/core.log"
        echo
        
        # Show validator information if available
        if [[ -f "$CORE_CHAIN_DIR/validator_address.txt" ]]; then
            echo "Validator Configuration"
            echo "---------------------"
            echo "Configured Validator: $(cat "$CORE_CHAIN_DIR/validator_address.txt")"
            echo
        fi
        
        echo "Last 5 Log Entries"
        echo "-----------------"
        if [[ -f "$NODE_DIR/logs/core.log" ]]; then
            tail -n 5 "$NODE_DIR/logs/core.log" 2>/dev/null
        else
            echo "No logs available yet"
        fi
        
    } > "$temp_file"

    dialog --colors \
           --title "Node Status" \
           --backtitle "Core Node Installer" \
           --ok-label "Back" \
           --extra-button \
           --extra-label "Main Menu" \
           --textbox "$temp_file" 25 75

    local ret=$?
    rm -f "$temp_file"
    return $ret
}

show_node_management() {
    while true; do
        local node_status="Stopped"
        if check_node_running; then
            node_status="Running"
        fi

        local validator_address=""
        if [[ -f "$CORE_CHAIN_DIR/validator_address.txt" ]]; then
            validator_address=$(cat "$CORE_CHAIN_DIR/validator_address.txt")
        fi
        
        # Get current node details for the menu title
        local status_details
        if [[ "$node_status" == "Running" ]]; then
            if get_node_process_info | grep -q "mine.*--unlock"; then
                status_details=" (Validator Mode)"
            else
                status_details=" (Normal Mode)"
            fi
        fi
        
        choice=$(show_navigation_buttons "Node Management - Status: $node_status" \
            "Start Node" \
            "Start Node as Validator" \
            "Stop Node" \
            "Generate Consensus Key" \
            "View Consensus Key" \
            "View Logs" \
            "View Node Status" \
            "Download & Sync Snapshot" \
            "Back to Main Menu")
        
        case $choice in
            1)
                if check_node_running; then
                    show_error "Node is already running!"
                else
                    initialize_genesis && start_node
                fi
                ;;
            2)
                if check_node_running; then
                    show_error "Node is already running!"
                elif [[ -z "$validator_address" ]]; then
                    show_error "No validator address found.\nPlease generate a consensus key first."
                else
                    initialize_genesis && start_node_with_validator "$validator_address"
                fi
                ;;
            3)
                if ! check_node_running; then
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
                # Save current directory
                local current_dir=$(pwd)
                
                # Change to script directory before sourcing log monitor
                cd "$SCRIPT_DIR"
                source "./log_monitor.sh"
                
                # Show log monitor menu and handle navigation
                while true; do
                    show_log_monitor_menu
                    local ret=$?
                    
                    # Handle navigation based on return code
                    if [ $ret -eq 0 ]; then  # Normal exit (Back)
                        break
                    elif [ $ret -eq 3 ]; then  # Extra button (Main Menu)
                        cd "$current_dir"
                        return 0
                    elif [ $ret -eq 1 ]; then  # Cancel
                        break
                    fi
                done
                
                # Return to original directory
                cd "$current_dir"
                ;;
            7)
                show_node_status
                local ret=$?
                if [ $ret -eq 3 ]; then  # Extra button (Main Menu)
                    return 0
                fi
                ;;
            8)
                dialog --colors \
                       --title "Download & Sync Snapshot" \
                       --yesno "\nThis will:\n\n1. Download the latest snapshot\n2. Extract it to the node directory\n3. Start the node in snapshot sync mode\n\nDo you want to continue?" 12 60
                
                if [ $? -eq 0 ]; then
                    if download_and_prepare_snapshot; then
                        dialog --colors \
                               --title "Start with Snapshot" \
                               --yesno "\nSnapshot prepared successfully!\n\nWould you like to start the node with snapshot sync now?" 10 60
                        
                        if [ $? -eq 0 ]; then
                            initialize_genesis && start_node_with_snapshot
                        fi
                    fi
                fi
                ;;
            9)
                return 0
                ;;
            *)
                if [ $? -eq 3 ]; then  # Extra button (Main Menu)
                    return 0
                fi
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

# Function to check and install required tools
check_snapshot_dependencies() {
    local missing_deps=()
    
    # Check for curl
    if ! command -v curl >/dev/null 2>&1; then
        missing_deps+=("curl")
    fi
    
    # Check for pv
    if ! command -v pv >/dev/null 2>&1; then
        missing_deps+=("pv")
    fi
    
    # Check for lz4
    if ! command -v lz4 >/dev/null 2>&1; then
        missing_deps+=("lz4")
    fi
    
    # If any dependencies are missing, try to install them
    if [ ${#missing_deps[@]} -gt 0 ]; then
        dialog --colors \
               --title "Missing Dependencies" \
               --yesno "\nThe following tools are required but not installed:\n\n$(printf "• %s\n" "${missing_deps[@]}")\n\nWould you like to install them now?" 12 60
        
        if [ $? -eq 0 ]; then
            show_progress "Installing required dependencies..."
            
            # Detect package manager and install
            if command -v apt-get >/dev/null 2>&1; then
                sudo apt-get update && sudo apt-get install -y "${missing_deps[@]}"
            elif command -v yum >/dev/null 2>&1; then
                sudo yum install -y epel-release && sudo yum install -y "${missing_deps[@]}"
            else
                show_error "Could not detect package manager.\nPlease install: ${missing_deps[*]}"
                return 1
            fi
        else
            show_error "Required dependencies must be installed to continue."
            return 1
        fi
    fi
    return 0
}

# Function to format progress for dialog
format_progress() {
    local current=$1
    local total=$2
    local width=50  # Progress bar width
    local percentage=$((current * 100 / total))
    local filled=$((percentage * width / 100))
    local empty=$((width - filled))
    
    # Create the progress bar string
    local bar="["
    for ((i=0; i<filled; i++)); do bar+="#"; done
    for ((i=0; i<empty; i++)); do bar+="-"; done
    bar+="]"
    
    # Format percentage with padding
    printf "Progress: %s %3d%%\n" "$bar" "$percentage"
}

# Function to attempt download with retries
attempt_download() {
    local url="$1"
    local output_file="$2"
    local expected_size="$3"
    local max_retries=3
    local retry_count=0
    local success=0

    while [ $retry_count -lt $max_retries ] && [ $success -eq 0 ]; do
        # Show retry attempt if not first try
        if [ $retry_count -gt 0 ]; then
            dialog --colors \
                   --title "Retrying Download" \
                   --yesno "\nDownload attempt $((retry_count + 1)) of $max_retries\n\nWould you like to retry?" 10 60
            
            if [ $? -ne 0 ]; then
                return 1
            fi
        fi

        # Show download progress with proper pv handling
        if (
            curl -L --connect-timeout 30 --retry 3 --retry-delay 5 --max-time 7200 "$url" | \
            pv -n -s "$expected_size" > "$output_file"
        ) 2>&1 | \
        while read -r percent; do
            percent=${percent%%.*} # trim decimal if any
            echo "XXX"
            echo "$percent"
            echo -e "\nDownloading Core Snapshot...\n\nAttempt $(($retry_count + 1)) of $max_retries\n\nThis may take a while depending on your internet speed.\n\nExpected Size: $(numfmt --to=iec-i --suffix=B $expected_size)"
            echo "XXX"
        done | dialog --title "Downloading Snapshot" \
                     --backtitle "Core Node Installer" \
                     --gauge "" 12 70 0; then

            # Verify the downloaded file
            if [ -f "$output_file" ]; then
                local actual_size=$(stat -c%s "$output_file" 2>/dev/null)
                
                # Allow for small difference (1MB) in file size
                local size_diff=$((expected_size - actual_size))
                if [ "${size_diff#-}" -lt 1048576 ]; then
                    success=1
                    break
                else
                    # Show detailed size mismatch
                    local actual_hr=$(numfmt --to=iec-i --suffix=B $actual_size)
                    local expected_hr=$(numfmt --to=iec-i --suffix=B $expected_size)
                    local percent_complete=$(( actual_size * 100 / expected_size ))
                    
                    dialog --colors \
                           --title "Download Incomplete" \
                           --yesno "\nDownload is incomplete ($percent_complete% downloaded)\n\nReceived: $actual_hr\nExpected: $expected_hr\n\nWould you like to retry?" 12 60
                    
                    if [ $? -ne 0 ]; then
                        return 1
                    fi
                fi
            else
                dialog --colors \
                       --title "Download Failed" \
                       --yesno "\nDownload failed - no file was created.\n\nWould you like to retry?" 10 60
                
                if [ $? -ne 0 ]; then
                    return 1
                fi
            fi
        else
            # curl|pv pipeline failed
            dialog --colors \
                   --title "Download Error" \
                   --yesno "\nDownload was interrupted.\n\nWould you like to retry?" 10 60
            
            if [ $? -ne 0 ]; then
                return 1
            fi
        fi

        retry_count=$((retry_count + 1))
        rm -f "$output_file" 2>/dev/null
    done

    if [ $success -eq 1 ]; then
        return 0
    else
        show_error "Failed to download after $max_retries attempts.\nPlease check your internet connection and try again later."
        return 1
    fi
}

# Function to download and prepare snapshot
download_and_prepare_snapshot() {
    local snapshot_url="https://snap.coredao.org/coredao-snapshot-testnet2-20250221-pruned.tar.lz4"
    local snapshot_file="coredao-snapshot-testnet2-20250221-pruned.tar.lz4"
    local extracted_file="coredao-snapshot-testnet2-20250221-pruned.tar"
    
    # Check and install dependencies if needed
    if ! check_snapshot_dependencies; then
        return 1
    fi
    
    log_message "Starting snapshot download"
    cd "$CORE_CHAIN_DIR"

    # Show initial progress dialog
    dialog --colors \
           --title "Preparing Download" \
           --infobox "\nGetting snapshot information..." 5 40
    sleep 1

    # Get total file size
    local total_size=$(curl -sI "$snapshot_url" | grep -i Content-Length | awk '{print $2}' | tr -d '\r')
    
    if [ -z "$total_size" ]; then
        show_error "Could not determine snapshot size.\nPlease check your internet connection."
        return 1
    fi

    local total_size_hr=$(numfmt --to=iec-i --suffix=B "$total_size")
    
    # Remove existing files if they exist
    rm -f "$snapshot_file" "$extracted_file" 2>/dev/null

    # Show download progress with proper pv handling
    if ! (
        curl -L "$snapshot_url" | \
        pv -n -s "$total_size" > "$snapshot_file"
    ) 2>&1 | \
    while read -r percent; do
        percent=${percent%%.*} # trim decimal if any
        echo "XXX"
        echo "$percent"
        echo -e "\nDownloading Core Snapshot ($total_size_hr)...\n\nThis may take a while depending on your internet speed and the data size."
        echo "XXX"
    done | dialog --title "Downloading Snapshot" \
                  --backtitle "Core Node Installer" \
                  --gauge "" 10 70 0; then
        show_error "Download failed.\nPlease check your internet connection and try again."
        rm -f "$snapshot_file" 2>/dev/null
        return 1
    fi

    # Verify download
    if [ ! -f "$snapshot_file" ] || [ ! -s "$snapshot_file" ]; then
        show_error "Failed to download snapshot or file is empty"
        rm -f "$snapshot_file" 2>/dev/null
        return 1
    fi

    # Get actual size
    local actual_size=$(stat -c%s "$snapshot_file" 2>/dev/null)
    if [ "$actual_size" != "$total_size" ]; then
        show_error "Download incomplete.\nExpected: $total_size_hr\nGot: $(numfmt --to=iec-i --suffix=B $actual_size)"
        rm -f "$snapshot_file" 2>/dev/null
        # Attempt download with retries
        if ! attempt_download "$snapshot_url" "$snapshot_file" "$total_size"; then  
            return 1
        fi
    fi

    # Verify integrity
    dialog --title "Verifying Download" \
           --backtitle "Core Node Installer" \
           --infobox "\nVerifying downloaded snapshot..." 5 40
    
    if ! lz4 -t "$snapshot_file" > /dev/null 2>&1; then
        dialog --colors \
               --title "Verification Failed" \
               --yesno "\nThe downloaded file appears to be corrupted.\n\nWould you like to try downloading again?" 10 60
        
        if [ $? -eq 0 ]; then
            rm -f "$snapshot_file"
            # Recursive call to try again
            download_and_prepare_snapshot
            return $?
        else
            show_error "Download verification failed.\nPlease try again later."
            rm -f "$snapshot_file"
            return 1
        fi
    fi

    # Show verification success
    dialog --colors \
           --title "✓ Verification Success" \
           --msgbox "\nSnapshot file verified successfully!" 7 40

    # Decompression
    dialog --title "Decompressing Snapshot" \
           --backtitle "Core Node Installer" \
           --infobox "\nPreparing to decompress snapshot..." 5 40
    sleep 1

    if ! (pv -n "$snapshot_file" | lz4 -d > "$extracted_file") 2>&1 | \
        dialog --title "Decompressing Snapshot" \
               --backtitle "Core Node Installer" \
               --gauge "\nDecompressing snapshot...\n\nThis may take a while depending on your system speed." 10 70; then
        show_error "Failed to decompress snapshot"
        rm -f "$snapshot_file" "$extracted_file"
        return 1
    fi

    if [ ! -f "$extracted_file" ] || [ ! -s "$extracted_file" ]; then
        show_error "Decompression failed or produced empty file"
        rm -f "$snapshot_file" "$extracted_file"
        return 1
    fi

    # Show decompression success
    dialog --colors \
           --title "✓ Decompression Success" \
           --msgbox "\nSnapshot decompressed successfully!" 7 40

    # Extraction
    dialog --title "Extracting Snapshot" \
           --backtitle "Core Node Installer" \
           --infobox "\nPreparing to extract snapshot..." 5 40
    sleep 1

    mkdir -p "$NODE_DIR"

    if ! (pv -n "$extracted_file" | tar xf - -C "$NODE_DIR") 2>&1 | \
        dialog --title "Extracting Snapshot" \
               --backtitle "Core Node Installer" \
               --gauge "\nExtracting snapshot...\n\nThis may take a while depending on your disk speed." 10 70; then
        show_error "Failed to extract snapshot"
        rm -f "$snapshot_file" "$extracted_file"
        return 1
    fi

    rm -f "$snapshot_file" "$extracted_file"
    
    show_success "Snapshot downloaded and prepared successfully!"
    return 0
}

# Function to start node with snapshot sync
start_node_with_snapshot() {
    local log_file="$NODE_DIR/logs/core.log"
    
    # Check if node is already running
    if check_node_running; then
        show_error "Node is already running. Please stop it first."
        return 1
    fi

    log_message "Starting Core node with snapshot sync"
    show_progress "Starting Core node..."

    cd "$CORE_CHAIN_DIR"

    # Create logs directory if it doesn't exist
    mkdir -p "$NODE_DIR/logs"

    # Clear existing log
    : > "$log_file"

    nohup ./build/bin/geth \
        --config "$CORE_CHAIN_DIR/testnet2/config.toml" \
        --datadir "$NODE_DIR" \
        --syncmode snap \
        --networkid 1114 \
        --cache 8000 \
        --verbosity 4 \
        2>&1 | tee -a "$log_file" &

    # Wait for up to 10 seconds for the node to start
    local counter=0
    while [ $counter -lt 10 ]; do
        sleep 1
        if grep -q "Started P2P networking" "$log_file" 2>/dev/null; then
            show_success "Node started successfully with snapshot sync!"
            return 0
        fi
        counter=$((counter + 1))
    done

    if check_node_running; then
        show_success "Node started successfully with snapshot sync!"
        return 0
    else
        show_error "Failed to start node. Check logs for details."
        return 1
    fi
}

# Run setup if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if ! check_dialog; then
        show_error "Dialog is required but not installed.\nPlease install dialog to continue."
        exit 1
    fi
    setup_node
fi
