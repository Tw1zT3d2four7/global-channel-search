#!/bin/bash

# === Menu Framework ===
# Universal menu system eliminating menu pattern duplication

# ============================================================================
# UNIVERSAL MENU SYSTEM
# ============================================================================

# Universal menu display with template support
show_menu() {
    local menu_config="$1"
    
    # Parse menu configuration (format: "title|status_type|options_array_name")
    IFS='|' read -r title status_type options_var <<< "$menu_config"
    
    clear
    show_menu_header "$title"
    
    # Show status section if specified
    case "$status_type" in
        "system")
            show_unified_system_status
            ;;
        "cache") 
            _show_cache_menu_status
            ;;
        "dispatcharr")
            _show_dispatcharr_menu_status
            ;;
        "markets")
            _show_markets_menu_status
            ;;
        "settings")
            _show_settings_menu_status
            ;;
        "none")
            # No status section
            ;;
    esac
    
    # Show menu options
    local -n options_array=$options_var
    show_menu_options "${options_array[@]}"
    echo
}

# Universal menu header formatter
show_menu_header() {
    local title="$1"
    local subtitle="$2"
    
    echo -e "${BOLD}${CYAN}=== $title ===${RESET}\n"
    
    if [[ -n "$subtitle" ]]; then
        echo -e "${BLUE}📍 $subtitle${RESET}"
        echo
    fi
}

# Universal menu options display
show_menu_options() {
    local options=("$@")
    
    echo -e "${BOLD}${CYAN}Menu Options:${RESET}"
    
    for option in "${options[@]}"; do
        # Parse option format: "key|label|description"
        IFS='|' read -r key label description <<< "$option"
        
        if [[ -n "$description" ]]; then
            echo -e "${GREEN}$key)${RESET} $label ${CYAN}($description)${RESET}"
        else
            echo -e "${GREEN}$key)${RESET} $label"
        fi
    done
}

# Universal menu input handling
handle_menu_input() {
    local menu_name="$1"
    local choice="$2"
    shift 2
    local valid_choices=("$@")
    
    # Validate choice
    for valid_choice in "${valid_choices[@]}"; do
        if [[ "$choice" == "$valid_choice" ]]; then
            return 0  # Valid choice
        fi
    done
    
    # Invalid choice handling
    show_invalid_menu_choice "$menu_name" "$choice"
    return 1
}

# Universal invalid choice display
show_invalid_menu_choice() {
    local menu_name="$1"
    local invalid_choice="$2"
    
    echo -e "${RED}❌ Invalid Option: '$invalid_choice'${RESET}"
    echo -e "${CYAN}💡 Please select a valid option from the $menu_name menu${RESET}"
    sleep 2
}

# Universal menu transition messages
show_menu_transition() {
    local transition_type="$1"
    local target="$2"
    
    case "$transition_type" in
        "opening")
            echo -e "${CYAN}🔄 Opening $target...${RESET}"
            ;;
        "returning")
            echo -e "${CYAN}🔄 Returning to $target...${RESET}"
            ;;
        "starting")
            echo -e "${CYAN}🔄 Starting $target...${RESET}"
            ;;
        "loading")
            echo -e "${CYAN}📊 Loading $target...${RESET}"
            ;;
    esac
    
    [[ "$transition_type" != "returning" ]] && sleep 1
}

# ============================================================================
# MENU STATUS TEMPLATES
# ============================================================================

# Cache management menu status
_show_cache_menu_status() {
    local breakdown=$(get_stations_breakdown)
    local base_count=$(echo "$breakdown" | cut -d' ' -f1)
    local user_count=$(echo "$breakdown" | cut -d' ' -f2)
    local total_count=$(get_total_stations_count)
    
    echo -e "${BOLD}${BLUE}=== Current Cache Status ===${RESET}"
    
    # Base cache status
    if [ "$base_count" -gt 0 ]; then
        format_status_indicator "success" "Base Station Database: $base_count stations" "distributed cache"
    else
        format_status_indicator "error" "Base Station Database: Not found" "expected in script directory"
    fi
    
    # User cache status
    if [ "$user_count" -gt 0 ]; then
        format_status_indicator "success" "User Station Database: $user_count stations" "your additions"
        local user_size=$(ls -lh "$USER_STATIONS_JSON" 2>/dev/null | awk '{print $5}')
        [[ -n "$user_size" ]] && echo -e "   ${CYAN}📊 Size: $user_size${RESET}"
    else
        format_status_indicator "warning" "User Station Database: Empty" "build via Market Management"
    fi
    
    echo -e "${CYAN}📊 Total Available Stations: ${BOLD}$total_count${RESET}"
    
    # Search capability
    if [ "$total_count" -gt 0 ]; then
        format_status_indicator "success" "Local Database Search: Fully operational"
    else
        format_status_indicator "error" "Local Database Search: No station data available"
    fi
    echo
    
    # Processing state
    _show_processing_state_summary
}

