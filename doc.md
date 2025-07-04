# Core Testnet Validator Node Installer - Technical Documentation

## Overview

The Core Testnet Validator Node Installer is a comprehensive Terminal User Interface (TUI) application designed to simplify the setup, configuration, and management of Core blockchain testnet validator nodes. It provides an automated, user-friendly solution for blockchain enthusiasts and validators to run Core testnet nodes without complex manual configuration.

## Project Structure

### Main Directory Structure
```

core-testnet-validator-node-installer/
├── README.md                          # Main project documentation and features
├── Guide.md                           # Step-by-step setup guide for Ubuntu/Linux
├── steps.md                           # Alternative setup instructions
├── hardwareRequirement.md             # Hardware specifications table
├── doc.md                             # This technical documentation
├── core-node-installer/               # Main installer application
│   ├── install.sh                     # Main TUI installer script
│   ├── hardware\_check.sh              # System requirements verification
│   ├── node\_setup.sh                  # Core node installation and setup
│   ├── log\_monitor.sh                 # Real-time log monitoring system
│   ├── utils.sh                       # Utility functions and styling
│   ├── config.toml                    # Core node configuration file
│   ├── genesis.json                   # Blockchain genesis configuration
│   ├── manual-setup.md                # Manual installation instructions
│   └── setupManual.md                 # Additional manual setup guide
└── asset/                             # UI screenshots and documentation images
├── homepage.png
├── mainmenu.png
├── adminMenu.png
├── feature.png
├── systemRequirement.png
└── systemRequirementsCheck.png

````

## Core Components and Features

### 1. Main Entry Point (`install.sh`)

The primary entry point that orchestrates the entire installation and management process.

**Key Functions:**
- `show_welcome_screen()` - Displays welcome interface  
- `verify_requirements()` - Initiates hardware verification  
- `show_main_menu()` - Main navigation hub with 9 options:  
  1. Check Hardware Requirements  
  2. Install/Upgrade Core Node  
  3. Node Management  
  4. Generate Consensus Key  
  5. View Consensus Key  
  6. View Logs  
  7. View Node Status  
  8. Admin Dashboard  
  9. Exit  

**Error Handling:**
- Comprehensive trap-based error handling with detailed logging  
- Function trace capability for debugging  
- Graceful error recovery with user-friendly messages  

**Installation Process Flow:**
1. Dialog dependency verification and installation  
2. OS detection (macOS, Debian, RedHat, Arch)  
3. Package manager auto-detection  
4. Required tools installation (dialog, curl, wget, speedtest-cli, lz4)  

### 2. Hardware Requirements Verification (`hardware_check.sh`)

Automated system compatibility checker that validates minimum requirements.

**System Requirements Checked:**
- **CPU**: Minimum 4 cores  
- **RAM**: Minimum 8 GB  
- **Storage**: Minimum 1 TB free space  
- **Internet**: Minimum 10 Mbps download speed  
- **Network Speed Test**: Uses speedtest-cli for real-time verification  

**Key Functions:**
- `get_system_info()` - Cross-platform system information gathering  
- `check_hardware_requirements()` - Comprehensive validation with color-coded results  
- Real-time status display with ✅/❌ indicators  
- Detailed requirement vs. actual comparison  

**Platform Support:**
- macOS (Darwin) using `sysctl` commands  
- Linux distributions using standard utilities  
- Automatic tool installation based on OS  

### 3. Node Setup and Management (`node_setup.sh`)

The core installation engine that handles the complete node setup process.

**Major Installation Steps:**
1. **Dependency Installation** (`install_dependencies()`)  
2. **Repository Management** (`clone_core_repository()`)  
3. **Binary Building** (`build_geth()`)  
4. **Node Directory Setup** (`setup_node_directory()`)  

**Advanced Features:**

**Blockchain Snapshot Management:**
- Robust download with retry mechanism  
- Progress tracking  
- Resume capability  
- MD5 checksum verification  

**Consensus Key Generation:**
- Secure validator key creation  
- Password strength validation  
- Secure keystore file management  
- Validator address extraction  

**Node Process Management:**
- Start/stop node (standard or validator mode)  
- Process status check  
- Real-time resource monitoring  

**Database Recovery System:**
- Chain gap detection  
- Reset and snapshot-based recovery  
- Data integrity verification  

### 4. Log Monitoring System (`log_monitor.sh`)

Real-time log analysis and monitoring dashboard.

**Core Features:**
- Real-time log tailing  
- Statistical analysis  
- Interactive search  
- Comprehensive dashboard  

**Log Management:**
- Export with timestamps  
- Log rotation  
- Clear with backup  
- Color-coded levels (ERROR, WARN, INFO)  

**Supported Log Types:**
- Core Node Logs (`$NODE_DIR/logs/core.log`)  
- Installation Logs (`core_installer.log`)  

### 5. Utility Functions (`utils.sh`)

Comprehensive utility library providing styling, system functions, and helpers.

**Styling System:**
- Color scheme  
- Status indicators with emoji  
- Dialog theming  
- Progress indicators  

**System Functions:**
- System info gathering  
- Internet connectivity check  
- File backup/restore  
- Logging with severity levels  

**Helper Functions:**
- `format_requirement()`  
- `backup_file()`  
- `countdown()`  
- `style_dialog()`  

### 6. Configuration Management

**Core Node Configuration (`config.toml`):**
```toml
[Eth]
NetworkId = 1114
LightPeers = 100
TrieTimeout = 100000000000

