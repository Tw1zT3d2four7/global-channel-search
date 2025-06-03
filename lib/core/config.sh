#!/bin/bash
# lib/core/config.sh - Configuration Management Module
# Handles all configuration file operations and state management

# ============================================================================
# CONFIGURATION FILE MANAGEMENT
# ============================================================================

setup_config() {
  if [ -f "$CONFIG_FILE" ]; then
    if source "$CONFIG_FILE" 2>/dev/null; then
      # Set defaults for any missing settings
      CHANNELS_URL=${CHANNELS_URL:-""}
      SHOW_LOGOS=${SHOW_LOGOS:-false}
      FILTER_BY_RESOLUTION=${FILTER_BY_RESOLUTION:-false}
      ENABLED_RESOLUTIONS=${ENABLED_RESOLUTIONS:-"SDTV,HDTV,UHDTV"}
      FILTER_BY_COUNTRY=${FILTER_BY_COUNTRY:-false}
      ENABLED_COUNTRIES=${ENABLED_COUNTRIES:-""}

      # Set defaults for Dispatcharr settings
      DISPATCHARR_URL=${DISPATCHARR_URL:-""}
      DISPATCHARR_USERNAME=${DISPATCHARR_USERNAME:-""}
      DISPATCHARR_PASSWORD=${DISPATCHARR_PASSWORD:-""}
      DISPATCHARR_ENABLED=${DISPATCHARR_ENABLED:-false}
      DISPATCHARR_REFRESH_INTERVAL=${DISPATCHARR_REFRESH_INTERVAL:-25}
      
      # Resume state - ONLY channel number now
      LAST_PROCESSED_CHANNEL_NUMBER=${LAST_PROCESSED_CHANNEL_NUMBER:-""}
      
      return 0
    else
      echo -e "${RED}Error: Cannot source config file${RESET}"
      rm "$CONFIG_FILE"
      echo -e "${YELLOW}Corrupted config removed. Let's set it up again.${RESET}"
    fi
  fi

  # Config file doesn't exist or was corrupted - create minimal config
  create_minimal_config
}

create_minimal_config() {
  echo -e "${YELLOW}Setting up configuration...${RESET}"
  echo -e "${CYAN}💡 Channels DVR server is optional and only needed for:${RESET}"
  echo -e "${CYAN}   • Direct API search${RESET}"
  echo -e "${CYAN}   • User Cache Expansion${RESET}"
  echo -e "${GREEN}   • Local Database Search works out of the box with base database!${RESET}"
  echo
  
  if confirm_action "Configure Channels DVR server now? (can be done later in Settings)"; then
    if configure_channels_server; then
      # Reload config to get the newly saved CHANNELS_URL
      source "$CONFIG_FILE" 2>/dev/null
      echo -e "${GREEN}✅ Server configured successfully!${RESET}"
    else
      echo -e "${YELLOW}Server configuration skipped${RESET}"
      CHANNELS_URL=""
    fi
  else
    echo -e "${GREEN}Skipping server configuration - you can add it later in Settings${RESET}"
    CHANNELS_URL=""
  fi
  
  # Write minimal config file
  {
    echo "CHANNELS_URL=\"${CHANNELS_URL:-}\""
    echo "SHOW_LOGOS=false"
    echo "FILTER_BY_RESOLUTION=false"
    echo "ENABLED_RESOLUTIONS=\"SDTV,HDTV,UHDTV\""
    echo "FILTER_BY_COUNTRY=false"
    echo "ENABLED_COUNTRIES=\"\""
    echo "# Dispatcharr Settings"
    echo "DISPATCHARR_URL=\"\""
    echo "DISPATCHARR_USERNAME=\"\""
    echo "DISPATCHARR_PASSWORD=\"\""
    echo "DISPATCHARR_ENABLED=false"
    echo "DISPATCHARR_REFRESH_INTERVAL=25"
    echo "# Resume State for Field Population - Channel Number Only"
    echo "LAST_PROCESSED_CHANNEL_NUMBER=\"\""
  } > "$CONFIG_FILE" || {
    echo -e "${RED}Error: Cannot write to config file${RESET}"
    exit 1
  }
  
  source "$CONFIG_FILE"
  echo -e "${GREEN}✅ Configuration saved successfully!${RESET}"
  echo
  echo -e "${BOLD}${CYAN}Ready to Use:${RESET}"
  echo -e "${GREEN}✅ Local Database Search - Works out of the box with base database${RESET}"
  echo -e "${CYAN}💡 Optional: Add custom markets via 'Manage Television Markets'${RESET}"
}