# Dispatcharr menu status
_show_dispatcharr_menu_status() {
    echo -e "${BOLD}${BLUE}=== Connection Status ===${RESET}"
    
    if [[ "$DISPATCHARR_ENABLED" == "true" ]]; then
        if dispatcharr_test_connection; then
            format_status_indicator "success" "Dispatcharr Integration: Active and Connected"
            echo -e "   ${CYAN}🌐 Server: $DISPATCHARR_URL${RESET}"
            echo -e "   ${CYAN}👤 User: ${DISPATCHARR_USERNAME:-"Not configured"}${RESET}"
            _show_token_status
        else
            format_status_indicator "error" "Dispatcharr Integration: Connection Failed"
            echo -e "   ${CYAN}🌐 Configured Server: $DISPATCHARR_URL${RESET}"
        fi
    else
        format_status_indicator "warning" "Dispatcharr Integration: Disabled"
    fi
    echo
    
    # Pending operations
    echo -e "${BOLD}${BLUE}=== Pending Operations ===${RESET}"
    if [[ -f "$DISPATCHARR_MATCHES" ]] && [[ -s "$DISPATCHARR_MATCHES" ]]; then
        local pending_count=$(wc -l < "$DISPATCHARR_MATCHES")
        echo -e "${YELLOW}📋 Pending Station ID Changes: $pending_count matches queued${RESET}"
    else
        format_status_indicator "success" "Pending Operations: No pending changes"
    fi
    echo
    
    # Database compatibility
    echo -e "${BOLD}${BLUE}=== Database Compatibility ===${RESET}"
    local total_count=$(get_total_stations_count)
    if [ "$total_count" -gt 0 ]; then
        format_status_indicator "success" "Local Station Database: $total_count stations available" "fully compatible"
    else
        format_status_indicator "error" "Local Station Database: No station data available" "limited functionality"
    fi
}

# Emby menu status
_show_emby_menu_status() {
    echo -e "${BOLD}${BLUE}=== Emby Integration Status ===${RESET}"
    
    if [[ "$EMBY_ENABLED" == "true" ]]; then
        if [[ -n "${EMBY_URL:-}" ]]; then
            local auth_status
            auth_status=$(get_emby_auth_status)
            local status_code=$?
            
            echo -e "${GREEN}✅ Emby Integration: Enabled${RESET}"
            echo -e "${CYAN}   📍 Server: $EMBY_URL${RESET}"
            echo -e "${CYAN}   🔐 Authentication: $auth_status${RESET}"
            
            if [[ $status_code -eq 0 ]]; then
                # Try to get server info for additional details
                local server_info
                server_info=$(emby_get_server_info 2>/dev/null)
                if [[ $? -eq 0 ]]; then
                    local server_name=$(echo "$server_info" | jq -r '.ServerName // "Unknown"' 2>/dev/null)
                    local version=$(echo "$server_info" | jq -r '.Version // "Unknown"' 2>/dev/null)
                    echo -e "${CYAN}   🖥️  Server: $server_name (v$version)${RESET}"
                fi
            fi
        else
            echo -e "${YELLOW}⚠️  Emby Integration: Enabled but not configured${RESET}"
        fi
    else
        echo -e "${CYAN}💡 Emby Integration: Disabled${RESET}"
    fi
    echo
}

