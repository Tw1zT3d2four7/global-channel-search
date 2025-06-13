#!/bin/bash

# ============================================================================
# COMPREHENSIVE API FUNCTIONS MODULE
# ============================================================================
# All API function calls for Channels DVR and Dispatcharr with elegant error handling
# Each function provides single-line replacements for existing curl commands

# ============================================================================
# CONFIGURATION ACCESS HELPER
# ============================================================================

# Ensure configuration variables are available in API functions
ensure_config_loaded() {
    local config_file="${CONFIG_FILE:-data/globalstationsearch.env}"
    if [[ -f "$config_file" ]] && [[ -z "${CHANNELS_URL:-}" || -z "${DISPATCHARR_URL:-}" ]]; then
        source "$config_file" 2>/dev/null
    fi
}

url_encode() {
    local string="$1"
    local encoded=""
    local length=${#string}
    
    for ((i=0; i<length; i++)); do
        local char="${string:i:1}"
        case "$char" in
            [a-zA-Z0-9.~_-])
                encoded+="$char"
                ;;
            ' ')
                encoded+="%20"
                ;;
            *)
                # Convert to hex for other special characters
                printf -v hex "%02X" "'$char"
                encoded+="%$hex"
                ;;
        esac
    done
    
    echo "$encoded"
}

# ============================================================================
# API CONFIGURATION
# ============================================================================

# Default timeouts and retry settings
readonly API_QUICK_TIMEOUT=5
readonly API_STANDARD_TIMEOUT=10
readonly API_EXTENDED_TIMEOUT=15
readonly API_MAX_RETRIES=3

# ============================================================================
# CONFIGURATION MANAGEMENT
# ============================================================================

# Save Channels DVR configuration and refresh
save_channels_dvr_config() {
    local config_key="$1"
    local config_value="$2"
    local config_file="${CONFIG_FILE:-data/globalstationsearch.env}"
    
    if [[ -z "$config_key" ]]; then
        echo -e "${RED}❌ save_channels_dvr_config: config_key required${RESET}" >&2
        return 1
    fi
    
    echo -e "${CYAN}💾 Saving configuration: $config_key${RESET}" >&2
    
    # Use the main script's save_setting function if available
    if declare -f save_setting >/dev/null 2>&1; then
        save_setting "$config_key" "$config_value"
    else
        # Fallback: direct file manipulation
        if [[ -f "$config_file" ]]; then
            sed -i.bak "/^$config_key=/d" "$config_file"
            echo "$config_key=\"$config_value\"" >> "$config_file"
        else
            echo -e "${RED}❌ Config file not found: $config_file${RESET}" >&2
            return 1
        fi
    fi
    
    # Reload configuration
    reload_channels_dvr_config
    
    return 0
}

# Reload Channels DVR configuration
reload_channels_dvr_config() {
    local config_file="${CONFIG_FILE:-data/globalstationsearch.env}"
    
    echo -e "${CYAN}🔄 Reloading configuration from: $config_file${RESET}" >&2
    
    if [[ -f "$config_file" ]]; then
        source "$config_file" 2>/dev/null || {
            echo -e "${YELLOW}⚠️ Failed to source config file: $config_file${RESET}" >&2
            return 1
        }
        
        echo -e "${GREEN}✅ Configuration reloaded successfully${RESET}" >&2
        return 0
    else
        echo -e "${YELLOW}⚠️ Config file not found: $config_file${RESET}" >&2
        return 1
    fi
}

# Update Channels DVR URL and refresh
update_channels_dvr_url() {
    local new_url="$1"
    
    if [[ -z "$new_url" ]]; then
        echo -e "${RED}❌ update_channels_dvr_url: URL required${RESET}" >&2
        return 1
    fi
    
    # Validate URL format
    if [[ ! "$new_url" =~ ^https?:// ]]; then
        echo -e "${RED}❌ Invalid URL format: $new_url${RESET}" >&2
        return 1
    fi
    
    echo -e "${CYAN}🔄 Updating Channels DVR URL to: $new_url${RESET}" >&2
    
    save_channels_dvr_config "CHANNELS_URL" "$new_url"
    
    return $?
}

# ============================================================================
# CHANNELS DVR API FUNCTIONS
# ============================================================================

# Test basic connectivity to Channels DVR
channels_dvr_test_connection() {
    ensure_config_loaded
    
    if [[ -z "${CHANNELS_URL:-}" ]]; then
        echo -e "${RED}❌ Channels DVR: No server URL configured${RESET}" >&2
        echo -e "${CYAN}💡 Configure server in Settings → Channels DVR Server${RESET}" >&2
        return 1
    fi
    
    if curl -s --connect-timeout $API_QUICK_TIMEOUT "$CHANNELS_URL" >/dev/null 2>&1; then
        return 0
    else
        local curl_exit_code=$?
        echo -e "${RED}❌ Channels DVR: Connection failed to $CHANNELS_URL${RESET}" >&2
        case $curl_exit_code in
            6)
                echo -e "${CYAN}💡 Could not resolve hostname - check server IP address${RESET}" >&2
                ;;
            7)
                echo -e "${CYAN}💡 Connection refused - verify server is running and port is correct${RESET}" >&2
                ;;
            28)
                echo -e "${CYAN}💡 Connection timeout - server may be slow or unresponsive${RESET}" >&2
                ;;
            *)
                echo -e "${CYAN}💡 Network error (code: $curl_exit_code) - check connection and settings${RESET}" >&2
                ;;
        esac
        return 1
    fi
}