configure_channels_server() {
  local ip port
  
  clear
  echo -e "${BOLD}${CYAN}=== Channels DVR Server Configuration ===${RESET}\n"
  echo -e "${BLUE}📍 Configure Connection to Channels DVR Server${RESET}"
  echo -e "${YELLOW}This server provides TV lineup data and station information for searches and caching.${RESET}"
  echo
  
  echo -e "${BOLD}${BLUE}Server Connection Guidelines:${RESET}"
  echo -e "${GREEN}• Local installation:${RESET} Use 'localhost' or '127.0.0.1'"
  echo -e "${GREEN}• Remote server:${RESET} Use the server's IP address on your network"
  echo -e "${GREEN}• Default port:${RESET} Usually 8089 unless you changed it"
  echo -e "${CYAN}💡 The server must be running and accessible from this machine${RESET}"
  echo
  
  while true; do
    echo -e "${BOLD}Step 1: Server IP Address${RESET}"
    read -p "Enter Channels DVR IP address [default: localhost]: " ip < /dev/tty
    ip=${ip:-localhost}
    
    # Validate IP format
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || [[ "$ip" == "localhost" ]]; then
      echo -e "${GREEN}✅ IP address accepted: $ip${RESET}"
      break
    else
      echo -e "${RED}❌ Invalid IP address format${RESET}"
      echo -e "${CYAN}💡 Use format like: 192.168.1.100 or 'localhost'${RESET}"
      echo
    fi
  done
  
  echo
  
  while true; do
    echo -e "${BOLD}Step 2: Server Port${RESET}"
    read -p "Enter Channels DVR port [default: 8089]: " port < /dev/tty
    port=${port:-8089}
    
    # Validate port number
    if [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )); then
      echo -e "${GREEN}✅ Port accepted: $port${RESET}"
      break
    else
      echo -e "${RED}❌ Invalid port number${RESET}"
      echo -e "${CYAN}💡 Port must be a number between 1 and 65535${RESET}"
      echo
    fi
  done
  
  CHANNELS_URL="http://$ip:$port"
  
  echo
  echo -e "${BOLD}Step 3: Connection Test${RESET}"
  echo -e "${CYAN}🔗 Testing connection to $CHANNELS_URL...${RESET}"
  
  if curl -s --connect-timeout 5 "$CHANNELS_URL" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Connection successful!${RESET}"
    echo -e "${CYAN}💡 Server is responding and ready for use${RESET}"
    
    # Save the configured URL to config file
    save_setting "CHANNELS_URL" "$CHANNELS_URL"
    return 0
  else
    echo -e "${RED}❌ Connection test failed${RESET}"
    echo -e "${CYAN}💡 This could be normal if the server is currently offline${RESET}"
    echo -e "${CYAN}💡 Common issues: Server not running, wrong IP/port, firewall blocking${RESET}"
    echo
    
    echo -e "${BOLD}${YELLOW}Connection Failed - What would you like to do?${RESET}"
    echo -e "${GREEN}1)${RESET} Save settings anyway (connection will be tested when needed)"
    echo -e "${GREEN}2)${RESET} Try different IP/port settings"
    echo -e "${GREEN}3)${RESET} Cancel configuration"
    echo
    
    read -p "Select option: " choice < /dev/tty
    
    case $choice in
      1)
        echo -e "${YELLOW}⚠️  Settings saved with failed connection test${RESET}"
        echo -e "${CYAN}💡 Connection will be tested again when features are used${RESET}"
        
        # Save the configured URL to config file
        save_setting "CHANNELS_URL" "$CHANNELS_URL"
        return 0
        ;;
      2)
        echo -e "${CYAN}🔄 Restarting server configuration...${RESET}"
        echo
        configure_channels_server  # Recursive call to restart
        return $?
        ;;
      3|"")
        echo -e "${YELLOW}⚠️  Server configuration cancelled${RESET}"
        CHANNELS_URL=""
        return 1
        ;;
      *)
        echo -e "${RED}❌ Invalid option${RESET}"
        sleep 1
        # Default to cancelling
        CHANNELS_URL=""
        return 1
        ;;
    esac
  fi
}