# Markets menu status
_show_markets_menu_status() {
    echo -e "${BOLD}${BLUE}Current Market Configuration:${RESET}"
    
    if [ -f "$CSV_FILE" ] && [ -s "$CSV_FILE" ]; then
        local market_count=$(awk 'END {print NR-1}' "$CSV_FILE")
        format_status_indicator "success" "Markets configured: $market_count"
        echo
        
        # Show market table
        _show_markets_table
        
        # FIXED: Status summary - count markets from CSV, not state file
        local cached_count=0
        local pending_count=0
        local base_cache_count=0
        
        while IFS=, read -r country zip; do
            [[ "$country" == "Country" ]] && continue
            
            if is_market_cached "$country" "$zip"; then
                ((cached_count++))
            elif is_market_in_base_cache "$country" "$zip" 2>/dev/null; then
                ((base_cache_count++))
            else
                ((pending_count++))
            fi
        done < "$CSV_FILE"
        
        if [ "$base_cache_count" -gt 0 ]; then
            echo -e "${CYAN}📊 Status Summary: ${GREEN}$cached_count cached${RESET}, ${YELLOW}$base_cache_count in base${RESET}, ${RED}$pending_count pending${RESET}"
        else
            echo -e "${CYAN}📊 Status Summary: ${GREEN}$cached_count cached${RESET}, ${RED}$pending_count pending${RESET}"
        fi
    else
        format_status_indicator "warning" "No markets configured"
    fi
}

# Settings menu status
_show_settings_menu_status() {
    echo -e "${BOLD}${BLUE}=== Current Configuration ===${RESET}"
    
    # Server configuration with status
    if [[ -n "${CHANNELS_URL:-}" ]]; then
        echo -e "${GREEN}✅ Channels DVR Server: $CHANNELS_URL${RESET}"
    else
        echo -e "${YELLOW}⚠️  Channels DVR Server: Not configured${RESET}"
    fi
    
    # Logo display with dependency check
    if [[ "$SHOW_LOGOS" == "true" ]]; then
        if command -v viu &> /dev/null; then
            echo -e "${GREEN}✅ Logo Display: Enabled${RESET}"
        else
            echo -e "${YELLOW}⚠️  Logo Display: Enabled (viu not installed)${RESET}"
        fi
    else
        echo -e "${CYAN}💡 Logo Display: Disabled${RESET}"
    fi
    
    # Resolution filter with enhanced details    
    if [[ "$FILTER_BY_RESOLUTION" == "true" ]]; then
      if [[ -n "$ENABLED_RESOLUTIONS" ]]; then
        echo -e "${GREEN}✅ Resolution Filter: Active (${YELLOW}$ENABLED_RESOLUTIONS${RESET})"
      else
        echo -e "${RED}❌ Resolution Filter: Enabled but no resolutions selected${RESET}"
      fi
    else
      echo -e "${CYAN}💡 Resolution Filter: Disabled (showing all quality levels)${RESET}"
    fi

    if [[ "$FILTER_BY_COUNTRY" == "true" ]]; then
      if [[ -n "$ENABLED_COUNTRIES" ]]; then
        echo -e "${GREEN}✅ Country Filter: Active (${YELLOW}$ENABLED_COUNTRIES${RESET})"
      else
        echo -e "${RED}❌ Country Filter: Enabled but no countries selected${RESET}"
      fi
    else
      echo -e "${CYAN}💡 Country Filter: Disabled (showing all countries)${RESET}"
    fi

    # Dispatcharr integration with connection status
    if [[ "$DISPATCHARR_ENABLED" == "true" ]]; then
        if [[ -n "${DISPATCHARR_URL:-}" ]]; then
            if dispatcharr_test_connection 2>/dev/null; then
                echo -e "${GREEN}✅ Dispatcharr Integration: Connected (${CYAN}$DISPATCHARR_URL${RESET})"
            else
                echo -e "${YELLOW}⚠️  Dispatcharr Integration: Configured but connection failed${RESET}"
            fi
        else
            echo -e "${YELLOW}⚠️  Dispatcharr Integration: Enabled but not configured${RESET}"
        fi
    else
        echo -e "${CYAN}💡 Dispatcharr Integration: Disabled${RESET}"
    fi

    # Emby integration with connection status
    if [[ "$EMBY_ENABLED" == "true" ]]; then
        if [[ -n "${EMBY_URL:-}" ]]; then
            if is_emby_authenticated 2>/dev/null; then
                echo -e "${GREEN}✅ Emby Integration: Connected (${CYAN}$EMBY_URL${RESET})"
            else
                echo -e "${YELLOW}⚠️  Emby Integration: Configured but connection failed${RESET}"
            fi
        else
            echo -e "${YELLOW}⚠️  Emby Integration: Enabled but not configured${RESET}"
        fi
    else
        echo -e "${CYAN}💡 Emby Integration: Disabled${RESET}"
    fi
    
    # Database status summary
    echo
    echo -e "${BOLD}${BLUE}=== Database Status ===${RESET}"
    local total_count=$(get_total_stations_count)
    local breakdown=$(get_stations_breakdown)
    local base_count=$(echo "$breakdown" | cut -d' ' -f1)
    local user_count=$(echo "$breakdown" | cut -d' ' -f2)
    
    if [ "$total_count" -gt 0 ]; then
        echo -e "${GREEN}✅ Station Database: $total_count stations available${RESET}"
        if [ "$base_count" -gt 0 ]; then
            echo -e "${CYAN}   📊 Base Stations: $base_count${RESET}"
        fi
        if [ "$user_count" -gt 0 ]; then
            echo -e "${CYAN}   📊 User Stations: $user_count${RESET}"
        fi
    else
        echo -e "${YELLOW}⚠️  Station Database: No stations available${RESET}"
    fi
    
    # Active search filters summary
    echo
    echo -e "${BOLD}${BLUE}=== Active Search Filters ===${RESET}"
    local active_filters=0
    
    if [[ "$FILTER_BY_RESOLUTION" == "true" ]] && [[ -n "$ENABLED_RESOLUTIONS" ]]; then
        echo -e "${GREEN}✅ Resolution Filter: $ENABLED_RESOLUTIONS${RESET}"
        ((active_filters++))
    fi
    
    if [[ "$FILTER_BY_COUNTRY" == "true" ]] && [[ -n "$ENABLED_COUNTRIES" ]]; then
        echo -e "${GREEN}✅ Country Filter: $ENABLED_COUNTRIES${RESET}"
        ((active_filters++))
    fi
    
    if [ "$active_filters" -eq 0 ]; then
        echo -e "${CYAN}💡 No search filters active - showing all available stations${RESET}"
    else
        echo -e "${CYAN}💡 $active_filters search filter(s) active - results will be filtered${RESET}"
    fi
}

