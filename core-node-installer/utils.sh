#!/bin/bash

# Color Scheme
# Primary Colors
PRIMARY='\033[38;2;248;146;19m'     # #F89213 - Orange
SECONDARY='\033[38;2;247;116;2m'    # #F77402 - Deep Orange
BG='\033[48;2;254;239;219m'        # #FEEFDB - Light Orange Background
FG='\033[38;2;18;18;18m'           # #121212 - Almost Black
# Complementary Colors
BLUE='\033[38;2;0;48;73m'          # Dark Blue for contrast
GREEN='\033[38;2;0;100;0m'         # Dark Green for success
RED='\033[38;2;220;53;69m'         # Bootstrap Red for errors
YELLOW='\033[38;2;255;193;7m'      # Warning Yellow
WHITE='\033[38;2;255;255;255m'     # Pure White
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Function to create fancy headers
show_header() {
    local title="$1"
    local width=60
    local padding=$(( (width - ${#title}) / 2 ))
    echo -e "${PRIMARY}${BOLD}"
    printf '%*s' $width '' | tr ' ' '='
    echo -e "\n${WHITE}%*s${title}%*s${NC}" $padding '' $padding ''
    echo -e "${PRIMARY}${BOLD}"
    printf '%*s' $width '' | tr ' ' '='
    echo -e "${NC}\n"
}

# Display error message with new styling
show_error() {
    dialog --title "$(echo -e "${RED}${BOLD}Error${NC}")" \
           --colors \
           --msgbox "\n\Z1${BOLD}Error:${NC}\n\n\Z0$1" 10 60
}

# Display success message with new styling
show_success() {
    dialog --title "$(echo -e "${GREEN}${BOLD}Success${NC}")" \
           --colors \
           --msgbox "\n\Z2${BOLD}Success:${NC}\n\n\Z0$1" 10 60
}

# Display warning message with new styling
show_warning() {
    dialog --title "$(echo -e "${YELLOW}${BOLD}Warning${NC}")" \
           --colors \
           --msgbox "\n\Z3${BOLD}Warning:${NC}\n\n\Z0$1" 10 60
}

# Display info message with new styling
show_info() {
    dialog --title "$(echo -e "${BLUE}${BOLD}Information${NC}")" \
           --colors \
           --msgbox "\n\Z4${BOLD}Info:${NC}\n\n\Z0$1" 10 60
}

# Display progress with new styling
show_progress() {
    echo -e "${PRIMARY}${BOLD}[PROGRESS]${NC} ${WHITE}$1${NC}"
}

# Display status message with new styling
show_status() {
    local message="$1"
    local status="$2"
    case $status in
        "success")
            echo -e "${GREEN}${BOLD}[✓]${NC} ${WHITE}$message${NC}"
            ;;
        "error")
            echo -e "${RED}${BOLD}[✗]${NC} ${WHITE}$message${NC}"
            ;;
        "warning")
            echo -e "${YELLOW}${BOLD}[!]${NC} ${WHITE}$message${NC}"
            ;;
        "info")
            echo -e "${BLUE}${BOLD}[i]${NC} ${WHITE}$message${NC}"
            ;;
        *)
            echo -e "${PRIMARY}${BOLD}[*]${NC} ${WHITE}$message${NC}"
            ;;
    esac
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        show_error "This operation requires root privileges.\nPlease run with sudo."
        exit 1
    fi
}

# Function to check if a command was successful
check_status() {
    if [ $? -eq 0 ]; then
        show_success "$1"
    else
        show_error "$2"
        exit 1
    fi
}

# Function to get system information for macOS
get_system_info() {
    show_progress "Gathering system information..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        CPU_CORES=$(sysctl -n hw.ncpu)
        TOTAL_RAM=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 )) # Convert to GB
        FREE_DISK=$(df -h / | awk 'NR==2 {print $4}' | sed 's/[A-Za-z]//g')
    else
        CPU_CORES=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo "Unknown")
        TOTAL_RAM=$(free -g 2>/dev/null | awk '/^Mem:/{print $2}' || echo "Unknown")
        FREE_DISK=$(df -h / | awk 'NR==2 {print $4}' | sed 's/[A-Za-z]//g')
    fi
    INTERNET_SPEED=$(speedtest-cli --simple 2>/dev/null | awk '/Download:/{print $2}' || echo "Unknown")
}

# Function to create a backup of a file
backup_file() {
    if [ -f "$1" ]; then
        local backup_path="$1.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$1" "$backup_path"
        show_status "Backup created: $backup_path" "success"
    fi
}