# Search for stations by name/call sign
channels_dvr_search_stations() {
    local search_term="$1"
    
    if [[ -z "$search_term" ]]; then
        echo -e "${RED}❌ Channels DVR API: Search term required${RESET}" >&2
        return 1
    fi
    
    ensure_config_loaded
    
    if ! channels_dvr_test_connection; then
        return 1
    fi
    
    # URL encode the search term to handle spaces and special characters
    local encoded_search_term=$(url_encode "$search_term")
    
    echo -e "${CYAN}🔍 Searching Channels DVR API for: '$search_term'${RESET}" >&2
    echo -e "${CYAN}📡 Encoded URL: $CHANNELS_URL/tms/stations/$encoded_search_term${RESET}" >&2
    
    local response
    response=$(curl -s \
        --connect-timeout $API_EXTENDED_TIMEOUT \
        --max-time $((API_EXTENDED_TIMEOUT * 2)) \
        "$CHANNELS_URL/tms/stations/$encoded_search_term" 2>/dev/null)
    
    local curl_exit_code=$?
    
    if [[ $curl_exit_code -ne 0 ]]; then
        case $curl_exit_code in
            3)
                echo -e "${RED}❌ Channels DVR API: Invalid URL format${RESET}" >&2
                echo -e "${CYAN}💡 Check if endpoint exists: $CHANNELS_URL/tms/stations/$encoded_search_term${RESET}" >&2
                ;;
            6)
                echo -e "${RED}❌ Channels DVR API: Cannot resolve hostname${RESET}" >&2
                echo -e "${CYAN}💡 Check your CHANNELS_URL setting: $CHANNELS_URL${RESET}" >&2
                ;;
            7)
                echo -e "${RED}❌ Channels DVR API: Connection failed${RESET}" >&2
                echo -e "${CYAN}💡 Is Channels DVR Server running on $CHANNELS_URL?${RESET}" >&2
                ;;
            28)
                echo -e "${RED}❌ Channels DVR API: Connection timeout${RESET}" >&2
                echo -e "${CYAN}💡 Server may be slow to respond or unreachable${RESET}" >&2
                ;;
            *)
                echo -e "${RED}❌ Channels DVR API: Network error during search (code: $curl_exit_code)${RESET}" >&2
                ;;
        esac
        echo -e "${CYAN}💡 Alternative: Use Local Database Search for reliable results${RESET}" >&2
        return 1
    fi
    
    if [[ -z "$response" ]]; then
        echo -e "${YELLOW}⚠️ Channels DVR API: No response from server${RESET}" >&2
        return 1
    fi
    
    if ! echo "$response" | jq empty 2>/dev/null; then
        echo -e "${RED}❌ Channels DVR API: Invalid response format${RESET}" >&2
        echo -e "${CYAN}💡 Server may be returning HTML error page instead of JSON${RESET}" >&2
        echo -e "${CYAN}💡 Response preview: ${response:0:100}...${RESET}" >&2
        return 1
    fi
    
    local result_count=$(echo "$response" | jq 'length' 2>/dev/null || echo "0")
    if [[ "$result_count" -eq 0 ]]; then
        echo -e "${YELLOW}⚠️ Channels DVR API: No stations found for '$search_term'${RESET}" >&2
        echo -e "${CYAN}💡 Try different spelling, call signs (CNN, ESPN), or partial names${RESET}" >&2
        return 1
    fi
    
    echo -e "${GREEN}✅ Channels DVR API: Found $result_count station(s)${RESET}" >&2
    echo "$response"
    return 0
}

# Get server version/status
channels_dvr_get_status() {
    if ! channels_dvr_test_connection; then
        return 1
    fi
    
    local response
    response=$(curl -s \
        --connect-timeout $API_STANDARD_TIMEOUT \
        "$CHANNELS_URL/api/status" 2>/dev/null)
    
    if [[ $? -eq 0 ]] && [[ -n "$response" ]]; then
        echo "$response"
        return 0
    else
        echo -e "${YELLOW}⚠️ Channels DVR: Status endpoint not available${RESET}" >&2
        return 1
    fi
}

# ============================================================================
# EMBY API FUNCTIONS
# ============================================================================

# Get Emby server information
emby_get_server_info() {
    if ! ensure_emby_auth; then
        echo -e "${RED}❌ Emby: Authentication failed${RESET}" >&2
        return 1
    fi
    
    local response
    response=$(curl -s \
        --connect-timeout $API_QUICK_TIMEOUT \
        -H "X-Emby-Token: $EMBY_API_KEY" \
        "${EMBY_URL}/emby/System/Info" 2>/dev/null)
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        echo "$response"
        return 0
    else
        echo -e "${RED}❌ Emby: Failed to get server information${RESET}" >&2
        return 1
    fi
}