# Private helpers
_show_token_status() {
    local token_file="$CACHE_DIR/dispatcharr_tokens.json"
    if [[ -f "$token_file" ]]; then
        local token_time=$(stat -c %Y "$token_file" 2>/dev/null || stat -f %m "$token_file" 2>/dev/null)
        if [[ -n "$token_time" ]]; then
            local current_time=$(date +%s)
            local age_minutes=$(( (current_time - token_time) / 60 ))
            
            if [ "$age_minutes" -lt 30 ]; then
                echo -e "   ${GREEN}🔑 Tokens: Fresh (${age_minutes}m old)${RESET}"
            else
                echo -e "   ${YELLOW}🔑 Tokens: Aging (${age_minutes}m old)${RESET}"
            fi
        fi
    fi
}

_show_processing_state_summary() {
    echo -e "${BOLD}${BLUE}=== Processing State ===${RESET}"
    
    local market_count=0
    if [ -f "$CSV_FILE" ]; then
        market_count=$(awk 'END {print NR-1}' "$CSV_FILE" 2>/dev/null || echo "0")
    fi
    
    if [ "$market_count" -gt 0 ]; then
        local cached_markets=0
        if [ -f "$CACHED_MARKETS" ] && [ -s "$CACHED_MARKETS" ]; then
            cached_markets=$(jq -s 'length' "$CACHED_MARKETS" 2>/dev/null || echo "0")
        fi
        local pending_markets=$((market_count - cached_markets))
        
        format_status_indicator "success" "Market Configuration: $market_count markets configured"
        if [ "$pending_markets" -gt 0 ]; then
            echo -e "   ${YELLOW}📊 Pending Markets: $pending_markets${RESET}"
        fi
    else
        format_status_indicator "warning" "Market Configuration: No markets configured"
    fi
    
    # Cache health
    if [ -d "$CACHE_DIR" ]; then
        local cache_size=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1 || echo "unknown")
        echo -e "${CYAN}📊 Total Cache Size: $cache_size${RESET}"
    fi
}

