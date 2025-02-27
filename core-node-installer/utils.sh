#!/bin/bash

# Color Scheme
# Primary Color (Yellow)
PRIMARY='\033[38;2;255;223;0m'     # #FFDF00
# Complementary Colors
BLUE='\033[38;2;70;130;180m'      # Steel Blue
GREEN='\033[38;2;34;139;34m'      # Forest Green
RED='\033[38;2;220;20;60m'        # Crimson
YELLOW="$PRIMARY"                  # Same as primary
WHITE='\033[37m'                   # White
GRAY='\033[38;2;105;105;105m'     # Dim Gray
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

# Function to get system information
get_system_info() {
    show_progress "Gathering system information..."
    CPU_CORES=$(nproc)
    TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
    FREE_DISK=$(df -h / | awk 'NR==2 {print $4}' | sed 's/[A-Za-z]//g')
    INTERNET_SPEED=$(speedtest-cli --simple 2>/dev/null | awk '/Download:/{print $2}')
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
screen_color = (YELLOW,BLACK,ON)
dialog_color = (BLACK,YELLOW,OFF)
title_color = (BLACK,YELLOW,ON)
border_color = (BLACK,YELLOW,ON)
shadow_color = (BLACK,BLACK,ON)
button_active_color = (YELLOW,BLACK,ON)
button_inactive_color = (BLACK,YELLOW,OFF)
button_key_active_color = (YELLOW,BLACK,ON)
button_key_inactive_color = (RED,YELLOW,OFF)
button_label_active_color = (YELLOW,BLACK,ON)
button_label_inactive_color = (BLACK,YELLOW,ON)
inputbox_color = (BLACK,YELLOW,OFF)
inputbox_border_color = (BLACK,YELLOW,ON)
searchbox_color = (BLACK,YELLOW,OFF)
searchbox_title_color = (BLACK,YELLOW,ON)
searchbox_border_color = (BLACK,YELLOW,ON)
position_indicator_color = (BLACK,YELLOW,ON)
menubox_color = (BLACK,YELLOW,OFF)
menubox_border_color = (BLACK,YELLOW,ON)
item_color = (BLACK,YELLOW,OFF)
item_selected_color = (YELLOW,BLACK,ON)
tag_color = (BLACK,YELLOW,ON)
tag_selected_color = (YELLOW,BLACK,ON)
tag_key_color = (BLACK,YELLOW,OFF)
tag_key_selected_color = (YELLOW,BLACK,ON)
check_color = (BLACK,YELLOW,OFF)
check_selected_color = (YELLOW,BLACK,ON)
uarrow_color = (BLACK,YELLOW,ON)
darrow_color = (BLACK,YELLOW,ON)
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