# ============================================================================
# CACHE STATE MANAGEMENT
# ============================================================================

save_combined_cache_state() {
  local combined_timestamp="$1"
  local base_timestamp="$2"
  local user_timestamp="$3"
  
  # Update or add cache state to config file
  local temp_config="${CONFIG_FILE}.tmp"
  
  # Remove existing cache state lines
  grep -v -E '^COMBINED_CACHE_TIMESTAMP=|^COMBINED_CACHE_BASE_TIME=|^COMBINED_CACHE_USER_TIME=' "$CONFIG_FILE" > "$temp_config" 2>/dev/null || touch "$temp_config"
  
  # Add new cache state
  {
    echo "COMBINED_CACHE_TIMESTAMP=$combined_timestamp"
    echo "COMBINED_CACHE_BASE_TIME=$base_timestamp"
    echo "COMBINED_CACHE_USER_TIME=$user_timestamp"
  } >> "$temp_config"
  
  # Replace config file
  mv "$temp_config" "$CONFIG_FILE"
}

load_combined_cache_state() {
  if [ -f "$CONFIG_FILE" ]; then
    # Source the config to get cache timestamps
    local saved_combined_time=$(grep '^COMBINED_CACHE_TIMESTAMP=' "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
    local saved_base_time=$(grep '^COMBINED_CACHE_BASE_TIME=' "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
    local saved_user_time=$(grep '^COMBINED_CACHE_USER_TIME=' "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
    
    # Return the values (caller can capture them)
    echo "$saved_combined_time|$saved_base_time|$saved_user_time"
  else
    echo "0|0|0"
  fi
}

# ============================================================================
# RESUME STATE MANAGEMENT
# ============================================================================

save_resume_state() {
  local channel_number="$1"
  
  # Update the in-memory variable
  LAST_PROCESSED_CHANNEL_NUMBER="$channel_number"
  
  # Update config file more robustly
  local temp_config="${CONFIG_FILE}.tmp"
  if [ -f "$CONFIG_FILE" ]; then
    # Remove existing line and add new one
    grep -v "^LAST_PROCESSED_CHANNEL_NUMBER=" "$CONFIG_FILE" > "$temp_config" 2>/dev/null || true
    echo "LAST_PROCESSED_CHANNEL_NUMBER=\"$channel_number\"" >> "$temp_config"
    
    # Replace original file
    if mv "$temp_config" "$CONFIG_FILE"; then
      echo -e "${CYAN}💾 Resume state saved: Channel #$channel_number${RESET}" >&2
    else
      echo -e "${RED}❌ Failed to save resume state${RESET}" >&2
      rm -f "$temp_config" 2>/dev/null
    fi
  else
    echo -e "${RED}❌ Config file not found, cannot save resume state${RESET}" >&2
  fi
}

clear_resume_state() {
  # Clear in-memory variable
  LAST_PROCESSED_CHANNEL_NUMBER=""
  
  # Clear in config file
  sed -i "s/LAST_PROCESSED_CHANNEL_NUMBER=.*/LAST_PROCESSED_CHANNEL_NUMBER=\"\"/" "$CONFIG_FILE"
  
  echo -e "${CYAN}💾 Resume state cleared${RESET}" >&2
}

# ============================================================================
# SETTINGS DISPLAY
# ============================================================================

display_current_settings() {
  echo -e "${BOLD}${BLUE}=== Current Configuration ===${RESET}"
  echo
  
  # STANDARDIZED: Channels DVR Server Status
  echo -e "${BOLD}${YELLOW}Channels DVR Integration:${RESET}"
  if [[ -n "${CHANNELS_URL:-}" ]]; then
    if curl -s --connect-timeout 2 "$CHANNELS_URL" >/dev/null 2>&1; then
      echo -e "${GREEN}✅ Server: Connected${RESET}"
      echo -e "   ${CYAN}🌐 URL: $CHANNELS_URL${RESET}"
      echo -e "   ${CYAN}📡 Status: Online and responding${RESET}"
    else
      echo -e "${RED}❌ Server: Connection Failed${RESET}"
      echo -e "   ${CYAN}🌐 URL: $CHANNELS_URL${RESET}"
      echo -e "   ${YELLOW}📡 Status: Cannot reach server${RESET}"
    fi
  else
    echo -e "${YELLOW}⚠️  Server: Not configured${RESET}"
    echo -e "   ${CYAN}💡 Configure via 'Change Channels DVR Server'${RESET}"
  fi
  echo
  
  # STANDARDIZED: Search Settings
  echo -e "${BOLD}${YELLOW}Search Configuration:${RESET}"
  
  # Logo Display
  if command -v viu >/dev/null 2>&1; then
    if [[ "$SHOW_LOGOS" == "true" ]]; then
      echo -e "${GREEN}✅ Logo Display: Enabled${RESET}"
      echo -e "   ${CYAN}🖼️  Station logos will appear in search results${RESET}"
    else
      echo -e "${YELLOW}⚠️  Logo Display: Disabled${RESET}"
      echo -e "   ${CYAN}💡 Enable to see visual station logos${RESET}"
    fi
  else
    echo -e "${RED}❌ Logo Display: Unavailable (viu not installed)${RESET}"
    echo -e "   ${CYAN}💡 Install viu: cargo install viu${RESET}"
  fi
  
  # Resolution Filter
  if [[ "$FILTER_BY_RESOLUTION" == "true" ]]; then
    echo -e "${GREEN}✅ Resolution Filter: Active${RESET}"
    echo -e "   ${CYAN}📺 Showing only: ${YELLOW}$ENABLED_RESOLUTIONS${RESET}"
    echo -e "   ${CYAN}💡 Search results filtered by video quality${RESET}"
  else
    echo -e "${YELLOW}⚠️  Resolution Filter: Disabled${RESET}"
    echo -e "   ${CYAN}💡 Showing all quality levels (SDTV, HDTV, UHDTV)${RESET}"
  fi
  
  # Country Filter
  if [[ "$FILTER_BY_COUNTRY" == "true" ]]; then
    echo -e "${GREEN}✅ Country Filter: Active${RESET}"
    echo -e "   ${CYAN}🌍 Showing only: ${YELLOW}$ENABLED_COUNTRIES${RESET}"
    echo -e "   ${CYAN}💡 Search results filtered by country${RESET}"
  else
    echo -e "${YELLOW}⚠️  Country Filter: Disabled${RESET}"
    echo -e "   ${CYAN}💡 Showing stations from all available countries${RESET}"
  fi
  echo
  
  # STANDARDIZED: Dispatcharr Integration Status
  echo -e "${BOLD}${YELLOW}Dispatcharr Integration:${RESET}"
  if [[ "$DISPATCHARR_ENABLED" == "true" ]]; then
    if [[ -n "${DISPATCHARR_URL:-}" ]]; then
      # Test Dispatcharr connection
      local token_file="$CACHE_DIR/dispatcharr_tokens.json"
      local has_tokens=false
      if [[ -f "$token_file" ]]; then
        local access_token=$(jq -r '.access // empty' "$token_file" 2>/dev/null)
        if [[ -n "$access_token" && "$access_token" != "null" ]]; then
          has_tokens=true
        fi
      fi
      
      if [[ "$has_tokens" == "true" ]]; then
        echo -e "${GREEN}✅ Dispatcharr: Connected and authenticated${RESET}"
        echo -e "   ${CYAN}🌐 URL: $DISPATCHARR_URL${RESET}"
        echo -e "   ${CYAN}👤 User: ${DISPATCHARR_USERNAME:-"Not configured"}${RESET}"
        echo -e "   ${CYAN}🔑 Tokens: Valid and cached${RESET}"
        echo -e "   ${CYAN}🔄 Refresh Interval: Every $DISPATCHARR_REFRESH_INTERVAL interactions${RESET}"
      else
        echo -e "${YELLOW}⚠️  Dispatcharr: Configured but not authenticated${RESET}"
        echo -e "   ${CYAN}🌐 URL: $DISPATCHARR_URL${RESET}"
        echo -e "   ${YELLOW}🔑 Tokens: Missing or expired${RESET}"
        echo -e "   ${CYAN}💡 Reconfigure via 'Configure Dispatcharr Integration'${RESET}"
      fi
    else
      echo -e "${YELLOW}⚠️  Dispatcharr: Enabled but no URL configured${RESET}"
      echo -e "   ${CYAN}💡 Configure URL via 'Configure Dispatcharr Integration'${RESET}"
    fi
  else
    echo -e "${RED}❌ Dispatcharr: Disabled${RESET}"
    echo -e "   ${CYAN}💡 Enable via 'Configure Dispatcharr Integration'${RESET}"
  fi
  echo
}