_show_markets_table() {
    if [ ! -f "$CSV_FILE" ] || [ ! -s "$CSV_FILE" ]; then
        return 0
    fi
    
    # Show compact market table
    printf "${BOLD}${YELLOW}%-12s %-15s %-12s %s${RESET}\n" "Country" "ZIP/Postal" "Status" "Notes"
    echo "-------------------------------------------------------"
    
    while IFS=, read -r country zip; do
        [[ "$country" == "Country" ]] && continue
        
        local status_text notes=""
        if is_market_cached "$country" "$zip"; then
            status_text="${GREEN}Cached${RESET}"
            notes="Ready"
        elif is_market_in_base_cache "$country" "$zip" 2>/dev/null; then
            status_text="${YELLOW}In base${RESET}"
            notes="May skip"
        else
            status_text="${RED}Pending${RESET}"
            notes="Not cached"
        fi
        
        # FIXED: Use echo -e instead of printf for colored text
        local country_field=$(printf "%-12s" "$country")
        local zip_field=$(printf "%-15s" "$zip")
        local notes_field=$(printf "%s" "$notes")
        echo -e "${country_field} ${zip_field} ${status_text}       ${notes_field}"
    done < "$CSV_FILE"
    echo
}

# ============================================================================
# MENU TEMPLATES
# ============================================================================

# Main menu template
show_main_menu() {
  # Define menu options
  local main_options=(
    "1|Search Local Database"
    "2|Dispatcharr Integration" 
    "3|Emby Integration"
    "4|Manage Television Markets for User Cache"
    "5|Run User Caching"
    "6|Direct API Search"
    "7|Reverse Station ID Lookup"
    "8|Local Cache Management"
    "9|Settings"
    "q|Quit"
  )
  
  show_menu "Global Station Search v$VERSION|system|main_options"

    local total_count=$(get_total_stations_count 2>/dev/null || echo "0")
    if [[ "${total_count:-0}" -eq 0 ]]; then
    echo
    echo -e "${BOLD}${YELLOW}💡 Quick Start Guide:${RESET}"
    echo -e "${CYAN}No station database found - here's how to get started:${RESET}"
    echo
    echo -e "${GREEN}Option 1: Immediate Use${RESET}"
    echo -e "• Try 'Search Local Database' - works with base cache if available"
    echo -e "• Use 'Direct API Search' if you have a Channels DVR server configured"
    echo
    echo -e "${GREEN}Option 2: Build Your Database${RESET}"
    echo -e "• Use 'Manage Television Markets' to add your local markets"
    echo -e "• Run 'Run User Caching' to build a comprehensive station database"
    echo -e "• Requires a Channels DVR server (configurable in Settings)"
    echo
    echo -e "${GREEN}Option 3: Integration${RESET}"
    echo -e "• Use 'Dispatcharr Integration' for automated channel management"
    echo -e "• Configure connections in 'Settings' menu"
    echo
  fi
}

# Settings menu template
show_settings_menu() {
    local settings_options=(
        "a|Change Channels DVR Server"
        "b|Toggle Logo Display"
        "c|Configure Resolution Filter"
        "d|Configure Country Filter"
        "e|View Cache Statistics"
        "f|Reset All Settings"
        "g|Export Settings"
        "h|Export Station Database to CSV"
        "i|Configure Dispatcharr Integration"
        "j|Configure Emby Integration"
        "k|Developer Information"
        "l|Update Management"
        "m|Backup Management"
        "q|Back to Main Menu"
    )
    
    show_menu "Settings|settings|settings_options"
}