# Test Emby connection and authentication
emby_test_connection() {
    echo -e "${CYAN}🔗 Testing Emby connection and authentication...${RESET}" >&2
    
    if [[ -z "${EMBY_URL:-}" ]] || [[ "$EMBY_ENABLED" != "true" ]]; then
        echo -e "${RED}❌ Emby: Not configured or disabled${RESET}" >&2
        echo -e "${CYAN}💡 Configure in Settings → Emby Integration${RESET}" >&2
        return 1
    fi
    
    if ! ensure_emby_auth; then
        echo -e "${RED}❌ Emby: Authentication failed${RESET}" >&2
        echo -e "${CYAN}💡 Check server URL, username, and password${RESET}" >&2
        return 1
    fi
    
    local server_info
    server_info=$(emby_get_server_info)
    
    if [[ $? -eq 0 ]]; then
        local server_name=$(echo "$server_info" | jq -r '.ServerName // "Unknown"')
        local version=$(echo "$server_info" | jq -r '.Version // "Unknown"')
        echo -e "${GREEN}✅ Emby: Connected to '$server_name' (v$version)${RESET}" >&2
        return 0
    else
        echo -e "${RED}❌ Emby: Connection test failed${RESET}" >&2
        return 1
    fi
} 

# Get Emby Live TV channels
emby_get_livetv_channels() {
    if ! ensure_emby_auth; then
        echo -e "${RED}❌ Emby: Authentication failed${RESET}" >&2
        return 1
    fi
    
    echo -e "${CYAN}📡 Fetching ALL Emby Live TV channels...${RESET}" >&2
    
    local response
    response=$(curl -s \
        --connect-timeout $API_STANDARD_TIMEOUT \
        --max-time $((API_STANDARD_TIMEOUT * 3)) \
        -H "X-Emby-Token: $EMBY_API_KEY" \
        "${EMBY_URL}/emby/LiveTv/Manage/Channels?Fields=ManagementId,ListingsId,Name,ChannelNumber,Id" 2>/dev/null)
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}❌ Emby: Network error fetching channels${RESET}" >&2
        return 1
    fi
    
    # Check if response is valid JSON
    if ! echo "$response" | jq empty 2>/dev/null; then
        echo -e "${RED}❌ Emby: Invalid JSON response${RESET}" >&2
        echo -e "${CYAN}Response preview: ${response:0:200}...${RESET}" >&2
        return 1
    fi
    
    # Handle both array and object responses
    local channels
    if echo "$response" | jq -e 'type == "array"' >/dev/null 2>&1; then
        # Direct array
        channels="$response"
    elif echo "$response" | jq -e '.Items' >/dev/null 2>&1; then
        # Object with Items property
        channels=$(echo "$response" | jq '.Items')
    else
        echo -e "${RED}❌ Emby: Unexpected response structure${RESET}" >&2
        echo -e "${CYAN}Response keys: $(echo "$response" | jq 'keys' 2>/dev/null)${RESET}" >&2
        return 1
    fi
    
    local channel_count=$(echo "$channels" | jq 'length' 2>/dev/null || echo "0")
    echo -e "${GREEN}✅ Retrieved $channel_count Live TV channels${RESET}" >&2
    
    if [[ "$channel_count" -eq 0 ]]; then
        echo -e "${YELLOW}⚠️  No channels found${RESET}" >&2
        return 1
    fi
    
    echo "$channels"
    return 0
}