[Eth.Miner]
GasFloor = 30000000
GasCeil = 50000000
GasPrice = 1000000000

[Node.P2P]
MaxPeers = 30
BootstrapNodes = [...]
StaticNodes = [...]
````

**Genesis Block Configuration (`genesis.json`):**

* Chain ID: 1114
* Consensus: Satoshi (Proof of Stake variant)
* Pre-allocated accounts
* Hard fork configs: Homestead, Berlin, London, Shanghai, etc.

## Technical Implementation Details

### Security Features

**Password Security:**

* Bcrypt encryption
* Secure file permissions (600)
* No plaintext storage

**Process Security:**

* Privilege separation
* Secure keystore handling

**Network Security:**

* Predefined bootstrap/static nodes
* Connection limits

### Error Handling and Recovery

**Multi-level Handling:**

1. Script Level
2. Function Level
3. User Level
4. System Level

**Recovery Mechanisms:**

* Retry with backoff
* Snapshot-based restore
* Process cleanup
* Config validation

### Performance Optimizations

**Download Management:**

* Parallel downloads
* Resume support
* Bandwidth optimization

**Resource Management:**

* Configurable cache
* Memory and CPU monitoring
* Disk validation

### Node Operation Modes

* **Standard Node**: Sync, relay
* **Validator Mode**: Block production, staking
* **Snapshot Sync Mode**: Fast sync

## Administrative Features

### Admin Dashboard

1. **System Maintenance**
2. **System Monitoring**
3. **Repair and Recovery**

## Installation Workflows

### Automated Installation Flow

1. Welcome
2. Hardware Check
3. Dependencies
4. Clone repo
5. Install Go/build
6. Setup directory
7. Deploy configs
8. Optional snapshot
9. Init genesis
10. Start node

### Manual Installation Support

* Step-by-step commands
* Alternative methods
* Systemd configs
* Binary installation

## Logging and Monitoring

### Log Structure

* Timestamps
* Error tracking
* Performance logs
* Audit trail

### Monitoring Capabilities

* Process and resource monitoring
* Sync status
* Block stats

## Network Configuration

### Core Testnet Specifics

* Chain ID / Network ID: 1114
* Bootstrap / Static nodes
* Default Ports:

  * P2P: 35012
  * HTTP RPC: 8575
  * WebSocket: 8576

### Connectivity

* Peer discovery
* NAT traversal
* Configurable limits

## Troubleshooting and Maintenance

### Common Issues

1. Download issues
2. DB corruption
3. Process conflicts
4. Permissions
5. Network

### Maintenance Operations

* Log rotation
* Backup/restore
* Monitoring
* Patches

## Future Enhancement Areas

### Planned Features

* Mainnet support
* Update automation
* Backup & disaster recovery
* Analytics

### Extensibility

* Modular architecture
* Plugin system
* API integration

## Conclusion

The Core Testnet Validator Node Installer is a robust, automated, and user-friendly TUI application for managing validator nodes. With strong security, modular design, and advanced error handling, it's ideal for both beginners and pros.