# Cache management menu template
show_cache_management_menu() {
    local cache_options=(
        "a|Incremental Update|add new markets only"
        "b|Full User Cache Refresh|rebuild entire user cache"
        "c|View Cache Statistics|detailed breakdown"
        "d|Export Combined Database to CSV|backup/external use"
        "e|Clear User Cache|remove custom stations"
        "f|Clear Temporary Files|cleanup disk space"
        "g|Advanced Cache Operations|developer tools"
        "h|Clean Dispatcharr Logo Cache|remove old logo entries"
        "q|Back to Main Menu"
    )
    
    show_menu "Local Cache Management|cache|cache_options"
    
    # Show smart recommendations
    _show_cache_recommendations
}

# Dispatcharr integration menu template
show_dispatcharr_menu() {
    local dispatcharr_options=(
        "a|Scan Channels for Missing Station IDs"
        "b|Interactive Station ID Matching"
        "c|Commit Station ID Changes"
        "d|Populate Other Dispatcharr Fields|channel names, logos, tvg-ids"
        "e|Configure Dispatcharr Connection"
        "f|View Integration Logs"
        "g|Refresh Authentication Tokens"
        "q|Back to Main Menu"
    )
    
    show_menu "Dispatcharr Integration|dispatcharr|dispatcharr_options"
    
    # Show smart recommendations
    _show_dispatcharr_recommendations
}

show_markets_menu() {
    local markets_options=(
        "a|Add Market|Configure new country/ZIP combination"
        "b|Remove Market|Remove existing market from configuration"
        "c|Import Markets from File|Bulk import from CSV file"
        "d|Export Markets to File|Backup current configuration"
        "e|Clean Up Postal Code Formats|Standardize existing entries"
        "f|Force Refresh Market|Reprocess specific market"
        "r|Ready to Cache|Proceed to User Cache Expansion"
        "q|Back to Main Menu"
    )
    
    show_menu "Manage Television Markets|markets|markets_options"
}

# Private: Smart recommendations
_show_cache_recommendations() {
    local total_count=$(get_total_stations_count)
    local market_count=0
    if [ -f "$CSV_FILE" ]; then
        market_count=$(awk 'END {print NR-1}' "$CSV_FILE" 2>/dev/null || echo "0")
    fi
    
    if [ "$total_count" -eq 0 ] && [ "$market_count" -eq 0 ]; then
        echo -e "${BOLD}${YELLOW}💡 Quick Start Recommendation:${RESET}"
        echo -e "${CYAN}   1. First: Use 'Manage Television Markets' from main menu${RESET}"
        echo -e "${CYAN}   2. Then: Return here for 'Incremental Update'${RESET}"
    elif [ "$total_count" -eq 0 ] && [ "$market_count" -gt 0 ]; then
        echo -e "${BOLD}${YELLOW}💡 Quick Start Recommendation:${RESET}"
        echo -e "${CYAN}   Try option 'a' Incremental Update to build your station database${RESET}"
    fi
}

_show_dispatcharr_recommendations() {
    local total_count=$(get_total_stations_count)
    
    if [[ "$DISPATCHARR_ENABLED" != "true" ]]; then
        echo -e "${BOLD}${YELLOW}💡 Quick Start Recommendation:${RESET}"
        echo -e "${CYAN}   Start with option 'e' to configure your Dispatcharr connection${RESET}"
    elif ! dispatcharr_test_connection; then
        echo -e "${BOLD}${YELLOW}💡 Connection Issue Detected:${RESET}"
        echo -e "${CYAN}   Try option 'e' to reconfigure connection or 'g' to refresh tokens${RESET}"
    elif [ "$total_count" -eq 0 ]; then
        echo -e "${BOLD}${YELLOW}💡 Database Required:${RESET}"
        echo -e "${CYAN}   Build station database first via 'Manage Television Markets'${RESET}"
    elif [[ -f "$DISPATCHARR_MATCHES" ]] && [[ -s "$DISPATCHARR_MATCHES" ]]; then
        local pending_count=$(wc -l < "$DISPATCHARR_MATCHES")
        echo -e "${BOLD}${YELLOW}💡 Pending Changes Detected:${RESET}"
        echo -e "${CYAN}   You have $pending_count matches ready - try option 'c' to commit${RESET}"
    else
        echo -e "${BOLD}${YELLOW}💡 Ready for Channel Management:${RESET}"
        echo -e "${CYAN}   Start with option 'a' to scan for channels needing station IDs${RESET}"
    fi
}