# Function to log messages with new styling
log_message() {
    local level="$2"
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    case $level in
        "error")
            echo -e "[${timestamp}] ${RED}ERROR:${NC} $message" >> core_installer.log
            ;;
        "warning")
            echo -e "[${timestamp}] ${YELLOW}WARNING:${NC} $message" >> core_installer.log
            ;;
        "success")
            echo -e "[${timestamp}] ${GREEN}SUCCESS:${NC} $message" >> core_installer.log
            ;;
        *)
            echo -e "[${timestamp}] ${PRIMARY}INFO:${NC} $message" >> core_installer.log
            ;;
    esac
}

# Function to check internet connectivity with new styling
check_internet() {
    show_progress "Checking internet connectivity..."
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        show_error "No internet connection detected.\nPlease check your network connection and try again."
        exit 1
    fi
    show_status "Internet connection verified" "success"
}

# Function to display a countdown timer with new styling
countdown() {
    local seconds=$1
    local message="${2:-Waiting}"
    while [ $seconds -gt 0 ]; do
        echo -ne "${PRIMARY}${BOLD}[$message]${NC} ${WHITE}${seconds}s remaining...${NC}\r"
        sleep 1
        : $((seconds--))
    done
    echo -e "\n"
}

# Function to style dialog boxes
style_dialog() {
    export DIALOGRC="$SCRIPT_DIR/.dialogrc"
    cat > "$DIALOGRC" << 'EOF'
# Dialog color scheme
use_shadow = ON
use_colors = ON
screen_color = (BLACK,WHITE,ON)
dialog_color = (BLACK,WHITE,OFF)
title_color = (WHITE,BLACK,ON)
border_color = (BLACK,WHITE,ON)
shadow_color = (BLACK,BLACK,ON)
button_active_color = (WHITE,BLACK,ON)
button_inactive_color = (BLACK,WHITE,OFF)
button_key_active_color = (WHITE,BLACK,ON)
button_key_inactive_color = (RED,WHITE,OFF)
button_label_active_color = (WHITE,BLACK,ON)
button_label_inactive_color = (BLACK,WHITE,ON)
inputbox_color = (BLACK,WHITE,OFF)
inputbox_border_color = (BLACK,WHITE,ON)
searchbox_color = (BLACK,WHITE,OFF)
searchbox_title_color = (WHITE,BLACK,ON)
searchbox_border_color = (BLACK,WHITE,ON)
position_indicator_color = (BLACK,WHITE,ON)
menubox_color = (BLACK,WHITE,OFF)
menubox_border_color = (BLACK,WHITE,ON)
item_color = (BLACK,WHITE,OFF)
item_selected_color = (WHITE,BLACK,ON)
tag_color = (BLACK,WHITE,ON)
tag_selected_color = (WHITE,BLACK,ON)
tag_key_color = (BLACK,WHITE,OFF)
tag_key_selected_color = (WHITE,BLACK,ON)
check_color = (BLACK,WHITE,OFF)
check_selected_color = (WHITE,BLACK,ON)
uarrow_color = (BLACK,WHITE,ON)
darrow_color = (BLACK,WHITE,ON)
EOF
}

# Function to install required dependencies
install_dependencies() {
    local os_type=$(detect_os)
    local deps=("dialog" "curl" "wget" "speedtest-cli" "lz4")
    
    case $os_type in
        "macos")
            if ! command -v brew &>/dev/null; then
                echo "Installing Homebrew..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            fi
            for dep in "${deps[@]}"; do
                if ! command -v "$dep" &>/dev/null; then
                    echo "Installing $dep..."
                    brew install "$dep"
                fi
            done
            ;;
        "debian")
            sudo apt-get update
            sudo apt-get install -y "${deps[@]}"
            ;;
        "redhat")
            sudo yum install -y epel-release
            sudo yum install -y "${deps[@]}"
            ;;
        "arch")
            sudo pacman -Sy --noconfirm "${deps[@]}"
            ;;
    esac
}

# Function to format requirement status
format_requirement() {
    local name="$1"
    local required="$2"
    local actual="$3"
    local status="$4"
    
    if [ "$status" = "pass" ]; then
        echo -e "${GREEN}${BOLD}✓${NC} ${FG}${name}${NC}: ${PRIMARY}${actual}${NC} ${DIM}(Required: ${required})${NC}"
    else
        echo -e "${RED}${BOLD}✗${NC} ${FG}${name}${NC}: ${RED}${actual}${NC} ${DIM}(Required: ${required})${NC}"
    fi
}
