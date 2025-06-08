#!/bin/bash
# lib/core/utils.sh - Core Utility Functions
# Safe utility functions with no external dependencies

# ============================================================================
# USER INTERACTION UTILITIES
# ============================================================================

pause_for_user() {
  read -p "Press Enter to continue..."
}

show_invalid_choice() {
  echo -e "${RED}❌ Invalid Option: Please select a valid option from the menu${RESET}"
  echo -e "${CYAN}💡 Check the available choices and try again${RESET}"
  sleep 2
}

confirm_action() {
  local message="$1"
  local default="${2:-n}"
  
  echo -e "${BOLD}${YELLOW}Confirmation Required:${RESET}"
  read -p "$message (y/n) [default: $default]: " response < /dev/tty
  response=${response:-$default}
  [[ "$response" =~ ^[Yy]$ ]]
}

# ============================================================================
# PROGRESS AND DISPLAY UTILITIES
# ============================================================================

show_progress_bar() {
  local current="$1"
  local total="$2"
  local percent="$3"
  local start_time="$4"  # Keep parameter for compatibility but don't use for ETA
  
  # Create simple progress bar with Unicode blocks
  local bar_width=20
  local filled=$((percent * bar_width / 100))
  local bar=""
  local i=0
  
  # Build progress bar
  while (( i < filled )); do
    bar+="█"
    ((i++))
  done
  while (( i < bar_width )); do
    bar+="░"
    ((i++))
  done

  # Show progress WITHOUT ETA - clean and simple
  printf "\r%3d%% [%s] %d/%d" "$percent" "$bar" "$current" "$total" >&2
  
  # Only add newline when completely finished
  if (( current == total )); then
    echo >&2
  fi
}

# ============================================================================
# UNIVERSAL CONFIGURATION SAVING
# ============================================================================

save_setting() {
    local setting_name="$1"
    local setting_value="$2"
    local config_file="${3:-$CONFIG_FILE}"
    
    # Create temp file
    local temp_config="${config_file}.tmp"
    
    # Remove existing setting
    grep -v "^${setting_name}=" "$config_file" > "$temp_config" 2>/dev/null || touch "$temp_config"
    
    # Add new setting
    echo "${setting_name}=\"${setting_value}\"" >> "$temp_config"
    
    # Atomic update
    if mv "$temp_config" "$config_file"; then
        return 0
    else
        rm -f "$temp_config" 2>/dev/null
        return 1
    fi
}

# Universal input validation
validate_input() {
    local validation_type="$1"
    local input="$2"
    shift 2
    local constraints=("$@")
    
    case "$validation_type" in
        "ip_address")
            _validate_ip_address "$input"
            ;;
        "port")
            _validate_port "$input" "${constraints[0]:-1}" "${constraints[1]:-65535}"
            ;;
        "numeric_range")
            _validate_numeric_range "$input" "${constraints[0]}" "${constraints[1]}"
            ;;
        "choice_list")
            _validate_choice_list "$input" "${constraints[@]}"
            ;;
        "multi_choice_list")
            _validate_multi_choice_list "$input" "${constraints[@]}"
            ;;
        "non_empty")
            _validate_non_empty "$input"
            ;;
    esac
}

# Universal connection testing
test_connection() {
    local connection_type="$1"
    local target="$2"
    local timeout="${3:-5}"
    
    case "$connection_type" in
        "http")
            curl -s --connect-timeout "$timeout" "$target" >/dev/null 2>&1
            ;;
        "api_endpoint")
            curl -s --connect-timeout "$timeout" "$target/api" >/dev/null 2>&1 || \
            curl -s --connect-timeout "$timeout" "$target" >/dev/null 2>&1
            ;;
        "dispatcharr")
            test_dispatcharr_connection "$target" "$timeout"
            ;;
    esac
}

# Universal setting status display
show_setting_status() {
    local setting_name="$1"
    local setting_value="$2"
    local setting_description="$3"
    local status_type="${4:-info}"
    
    echo -e "${BOLD}${BLUE}$setting_description:${RESET}"
    
    case "$status_type" in
        "enabled")
            echo -e "Status: ${GREEN}Enabled${RESET}"
            echo -e "Value: ${YELLOW}$setting_value${RESET}"
            ;;
        "disabled")
            echo -e "Status: ${YELLOW}Disabled${RESET}"
            ;;
        "configured")
            echo -e "Status: ${GREEN}Configured${RESET}"
            echo -e "Value: ${CYAN}$setting_value${RESET}"
            ;;
        "not_configured")
            echo -e "Status: ${RED}Not Configured${RESET}"
            ;;
        *)
            echo -e "Current: ${CYAN}$setting_value${RESET}"
            ;;
    esac
}