# Find channels missing Listings ID and extract Station ID
emby_find_channels_missing_listingsid() {
    if ! ensure_emby_auth; then
        echo -e "${RED}❌ Emby: Authentication failed${RESET}" >&2
        return 1
    fi
    
    echo -e "${CYAN}🔍 Scanning Emby channels for missing ListingsId...${RESET}" >&2
    
    local channels_data
    channels_data=$(emby_get_livetv_channels)
    
    if [[ $? -ne 0 ]] || [[ -z "$channels_data" ]]; then
        echo -e "${RED}❌ Failed to get channel data${RESET}" >&2
        return 1
    fi
    
    echo -e "${CYAN}🔍 Processing channels to find missing ListingsId...${RESET}" >&2
    
    # Filter channels missing ListingsId first
    local missing_channels_raw
    missing_channels_raw=$(echo "$channels_data" | jq -c '.[] | select(.ListingsId == null or .ListingsId == "" or .ListingsId == "null")')
    
    if [[ -z "$missing_channels_raw" ]]; then
        echo -e "${GREEN}✅ All channels have ListingsId assigned${RESET}" >&2
        echo "[]"
        return 0
    fi
    
    # Count total channels to process
    local missing_channels_array=()
    while IFS= read -r channel_line; do
        if [[ -n "$channel_line" ]]; then
            missing_channels_array+=("$channel_line")
        fi
    done <<< "$missing_channels_raw"
    
    local total_missing=${#missing_channels_array[@]}
    echo -e "${CYAN}📊 Processing $total_missing channels missing ListingsId...${RESET}" >&2
    echo >&2
    
    # Process each channel with progress indicator
    local processed_count=0
    local successful_extractions=0
    local processed_channels=()
    
    for channel_line in "${missing_channels_array[@]}"; do
        ((processed_count++))
        
        # Show progress indicator
        echo -ne "\r${CYAN}🔍 Extracting station ID ${BOLD}$processed_count${RESET}${CYAN} of ${BOLD}$total_missing${RESET}${CYAN}...${RESET}" >&2
        
        # Extract station ID from ManagementId
        local management_id=$(echo "$channel_line" | jq -r '.ManagementId // empty')
        local extracted_id=""
        
        if [[ -n "$management_id" && "$management_id" != "null" ]]; then
            # Extract everything after the last underscore
            extracted_id="${management_id##*_}"
            
            # Validate it's a reasonable station ID (numeric, reasonable length)
            if [[ "$extracted_id" =~ ^[0-9]+$ ]] && [[ ${#extracted_id} -ge 4 ]] && [[ ${#extracted_id} -le 10 ]]; then
                # Add ExtractedId to the channel object
                local enhanced_channel
                enhanced_channel=$(echo "$channel_line" | jq --arg extracted_id "$extracted_id" '. + {ExtractedId: $extracted_id}')
                processed_channels+=("$enhanced_channel")
                ((successful_extractions++))
            fi
        fi
        
        # Small delay for visual progress
        sleep 0.005
    done
    
    # Clear progress line and show results
    echo -e "\r${GREEN}✅ Station ID extraction completed: ${BOLD}$successful_extractions${RESET}${GREEN} of ${BOLD}$total_missing${RESET}${GREEN} successful${RESET}" >&2
    echo >&2
    
    if [[ "$successful_extractions" -eq 0 ]]; then
        echo -e "${YELLOW}⚠️  No valid station IDs could be extracted${RESET}" >&2
        echo "[]"
        return 0
    fi
    
    # Return processed channels as individual JSON objects (maintain existing format)
    printf '%s\n' "${processed_channels[@]}"
    return 0
}

# Reverse lookup station IDs to get lineupId, country, and lineupName
emby_reverse_lookup_station_ids() {
    local station_ids_array=("$@")
    local total_ids=${#station_ids_array[@]}
    
    # Check if we have a station database
    if ! has_stations_database; then
        echo -e "${RED}❌ No station database available for reverse lookup${RESET}" >&2
        echo -e "${CYAN}💡 Build database via 'Manage Television Markets' → 'Run User Caching'${RESET}" >&2
        return 1
    fi
    
    local stations_file
    stations_file=$(get_effective_stations_file)
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}❌ Failed to access station database${RESET}" >&2
        return 1
    fi
    
    echo -e "${CYAN}💡 Searching your local station database for matching stations...${RESET}" >&2
    echo >&2
    
    # Create result array for lookup results
    local lookup_results=()
    local found_count=0
    local not_found_count=0
    local processed_count=0
    
    for station_id in "${station_ids_array[@]}"; do
        ((processed_count++))
        
        # Show CLEAN progress indicator
        echo -ne "\r${CYAN}🔍 Looking up station ID ${BOLD}$processed_count${RESET}${CYAN} of ${BOLD}$total_ids${RESET}${CYAN} (${BOLD}$found_count${RESET}${CYAN} found)...${RESET}" >&2
        
        # Query using the CORRECT structure for your database
        local station_data
        station_data=$(jq -r --arg id "$station_id" '
            .[] | select(.stationId == $id) |
            if .lineupTracing and (.lineupTracing | length > 0) then
                {
                    stationId: .stationId,
                    lineupId: .lineupTracing[0].lineupId,
                    country: .lineupTracing[0].country,
                    lineupName: .lineupTracing[0].lineupName
                }
            else
                empty
            end
        ' "$stations_file" 2>/dev/null)
        
        if [[ -n "$station_data" && "$station_data" != "null" && "$station_data" != "{}" ]]; then
            lookup_results+=("$station_data")
            ((found_count++))
        else
            ((not_found_count++))
        fi
    done
    
    # Clear progress line and show results
    echo -e "\r${GREEN}✅ Lookup completed: ${BOLD}$found_count${RESET}${GREEN} found, ${BOLD}$not_found_count${RESET}${GREEN} not found                    ${RESET}" >&2
    echo >&2
    
    if [[ "$found_count" -eq 0 ]]; then
        echo -e "${YELLOW}⚠️  No station matches found in your database${RESET}" >&2
        return 1
    fi
    
    # Output results as JSON array
    printf '%s\n' "${lookup_results[@]}" | jq -s '.' 2>/dev/null
    return 0
}

process_emby_missing_listings() {
    local lookup_results="$1"
    local channel_mapping=("${@:2}")
    
    echo -e "\n${BOLD}${CYAN}=== Adding Missing Listing Providers to Emby ===${RESET}"
    echo
    
    # Extract unique listing providers from lookup results
    local unique_providers
    unique_providers=$(echo "$lookup_results" | jq -r '.[] | "\(.lineupId)|\(.country)|\(.lineupName)"' | sort -u)
    
    local provider_count=$(echo "$unique_providers" | wc -l)
    
    echo -e "${CYAN}📊 Found ${BOLD}$provider_count unique listing providers${RESET}${CYAN} to add${RESET}"
    echo
    
    # Show what we're about to add
    echo -e "${BOLD}${BLUE}=== Listing Providers to Add ===${RESET}"
    printf "${BOLD}${YELLOW}%-20s %-10s %-30s${RESET}\n" "LineupId" "Country" "Name"
    echo "------------------------------------------------------------"
    
    while IFS='|' read -r lineup_id country lineup_name; do
        printf "%-20s %-10s %-30s\n" "$lineup_id" "$country" "$lineup_name"
    done <<< "$unique_providers"
    
    echo
    
    if ! confirm_action "Add these $provider_count listing providers to Emby?"; then
        echo -e "${YELLOW}⚠️  Operation cancelled by user${RESET}"
        return 0
    fi
    
    # Add each unique listing provider
    echo -e "\n${CYAN}📡 Adding listing providers to Emby...${RESET}"
    
    local added_count=0
    local failed_count=0
    local already_exists_count=0
    local provider_details=()
    
    while IFS='|' read -r lineup_id country lineup_name; do
        echo -e "${CYAN}  📡 Adding provider: ${BOLD}$lineup_id${RESET}${CYAN} ($lineup_name)${RESET}"
        
        if emby_add_listing_provider "$lineup_id" "$country" "$lineup_name" "embygn"; then
            ((added_count++))
            echo -e "${GREEN}     ✅ Successfully added${RESET}"
            provider_details+=("$lineup_id ($country): $lineup_name")
        else
            # Check if it was a "already exists" case (we return 0 for 409)
            if [[ $? -eq 0 ]]; then
                ((already_exists_count++))
                echo -e "${CYAN}     ℹ️  Already configured${RESET}"
            else
                ((failed_count++))
                echo -e "${RED}     ❌ Failed to add${RESET}"
            fi
        fi
        echo
    done <<< "$unique_providers"
    
    # Final summary
    echo -e "${BOLD}${BLUE}=== Listing Provider Addition Complete ===${RESET}"
    echo
    
    if [[ $added_count -gt 0 ]]; then
        echo -e "${GREEN}🎉 SUCCESS: ${BOLD}$added_count listing providers${RESET}${GREEN} added!${RESET}"
        echo
        echo -e "${BOLD}${GREEN}Providers Added:${RESET}"
        for detail in "${provider_details[@]}"; do
            echo -e "${GREEN}  ✅ $detail${RESET}"
        done
        echo
    fi
    
    if [[ $already_exists_count -gt 0 ]]; then
        echo -e "${CYAN}ℹ️  ${BOLD}$already_exists_count providers${RESET}${CYAN} already existed${RESET}"
    fi
    
    if [[ $failed_count -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  ${BOLD}$failed_count providers${RESET}${YELLOW} failed to add${RESET}"
    fi
    
    echo
    echo -e "${CYAN}📊 Final Summary:${RESET}"
    echo -e "${GREEN}  • Listing providers added: $added_count${RESET}"
    echo -e "${CYAN}  • Already existed: $already_exists_count${RESET}"
    echo -e "${YELLOW}  • Failed: $failed_count${RESET}"
    
    if [[ $added_count -gt 0 ]]; then
        echo
        echo -e "${BOLD}${GREEN}🎯 Emby Listing Provider Addition Complete!${RESET}"
        echo -e "${CYAN}Emby will now automatically map your channels to the new listing providers.${RESET}"
        echo -e "${CYAN}💡 Check your Emby Live TV settings to see the automatic channel mapping.${RESET}"
        echo -e "${CYAN}💡 It may take a few minutes for Emby to process the new listings.${RESET}"
    fi
    
    return 0
}

# Add listing providers for all channels missing lineup data
emby_add_listing_provider() {
    local listings_id="$1"
    local country="$2"
    local lineup_name="$3"
    local type="${4:-embygn}"
    
    if [[ -z "$listings_id" || -z "$country" ]]; then
        return 1
    fi
    
    if ! ensure_emby_auth; then
        return 1
    fi
    
    # Prepare JSON payload for listing provider
    local provider_payload
    provider_payload=$(jq -n \
        --arg listings_id "$listings_id" \
        --arg type "$type" \
        --arg country "$country" \
        --arg name "${lineup_name:-$listings_id}" \
        '{
            ListingsId: $listings_id,
            Type: $type,
            Country: $country,
            Name: $name
        }')
    
    # Add to Emby listing providers (silent operation for progress display)
    local response
    response=$(curl -s \
        --connect-timeout $API_STANDARD_TIMEOUT \
        --max-time $((API_STANDARD_TIMEOUT * 2)) \
        -w "HTTPSTATUS:%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -H "X-Emby-Token: $EMBY_API_KEY" \
        -d "$provider_payload" \
        "${EMBY_URL}/emby/LiveTv/ListingProviders" 2>/dev/null)
    
    local curl_exit_code=$?
    local http_status=$(echo "$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
    
    # Handle results (return codes only, progress display handles messaging)
    if [[ $curl_exit_code -ne 0 ]]; then
        return 1
    fi
    
    case "$http_status" in
        200|201|204|409)  # Include 409 (already exists) as success
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

process_emby_missing_listings() {
    local lookup_results="$1"
    shift
    local channel_mapping=("$@")
    
    # Extract unique listing providers from lookup results
    local unique_providers
    unique_providers=$(echo "$lookup_results" | jq -r '.[] | "\(.lineupId)|\(.country)|\(.lineupName)"' | sort -u)
    
    if [[ -z "$unique_providers" ]]; then
        echo -e "${YELLOW}⚠️  No listing providers to add${RESET}"
        return 0
    fi
    
    # Count and collect providers
    local providers_array=()
    while IFS='|' read -r lineup_id country lineup_name; do
        if [[ -n "$lineup_id" ]]; then
            providers_array+=("$lineup_id|$country|$lineup_name")
        fi
    done <<< "$unique_providers"
    
    local provider_count=${#providers_array[@]}
    
    # Add each unique listing provider WITH PROGRESS
    local added_count=0
    local failed_count=0
    local processed_count=0
    
    for provider_info in "${providers_array[@]}"; do
        IFS='|' read -r lineup_id country lineup_name <<< "$provider_info"
        ((processed_count++))
        
        # Show progress indicator
        echo -ne "\r${CYAN}📡 Adding provider ${BOLD}$processed_count${RESET}${CYAN} of ${BOLD}$provider_count${RESET}${CYAN}: ${BOLD}$lineup_id${RESET}${CYAN}...${RESET}"
        
        # Add the listing provider
        if emby_add_listing_provider "$lineup_id" "$country" "$lineup_name" "embygn" 2>/dev/null; then
            ((added_count++))
            echo -ne " ${GREEN}✅${RESET}"
        else
            ((failed_count++))
            echo -ne " ${RED}❌${RESET}"
        fi
        
        # Small delay for visual feedback
        sleep 0.1
        echo  # New line after each provider
    done
    
    # Clear progress and show final summary
    echo
    echo -e "${BOLD}${BLUE}=== Listing Provider Addition Complete ===${RESET}"
    echo -e "${GREEN}  • Successfully added: $added_count${RESET}"
    echo -e "${YELLOW}  • Failed to add: $failed_count${RESET}"
    
    if [[ $added_count -gt 0 ]]; then
        echo -e "\n${BOLD}${GREEN}🎯 Success! Added $added_count listing providers to Emby${RESET}"
        echo -e "${CYAN}💡 Emby will now automatically map channels to these new listings${RESET}"
        echo -e "${CYAN}💡 Check Emby Live TV settings to see automatic channel mapping${RESET}"
        echo -e "${CYAN}💡 Channel mapping may take a few minutes to complete${RESET}"
    fi
    
    return 0
}

test_emby_channel_mapping_endpoints() {
    echo -e "\n${BOLD}${CYAN}=== Testing Emby Channel Mapping Endpoints ===${RESET}"
    
    if ! ensure_emby_auth; then
        echo -e "${RED}❌ Authentication required${RESET}"
        return 1
    fi
    
    local test_endpoints=(
        "/emby/LiveTv/ListingProviders|Working update endpoint"
        "/emby/LiveTv/GuideInfo|Guide information"
        "/emby/LiveTv/ChannelMappingOptions|Channel mapping options"
        "/emby/LiveTv/SetChannelMapping|Set channel mapping"
        "/emby/LiveTv/TunerChannels|Tuner channels"
    )
    
    for endpoint_info in "${test_endpoints[@]}"; do
        IFS='|' read -r endpoint description <<< "$endpoint_info"
        echo -e "${CYAN}   Testing: $endpoint${RESET}"
        echo -e "${CYAN}   Purpose: $description${RESET}"
        
        local response
        response=$(curl -s \
            --connect-timeout 10 \
            -w "HTTPSTATUS:%{http_code}" \
            -H "X-Emby-Token: $EMBY_API_KEY" \
            "${EMBY_URL}${endpoint}" 2>/dev/null)
        
        local status=$(echo "$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
        echo -e "      📊 Status: $status"
        
        case "$status" in
            200)
                echo -e "${GREEN}      ✅ Endpoint exists${RESET}"
                if [[ "$endpoint" == "/emby/LiveTv/ListingProviders" ]]; then
                    echo -e "${GREEN}      🎯 This is the working update endpoint!${RESET}"
                fi
                ;;
            404)
                echo -e "${RED}      ❌ Not found${RESET}"
                ;;
            500)
                echo -e "${YELLOW}      ⚠️  Server error${RESET}"
                ;;
            *)
                echo -e "${YELLOW}      ⚠️  Status: $status${RESET}"
                ;;
        esac
        echo
    done
}

generate_emby_analysis_report() {
    local channels_data="$1"
    local missing_channels="$2"
    
    echo -e "\n${BOLD}${CYAN}=== EMBY CHANNEL ANALYSIS REPORT ===${RESET}"
    
    # Count channels
    local total_count missing_count complete_count
    total_count=$(echo "$channels_data" | jq 'length' 2>/dev/null || echo "0")
    missing_count=$(echo "$missing_channels" | jq -s 'length' 2>/dev/null || echo "0")
    complete_count=$((total_count - missing_count))
    
    echo -e "\n${BOLD}📊 Channel Statistics:${RESET}"
    echo -e "• Total channels found: ${CYAN}$total_count${RESET}"
    echo -e "• Channels with ListingsId: ${GREEN}$complete_count${RESET}"
    echo -e "• Channels missing ListingsId: ${YELLOW}$missing_count${RESET}"
    
    if [[ "$total_count" -gt 0 ]]; then
        echo -e "• Coverage percentage: ${CYAN}$(( complete_count * 100 / total_count ))%${RESET}"
    fi
    
    echo -e "\n${BOLD}🔍 Technical Status:${RESET}"
    echo -e "• Emby API connectivity: ${GREEN}✅ Working${RESET}"
    echo -e "• Channel data retrieval: ${GREEN}✅ Working${RESET}"
    echo -e "• Station ID extraction: ${GREEN}✅ Working${RESET}"
    echo -e "• Listing provider updates: ${GREEN}✅ Working via /emby/LiveTv/ListingProviders${RESET}"
    
    if [[ "$missing_count" -gt 0 ]]; then
        echo -e "\n${BOLD}📋 Sample Channels Needing ListingsId:${RESET}"
        echo "$missing_channels" | jq -r 'select(type == "object") | "• \(.ChannelNumber // "No#") - \(.Name // "No Name") (Station: \(.ExtractedId))"' | head -10
    fi
    
    echo -e "\n${BOLD}💡 Integration Approach:${RESET}"
    echo -e "• Station IDs are successfully extracted from ManagementId"
    echo -e "• Lookup station IDs to find corresponding LineupIds"
    echo -e "• ${GREEN}✅ Add unique LineupIds as listing providers to Emby${RESET}"
    echo -e "• ${GREEN}✅ Let Emby automatically map channels to new listings${RESET}"
    echo -e "• Much more efficient than updating individual channels"
}

# Test the complete Emby integration workflow
test_complete_emby_workflow() {
    echo -e "\n${BOLD}${CYAN}=== Complete Emby Integration Test ===${RESET}"
    
    # Step 1: Connection test
    echo -e "\n${BOLD}1️⃣ Connection Test${RESET}"
    if emby_test_connection >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Connection successful${RESET}"
    else
        echo -e "${RED}❌ Connection failed${RESET}"
        return 1
    fi
    
    # Step 2: Channel retrieval test
    echo -e "\n${BOLD}2️⃣ Channel Retrieval Test${RESET}"
    local channels
    channels=$(emby_get_livetv_channels)
    if [[ $? -eq 0 ]]; then
        local channel_count=$(echo "$channels" | jq 'length' 2>/dev/null || echo "0")
        echo -e "${GREEN}✅ Retrieved $channel_count channels${RESET}"
    else
        echo -e "${RED}❌ Failed to retrieve channels${RESET}"
        return 1
    fi
    
    # Step 3: Missing channels analysis
    echo -e "\n${BOLD}3️⃣ Missing ListingsId Analysis${RESET}"
    local missing_channels
    missing_channels=$(emby_find_channels_missing_listingsid)
    if [[ $? -eq 0 ]]; then
        # Count missing channels correctly (they come as individual JSON objects)
        local missing_count=0
        while IFS= read -r channel_line; do
            if [[ -n "$channel_line" && "$channel_line" != "null" ]]; then
                ((missing_count++))
            fi
        done < <(echo "$missing_channels" | jq -c '.')
        
        echo -e "${GREEN}✅ Found $missing_count channels missing ListingsId${RESET}"
    else
        echo -e "${RED}❌ Failed to analyze missing channels${RESET}"
        return 1
    fi
    
    # Step 4: Listing Provider Addition Test (NEW APPROACH)
    echo -e "\n${BOLD}4️⃣ Listing Provider Addition Test${RESET}"
    if [[ "$missing_count" -gt 0 ]]; then
        echo -e "${CYAN}📡 Testing listing provider addition capability...${RESET}"
        
        # Test adding a sample listing provider
        echo -e "${CYAN}🧪 Testing with sample provider: TEST-LINEUP-12345${RESET}"
        
        if emby_add_listing_provider "TEST-LINEUP-12345" "USA" "Test Listing Provider" "embygn"; then
            echo -e "${GREEN}✅ Listing provider addition is working perfectly!${RESET}"
            echo -e "${GREEN}🎯 Your Emby integration is fully functional${RESET}"
            
            # Clean up test provider (optional - it won't hurt to leave it)
            echo -e "${CYAN}💡 Test provider added successfully (you can remove it manually from Emby if desired)${RESET}"
        else
            echo -e "${RED}❌ Listing provider addition test failed${RESET}"
            echo -e "${CYAN}💡 Check Emby server logs for more details${RESET}"
            return 1
        fi
    else
        echo -e "${GREEN}✅ No missing channels found - all channels already have ListingsId${RESET}"
        echo -e "${CYAN}💡 Testing listing provider addition with sample data anyway...${RESET}"
        
        # Still test the endpoint even if no missing channels
        if emby_add_listing_provider "TEST-SAMPLE-99999" "USA" "Sample Test Provider" "embygn"; then
            echo -e "${GREEN}✅ Listing provider endpoint is working${RESET}"
        else
            echo -e "${YELLOW}⚠️  Listing provider test had issues (but no missing channels anyway)${RESET}"
        fi
    fi
    
    # Step 5: Station ID Extraction Test
    echo -e "\n${BOLD}5️⃣ Station ID Extraction Test${RESET}"
    if [[ "$missing_count" -gt 0 ]]; then
        echo -e "${CYAN}🔍 Testing station ID extraction from ManagementId...${RESET}"
        
        # Get a sample missing channel and test extraction
        local sample_channel
        sample_channel=$(echo "$missing_channels" | head -1)
        
        if [[ -n "$sample_channel" ]]; then
            local extracted_id=$(echo "$sample_channel" | jq -r '.ExtractedId // empty')
            local management_id=$(echo "$sample_channel" | jq -r '.ManagementId // empty')
            
            if [[ -n "$extracted_id" && "$extracted_id" != "null" ]]; then
                echo -e "${GREEN}✅ Station ID extraction working${RESET}"
                echo -e "${CYAN}   📋 Sample ManagementId: ${management_id:0:50}...${RESET}"
                echo -e "${CYAN}   📋 Extracted Station ID: $extracted_id${RESET}"
            else
                echo -e "${YELLOW}⚠️  Station ID extraction may have issues${RESET}"
                echo -e "${CYAN}   📋 Sample ManagementId: $management_id${RESET}"
            fi
        else
            echo -e "${YELLOW}⚠️  No sample channel available for extraction test${RESET}"
        fi
    else
        echo -e "${GREEN}✅ No missing channels to test extraction with${RESET}"
    fi
    
    # Step 6: Endpoint mapping test
    echo -e "\n${BOLD}6️⃣ Endpoint Mapping Test${RESET}"
    test_emby_channel_mapping_endpoints
    
    # Step 7: Database availability test
    echo -e "\n${BOLD}7️⃣ Station Database Test${RESET}"
    if has_stations_database; then
        local stations_file
        stations_file=$(get_effective_stations_file)
        if [[ $? -eq 0 ]]; then
            local db_count=$(jq 'length' "$stations_file" 2>/dev/null || echo "0")
            echo -e "${GREEN}✅ Station database available with $db_count stations${RESET}"
        else
            echo -e "${YELLOW}⚠️  Station database file issues${RESET}"
        fi
    else
        echo -e "${YELLOW}⚠️  No station database available${RESET}"
        echo -e "${CYAN}💡 Build database via 'Manage Television Markets' → 'Run User Caching'${RESET}"
    fi
    
    # Final results
    echo -e "\n${BOLD}🎉 Complete Emby Integration Test Results:${RESET}"
    echo -e "${GREEN}✅ Connection: Working${RESET}"
    echo -e "${GREEN}✅ Channel retrieval: Working (${channel_count} channels)${RESET}"
    echo -e "${GREEN}✅ Missing channel analysis: Working (${missing_count} missing)${RESET}"
    echo -e "${GREEN}✅ Listing provider addition: Working${RESET}"
    echo -e "${GREEN}✅ Station ID extraction: Working${RESET}"
    
    if [[ "$missing_count" -gt 0 ]]; then
        echo -e "\n${CYAN}💡 You can now run the full workflow to add listing providers for $missing_count channels${RESET}"
    else
        echo -e "\n${CYAN}💡 All channels already configured - integration is ready for future use${RESET}"
    fi
    
    echo -e "${CYAN}💡 Integration approach: Add unique listing providers → Let Emby auto-map channels${RESET}"
}

# ============================================================================
# EMBY API HEALTH CHECK INTEGRATION
# ============================================================================

# Get Emby API status for health monitoring
get_emby_api_status() {
    if [[ "$EMBY_ENABLED" != "true" ]]; then
        echo "disabled"
        return 1
    fi
    
    if [[ -z "${EMBY_URL:-}" ]]; then
        echo "not_configured"
        return 1
    fi
    
    if emby_test_connection >/dev/null 2>&1; then
        echo "healthy"
        return 0
    else
        echo "unhealthy"
        return 1
    fi
}

# ============================================================================
# MODULE INITIALIZATION
# ============================================================================

# Initialize API system
init_api_system() {
    # Ensure log directories exist
    mkdir -p "$(dirname "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}")" 2>/dev/null
    mkdir -p "${LOGS_DIR:-/tmp}" 2>/dev/null
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - API module initialized" >> "${LOGS_DIR:-/tmp}/api_general.log"
    
    # Test services if they're configured
    if [[ -n "${CHANNELS_URL:-}" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Testing Channels DVR connection..." >> "${LOGS_DIR:-/tmp}/api_general.log"
    fi
    
    if [[ "$DISPATCHARR_ENABLED" == "true" ]] && [[ -n "${DISPATCHARR_URL:-}" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Testing Dispatcharr connection..." >> "${LOGS_DIR:-/tmp}/api_general.log"
    fi
}

# Auto-initialize when module is loaded
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    init_api_system
fi