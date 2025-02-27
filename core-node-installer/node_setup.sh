#!/bin/bash

# Source utils
source ./utils.sh

# Installation directory
INSTALL_DIR="$HOME/core-node"
CORE_CHAIN_DIR="$INSTALL_DIR/core-chain"
NODE_DIR="$CORE_CHAIN_DIR/node"

install_dependencies() {
    log_message "Installing dependencies"
    show_progress "Installing required packages..."
    
    if [ -f /etc/debian_version ]; then
        sudo apt update
        sudo apt install -y git gcc make curl lz4 golang unzip
    elif [ -f /etc/redhat-release ]; then
        sudo yum install -y git gcc make curl lz4 golang unzip
    else
        show_error "Unsupported distribution. Please install dependencies manually."
        return 1
    fi

    # Verify installations
    local FAILED=0
    for cmd in git gcc make curl lz4 go unzip; do
        if ! command -v $cmd &> /dev/null; then
            show_error "$cmd is not installed properly"
            FAILED=1
        fi
    done

    if [ $FAILED -eq 1 ]; then
        return 1
    fi

    show_success "All dependencies installed successfully!"
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
        git pull
    else
        git clone https://github.com/coredao-org/core-chain
        cd "$CORE_CHAIN_DIR"
    fi

    check_status "Repository cloned/updated successfully!" "Failed to clone/update repository"
}

build_geth() {
    log_message "Building geth"
    show_progress "Building geth binary..."
    
    cd "$CORE_CHAIN_DIR"
    make geth

    check_status "Geth built successfully!" "Failed to build geth"
}

setup_node_directory() {
    log_message "Setting up node directory"
    show_progress "Setting up node directory..."
    
    mkdir -p "$NODE_DIR"

    # Download testnet files
    cd "$CORE_CHAIN_DIR"
    wget https://github.com/coredao-org/core-chain/releases/download/v1.0.14/testnet2.zip
    unzip -o testnet2.zip

    check_status "Node directory setup completed!" "Failed to setup node directory"
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
    cat > "$INSTALL_DIR/start-node.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")/core-chain"
./build/bin/geth --config ./testnet2/config.toml --datadir ./node --cache 8000 --rpc.allow-unprotected-txs --networkid 1114
EOF

    chmod +x "$INSTALL_DIR/start-node.sh"
    show_success "Startup script created at $INSTALL_DIR/start-node.sh"
}

setup_node() {
    # Main installation steps
    local steps=(
        "Installing Dependencies" "install_dependencies"
        "Cloning Repository" "clone_core_repository"
        "Building Geth" "build_geth"
        "Setting up Node Directory" "setup_node_directory"
        "Downloading Snapshot" "download_snapshot"
        "Initializing Genesis" "initialize_genesis"
        "Creating Startup Script" "create_startup_script"
    )

    local total_steps=$((${#steps[@]} / 2))
    local current_step=1

    for ((i = 0; i < ${#steps[@]}; i += 2)); do
        local step_name="${steps[i]}"
        local step_function="${steps[i+1]}"

        dialog --title "Core Node Setup ($current_step/$total_steps)" \
               --infobox "Step $current_step: $step_name" 5 70
        sleep 2

        if ! $step_function; then
            show_error "Failed at step: $step_name"
            return 1
        fi

        ((current_step++))
    done

    show_success "Core node setup completed successfully!\n\nTo start your node, run:\n$INSTALL_DIR/start-node.sh"
    return 0
}

# Run setup if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_dialog
    setup_node
fi
