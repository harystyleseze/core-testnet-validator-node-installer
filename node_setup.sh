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
    
    # Write the raw entered password to temporary file for geth
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

# Function to verify account unlock
verify_account_unlock() {
    local address="$1"
    local password_file="$2"
    
    cd "$CORE_CHAIN_DIR"
    
    # Try to unlock account without starting the node
    local result=0
    if ! ./build/bin/geth --datadir "$NODE_DIR" account list --unlock "$address" --password "$password_file" &>/dev/null; then
        result=1
    fi
    
    return $result
}

# Function to read and verify encrypted password
read_encrypted_password() {
    local password_file="$1"
    local entered_password="$2"
    
    # Read the encrypted password from file
    local stored_hash
    stored_hash=$(cat "$password_file")
    
    # Create a temporary Python script for verification
    local temp_script=$(mktemp)
    chmod 700 "$temp_script"
    
    cat > "$temp_script" << 'EOF'
import bcrypt
import base64
import sys

try:
    password = sys.argv[1].encode('utf-8')
    stored_hash = base64.b64decode(sys.argv[2])
    if bcrypt.checkpw(password, stored_hash):
        sys.exit(0)
    sys.exit(1)
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
EOF

    # Verify the password
    if ! python3 "$temp_script" "$entered_password" "$stored_hash" 2>/dev/null; then
        rm -f "$temp_script"
        return 1
    fi
    
    rm -f "$temp_script"
    return 0
} 