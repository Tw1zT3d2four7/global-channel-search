#!/bin/bash

# ============================================================================
# DISPATCHARR INTEGRATION MODULE
# ============================================================================
# Consolidated Dispatcharr functionality with enhanced just-in-time auth
# All Dispatcharr operations should eventually use this module
# Created: 2025-06-07
# Version: 1.0.0

# ============================================================================
# MODULE CONFIGURATION
# ============================================================================

# Token freshness threshold (seconds) - check token if older than this
DISPATCHARR_TOKEN_FRESHNESS_THRESHOLD=30

# Module state tracking
DISPATCHARR_MODULE_INITIALIZED=false
DISPATCHARR_LAST_TOKEN_VALIDATION=0

# ============================================================================
# TOKEN FILE PATH INITIALIZATION
# ============================================================================

# Ensure DISPATCHARR_TOKENS is set properly
_dispatcharr_init_token_path() {
    if [[ -z "${DISPATCHARR_TOKENS:-}" ]]; then
        # Use cache directory if available, otherwise fall back to /tmp
        local cache_dir="${CACHE_DIR:-/tmp}"
        export DISPATCHARR_TOKENS="$cache_dir/dispatcharr_tokens.json"
        
        # Ensure directory exists
        mkdir -p "$(dirname "$DISPATCHARR_TOKENS")" 2>/dev/null
    fi
}

# ============================================================================
# CORE TOKEN MANAGEMENT FUNCTIONS
# ============================================================================

# Check if current token is fresh enough to skip validation
_dispatcharr_token_needs_check() {
    local current_time=$(date +%s)
    local time_since_check=$((current_time - DISPATCHARR_LAST_TOKEN_VALIDATION))
    
    if [[ $time_since_check -gt $DISPATCHARR_TOKEN_FRESHNESS_THRESHOLD ]]; then
        return 0  # Yes, needs check
    else
        return 1  # No, still fresh
    fi
}

# Ensure we have a valid token with just-in-time verification
dispatcharr_ensure_valid_token() {
    # Quick return if token was recently validated
    if ! _dispatcharr_token_needs_check; then
        return 0
    fi
    
    # Update validation timestamp immediately to prevent race conditions
    DISPATCHARR_LAST_TOKEN_VALIDATION=$(date +%s)
    
    # Check if we have basic configuration
    if [[ -z "${DISPATCHARR_URL:-}" ]] || [[ "$DISPATCHARR_ENABLED" != "true" ]]; then
        return 1
    fi
    
    # Try token validation first (fastest)
    if _dispatcharr_validate_current_token; then
        return 0
    fi
    
    # If validation failed, try refresh (faster than full auth)
    if _dispatcharr_refresh_token; then
        return 0
    fi
    
    # Last resort: full authentication
    if _dispatcharr_full_authentication; then
        return 0
    fi
    
    # All methods failed
    return 1
}

# API wrapper that ensures authentication before every call
dispatcharr_api_wrapper() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    local extra_headers="$4"
    
    # Input validation
    if [[ -z "$method" || -z "$endpoint" ]]; then
        _dispatcharr_log "error" "API wrapper called with missing method or endpoint"
        return 1
    fi
    
    # Ensure we have a valid token with detailed error reporting
    if ! dispatcharr_ensure_valid_token; then
        _dispatcharr_log "error" "Failed to obtain valid authentication token"
        return 1
    fi
    
    # Get current access token
    local access_token
    access_token=$(get_dispatcharr_access_token)
    
    if [[ -z "$access_token" ]]; then
        _dispatcharr_log "error" "No access token available after authentication"
        return 1
    fi
    
    _dispatcharr_log "info" "Making ${method} request to ${endpoint}"
    
    # Build and execute curl command with error checking
    local response
    local http_code
    
    response=$(curl -s -w "%{http_code}" \
        --connect-timeout "${API_TIMEOUT:-10}" \
        --max-time "${API_MAX_TIME:-30}" \
        -X "$method" \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        ${extra_headers:+$extra_headers} \
        ${data:+-d "$data"} \
        "${DISPATCHARR_URL}${endpoint}")
    
    local curl_exit_code=$?
    
    # Extract HTTP status code (last 3 characters)
    http_code="${response: -3}"
    response="${response%???}"  # Remove status code from response
    
    # Handle curl errors
    if [[ $curl_exit_code -ne 0 ]]; then
        _dispatcharr_log "error" "Network error (curl exit code: $curl_exit_code) for ${method} ${endpoint}"
        return 1
    fi
    
    # Handle HTTP errors
    case "$http_code" in
        200|201|204)
            _dispatcharr_log "info" "Successful ${method} request to ${endpoint} (HTTP $http_code)"
            echo "$response"
            return 0
            ;;
        401)
            _dispatcharr_log "warn" "Authentication failed (HTTP 401) - token may be expired"
            # Invalidate current auth state to force re-authentication
            DISPATCHARR_LAST_TOKEN_VALIDATION=0
            return 1
            ;;
        403)
            _dispatcharr_log "error" "Access forbidden (HTTP 403) for ${method} ${endpoint}"
            return 1
            ;;
        404)
            _dispatcharr_log "error" "Endpoint not found (HTTP 404): ${endpoint}"
            return 1
            ;;
        *)
            _dispatcharr_log "error" "HTTP error $http_code for ${method} ${endpoint}"
            return 1
            ;;
    esac
}

# ============================================================================
# INTERNAL HELPER FUNCTIONS
# ============================================================================

_dispatcharr_validate_current_token() {
    local access_token
    access_token=$(get_dispatcharr_access_token)
    
    if [[ -z "$access_token" ]]; then
        return 1
    fi
    
    # Quick validation with version endpoint - DIRECT curl call to avoid circular dependency
    local response
    response=$(curl -s \
        --connect-timeout "${API_TIMEOUT:-10}" \
        --max-time 15 \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        "${DISPATCHARR_URL}/api/core/version/" 2>/dev/null)
    
    local curl_exit_code=$?
    
    # Check if curl succeeded and response is valid JSON
    if [[ $curl_exit_code -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        # Also check that it's not an error response
        if ! echo "$response" | jq -e '.detail // .error' >/dev/null 2>&1; then
            return 0  # Valid token
        fi
    fi
    
    return 1  # Invalid token
}

_dispatcharr_refresh_token() {
    # Get refresh token
    local refresh_token
    refresh_token=$(get_dispatcharr_access_token)  # This function should exist in auth.sh
    if [[ -z "$refresh_token" ]]; then
        # Try to get refresh token specifically
        refresh_token=$(jq -r '.refresh // empty' "$DISPATCHARR_TOKENS" 2>/dev/null)
    fi
    
    if [[ -z "$refresh_token" || "$refresh_token" == "null" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [AUTH-WARN] No refresh token available, performing full authentication" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
        _dispatcharr_full_authentication
        return $?
    fi
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [AUTH-INFO] Refreshing access token using refresh token" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
    
    # Perform refresh request
    local refresh_response
    refresh_response=$(curl -s \
        --connect-timeout ${STANDARD_TIMEOUT:-10} \
        --max-time ${MAX_OPERATION_TIME:-20} \
        -X POST \
        -H "Content-Type: application/json" \
        -d "{\"refresh\":\"$refresh_token\"}" \
        "${DISPATCHARR_URL}/api/accounts/token/refresh/" 2>&1)
    
    local curl_exit_code=$?
    
    # Handle network errors
    if [[ $curl_exit_code -ne 0 ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [AUTH-WARN] Network error during token refresh, falling back to full auth" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
        _dispatcharr_full_authentication
        return $?
    fi
    
    # Validate and process response
    if echo "$refresh_response" | jq -e '.access' >/dev/null 2>&1; then
        # Ensure token directory exists
        mkdir -p "$(dirname "${DISPATCHARR_TOKENS}")" 2>/dev/null
        
        # Update token file with new access token
        local temp_file="${DISPATCHARR_TOKENS}.tmp"
        if jq --argjson new_access "$refresh_response" \
            '. + {access: $new_access.access}' \
            "$DISPATCHARR_TOKENS" > "$temp_file" 2>/dev/null; then
            
            mv "$temp_file" "$DISPATCHARR_TOKENS"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - [AUTH-SUCCESS] Access token refreshed successfully" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
            DISPATCHARR_AUTH_STATE="authenticated"
            DISPATCHARR_LAST_TOKEN_CHECK=$(date +%s)
            return 0
        else
            rm -f "$temp_file"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - [AUTH-WARN] Failed to update token file, falling back to full auth" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
            _dispatcharr_full_authentication
            return $?
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [AUTH-WARN] Refresh token expired or invalid, performing full authentication" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
        _dispatcharr_full_authentication
        return $?
    fi
}

_dispatcharr_full_authentication() {
    # Validation checks
    if [[ -z "${DISPATCHARR_URL:-}" ]] || [[ "$DISPATCHARR_ENABLED" != "true" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [AUTH-ERROR] Dispatcharr not configured or disabled" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
        return 1
    fi
    
    if [[ -z "${DISPATCHARR_USERNAME:-}" ]] || [[ -z "${DISPATCHARR_PASSWORD:-}" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [AUTH-ERROR] Missing Dispatcharr credentials" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
        return 1
    fi
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [AUTH-INFO] Authenticating with Dispatcharr..." >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
    
    # Perform authentication request
    local token_response
    token_response=$(curl -s \
        --connect-timeout ${STANDARD_TIMEOUT:-10} \
        --max-time ${MAX_OPERATION_TIME:-20} \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"$DISPATCHARR_USERNAME\",\"password\":\"$DISPATCHARR_PASSWORD\"}" \
        "${DISPATCHARR_URL}/api/accounts/token/" 2>&1)
    
    local curl_exit_code=$?
    
    # Handle network errors
    if [[ $curl_exit_code -ne 0 ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [AUTH-ERROR] Network error during authentication (curl exit: $curl_exit_code)" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
        DISPATCHARR_AUTH_STATE="failed"
        return 1
    fi
    
    # Validate JSON response
    if ! echo "$token_response" | jq empty 2>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [AUTH-ERROR] Invalid response format from Dispatcharr auth endpoint" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
        DISPATCHARR_AUTH_STATE="failed"
        return 1
    fi
    
    # Check for successful authentication
    if echo "$token_response" | jq -e '.access' >/dev/null 2>&1; then
        # Ensure token directory exists
        mkdir -p "$(dirname "${DISPATCHARR_TOKENS}")" 2>/dev/null
        
        # Save tokens securely
        echo "$token_response" > "$DISPATCHARR_TOKENS"
        
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [AUTH-SUCCESS] Authentication successful" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
        DISPATCHARR_AUTH_STATE="authenticated"
        DISPATCHARR_LAST_TOKEN_CHECK=$(date +%s)
        
        return 0
    else
        # Extract error details
        local error_detail=$(echo "$token_response" | jq -r '.detail // .error // .message // "Authentication failed"' 2>/dev/null)
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [AUTH-ERROR] Authentication failed: $error_detail" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
        DISPATCHARR_AUTH_STATE="failed"
        return 1
    fi
}

_dispatcharr_get_access_token() {
    local token_file="$DISPATCHARR_TOKENS"
    
    if [[ ! -f "$token_file" ]]; then
        return 1
    fi
    
    local access_token=$(jq -r '.access // empty' "$token_file" 2>/dev/null)
    if [[ -n "$access_token" && "$access_token" != "null" ]]; then
        echo "$access_token"
        return 0
    fi
    
    return 1
}

_dispatcharr_get_refresh_token() {
    local token_file="$DISPATCHARR_TOKENS"
    
    if [[ ! -f "$token_file" ]]; then
        return 1
    fi
    
    local refresh_token=$(jq -r '.refresh // empty' "$token_file" 2>/dev/null)
    if [[ -n "$refresh_token" && "$refresh_token" != "null" ]]; then
        echo "$refresh_token"
        return 0
    fi
    
    return 1
}


# ============================================================================
# MODULE INITIALIZATION
# ============================================================================

# Initialize the module
dispatcharr_init_module() {
    if [[ "$DISPATCHARR_MODULE_INITIALIZED" == "true" ]]; then
        return 0
    fi
    
    # Initialize token path
    _dispatcharr_init_token_path
    
    DISPATCHARR_MODULE_INITIALIZED=true
    DISPATCHARR_LAST_TOKEN_VALIDATION=0
    
    return 0
}

# Auto-initialize when module is loaded
dispatcharr_init_module

# ============================================================================
# CONFIGURATION MANAGEMENT
# ============================================================================

# Save configuration change and refresh auth state
_dispatcharr_save_config() {
    local config_key="$1"
    local config_value="$2"
    local config_file="${CONFIG_FILE:-data/globalstationsearch.env}"
    
    # Validate required parameters
    if [[ -z "$config_key" ]]; then
        log_auth_error "save_dispatcharr_config: config_key required"
        return 1
    fi
    
    log_auth_info "Saving configuration: $config_key"
    
    # Use the main script's save_setting function if available
    if declare -f save_setting >/dev/null 2>&1; then
        save_setting "$config_key" "$config_value"
    else
        # Fallback: direct file manipulation
        if [[ -f "$config_file" ]]; then
            # Remove existing line and add new one
            sed -i.bak "/^$config_key=/d" "$config_file"
            echo "$config_key=\"$config_value\"" >> "$config_file"
        else
            log_auth_error "Config file not found: $config_file"
            return 1
        fi
    fi
    
    # Reload configuration
    reload_dispatcharr_config
    
    # Invalidate auth state since config changed
    invalidate_auth_state "Configuration changed: $config_key"
    
    return 0
}

# Reload configuration from file and refresh auth state
_dispatcharr_reload_config() {
    local config_file="${CONFIG_FILE:-data/globalstationsearch.env}"
    
    log_auth_info "Reloading configuration from: $config_file"
    
    if [[ -f "$config_file" ]]; then
        # Source the config file to reload variables
        source "$config_file" 2>/dev/null || {
            log_auth_warn "Failed to source config file: $config_file"
            return 1
        }
        
        log_auth_info "Configuration reloaded successfully"
        
        # Log current config state (without sensitive info)
        log_auth_debug "DISPATCHARR_ENABLED: ${DISPATCHARR_ENABLED:-unset}"
        log_auth_debug "DISPATCHARR_URL: ${DISPATCHARR_URL:-unset}"
        log_auth_debug "DISPATCHARR_USERNAME: ${DISPATCHARR_USERNAME:+***set***}"
        log_auth_debug "DISPATCHARR_PASSWORD: ${DISPATCHARR_PASSWORD:+***set***}"
        
        return 0
    else
        log_auth_warn "Config file not found: $config_file"
        return 1
    fi
}

# Update Dispatcharr URL and refresh
_dispatcharr_update_url() {
    local new_url="$1"
    
    if [[ -z "$new_url" ]]; then
        log_auth_error "update_dispatcharr_url: URL required"
        return 1
    fi
    
    # Validate URL format
    if [[ ! "$new_url" =~ ^https?:// ]]; then
        log_auth_error "Invalid URL format: $new_url"
        return 1
    fi
    
    log_auth_info "Updating Dispatcharr URL to: $new_url"
    
    # Save to config and reload
    save_dispatcharr_config "DISPATCHARR_URL" "$new_url"
    
    return $?
}

# Update Dispatcharr credentials and refresh
_dispatcharr_update_credentials() {
    local new_username="$1"
    local new_password="$2"
    
    if [[ -z "$new_username" || -z "$new_password" ]]; then
        log_auth_error "update_dispatcharr_credentials: username and password required"
        return 1
    fi
    
    log_auth_info "Updating Dispatcharr credentials for user: $new_username"
    
    # Save both credentials
    save_dispatcharr_config "DISPATCHARR_USERNAME" "$new_username"
    save_dispatcharr_config "DISPATCHARR_PASSWORD" "$new_password"
    
    return $?
}

# Enable/disable Dispatcharr integration
_dispatcharr_update_enabled() {
    local enabled="$1"
    
    if [[ "$enabled" != "true" && "$enabled" != "false" ]]; then
        log_auth_error "update_dispatcharr_enabled: value must be 'true' or 'false'"
        return 1
    fi
    
    log_auth_info "Setting DISPATCHARR_ENABLED to: $enabled"
    
    save_dispatcharr_config "DISPATCHARR_ENABLED" "$enabled"
    
    return $?
}

# ============================================================================
# API FUNCTIONS
# ============================================================================

# BASIC

# Get Dispatcharr version
dispatcharr_get_version() {
    local response
    response=$(dispatcharr_api_wrapper "GET" "/api/core/version/")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        echo "$response"
        return 0
    else
        _dispatcharr_log "error" "Failed to get version information"
        return 1
    fi
}

# Test Dispatcharr connection and authentication
dispatcharr_test_connection() {
    _dispatcharr_log "info" "Testing Dispatcharr connection and authentication"
    
    # Check basic configuration
    if [[ -z "${DISPATCHARR_URL:-}" ]] || [[ "$DISPATCHARR_ENABLED" != "true" ]]; then
        _dispatcharr_log "error" "Dispatcharr not configured or disabled"
        echo -e "${RED}❌ Dispatcharr: Not configured or disabled${RESET}" >&2
        echo -e "${CYAN}💡 Configure in Settings → Dispatcharr Integration${RESET}" >&2
        return 1
    fi
    
    # Test authentication
    if ! dispatcharr_ensure_valid_token; then
        _dispatcharr_log "error" "Authentication failed during connection test"
        echo -e "${RED}❌ Dispatcharr: Authentication failed${RESET}" >&2
        echo -e "${CYAN}💡 Check server URL, username, and password${RESET}" >&2
        return 1
    fi
    
    # Test API call
    local version_info
    version_info=$(dispatcharr_get_version)
    
    if [[ $? -eq 0 ]]; then
        local version=$(echo "$version_info" | jq -r '.version // "Unknown"' 2>/dev/null)
        _dispatcharr_log "info" "Connection test successful, server version: $version"
        echo -e "${GREEN}✅ Dispatcharr: Connection and authentication successful${RESET}" >&2
        echo -e "${CYAN}💡 Server version: $version${RESET}" >&2
        return 0
    else
        _dispatcharr_log "error" "Connection test failed - API call unsuccessful"
        echo -e "${RED}❌ Dispatcharr: Connection test failed${RESET}" >&2
        return 1
    fi
}

# CHANNELS

# Get all channels
dispatcharr_get_channels() {
    local search_term="$1"
    
    _dispatcharr_log "info" "Fetching channels from Dispatcharr"
    
    # Build endpoint with optional search parameter
    local endpoint="/api/channels/channels/"
    if [[ -n "$search_term" ]]; then
        # URL encode the search term  
        local encoded_search_term=$(printf '%s' "$search_term" | sed 's/ /%20/g; s/&/%26/g; s/#/%23/g')
        endpoint+="?search=$encoded_search_term"
        _dispatcharr_log "info" "Searching channels for: '$search_term'"
    fi
    
    local response
    response=$(dispatcharr_api_wrapper "GET" "$endpoint")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        # Channels endpoint returns direct array, not paginated response
        if [[ -n "$response" ]] && [[ "$response" != "[]" ]]; then
            local channel_count=$(echo "$response" | jq 'length' 2>/dev/null || echo "0")
            _dispatcharr_log "info" "Retrieved $channel_count channels successfully"
            echo "$response"
        else
            _dispatcharr_log "warn" "No channels found"
            echo "[]"
        fi
        return 0
    else
        _dispatcharr_log "error" "Failed to fetch channels from Dispatcharr"
        return 1
    fi
}

# Get and cache all channels from Dispatcharr
dispatcharr_get_and_cache_channels() {
    local search_term="${1:-}"  # Optional search parameter
    
    _dispatcharr_log "info" "Fetching and caching channels from Dispatcharr"
    
    local response
    response=$(dispatcharr_get_channels "$search_term")
    
    if [[ $? -eq 0 ]]; then
        # Cache the response
        echo "$response" > "$DISPATCHARR_CACHE"
        _dispatcharr_log "info" "Successfully cached channel data"
        echo "$response"
        return 0
    else
        _dispatcharr_log "error" "Failed to fetch channels for caching"
        return 1
    fi
}

# Get specific channel by ID from Dispatcharr
dispatcharr_get_channel() {
    local channel_id="$1"
    
    if [[ -z "$channel_id" ]]; then
        _dispatcharr_log "error" "Channel ID is required"
        return 1
    fi
    
    _dispatcharr_log "info" "Fetching channel $channel_id from Dispatcharr"
    
    local response
    response=$(dispatcharr_api_wrapper "GET" "/api/channels/channels/$channel_id/")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        # Verify we got a channel object with the expected ID
        local returned_id=$(echo "$response" | jq -r '.id // empty' 2>/dev/null)
        if [[ "$returned_id" == "$channel_id" ]]; then
            _dispatcharr_log "info" "Successfully retrieved channel $channel_id"
            echo "$response"
            return 0
        else
            _dispatcharr_log "error" "Channel ID mismatch: requested $channel_id, got $returned_id"
            return 1
        fi
    else
        _dispatcharr_log "error" "Failed to fetch channel $channel_id from Dispatcharr"
        return 1
    fi
}

# Update station ID
dispatcharr_update_channel_station_id() {
    local channel_id="$1"
    local station_id="$2"
    
    if [[ -z "$channel_id" || -z "$station_id" ]]; then
        _dispatcharr_log "error" "Channel ID and Station ID are required"
        return 1
    fi
    
    _dispatcharr_log "info" "Updating channel $channel_id with station ID: $station_id"
    
    # Prepare JSON payload
    local json_data
    json_data=$(jq -n --arg sid "$station_id" '{tvc_guide_stationid: $sid}')
    
    local response
    response=$(dispatcharr_api_wrapper "PATCH" "/api/channels/channels/$channel_id/" "$json_data")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        # Verify the update was successful
        local updated_station_id=$(echo "$response" | jq -r '.tvc_guide_stationid // empty' 2>/dev/null)
        if [[ "$updated_station_id" == "$station_id" ]]; then
            _dispatcharr_log "info" "Successfully updated channel $channel_id station ID to: $station_id"
            echo "$response"
            return 0
        else
            _dispatcharr_log "error" "Station ID update verification failed for channel $channel_id"
            return 1
        fi
    else
        _dispatcharr_log "error" "Failed to update channel $channel_id station ID"
        return 1
    fi
}

# Update channel with data
dispatcharr_update_channel() {
    local channel_id="$1"
    local update_data="$2"
    
    if [[ -z "$channel_id" || -z "$update_data" ]]; then
        _dispatcharr_log "error" "Channel ID and update data are required"
        return 1
    fi
    
    # Validate that update_data is valid JSON
    if ! echo "$update_data" | jq empty 2>/dev/null; then
        _dispatcharr_log "error" "Update data must be valid JSON"
        return 1
    fi
    
    _dispatcharr_log "info" "Updating channel $channel_id with data"
    
    local response
    response=$(dispatcharr_api_wrapper "PATCH" "/api/channels/channels/$channel_id/" "$update_data")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        # Verify the update was successful by checking returned ID
        local returned_id=$(echo "$response" | jq -r '.id // empty' 2>/dev/null)
        if [[ "$returned_id" == "$channel_id" ]]; then
            _dispatcharr_log "info" "Successfully updated channel $channel_id"
            echo "$response"
            return 0
        else
            _dispatcharr_log "error" "Channel update verification failed for channel $channel_id"
            return 1
        fi
    else
        _dispatcharr_log "error" "Failed to update channel $channel_id"
        return 1
    fi
}

# Find channels that are missing station IDs
dispatcharr_find_missing_station_ids() {
    local channels_data="$1"
    
    _dispatcharr_log "info" "Analyzing channels for missing station IDs"
    
    if [[ -z "$channels_data" ]]; then
        _dispatcharr_log "error" "No channel data provided for analysis"
        return 1
    fi
    
    # Extract missing channels and sort by channel number
    local missing_channels
    missing_channels=$(echo "$channels_data" | jq -r '
        .[] | 
        select((.tvc_guide_stationid // "") == "" or (.tvc_guide_stationid // "") == null) |
        [.id, .name, .channel_group_id // "Ungrouped", (.channel_number // 0)] | 
        @tsv
    ' 2>/dev/null | sort -t$'\t' -k4 -n)
    
    if [[ $? -eq 0 ]]; then
        local count=$(echo "$missing_channels" | wc -l)
        if [[ -n "$missing_channels" ]]; then
            _dispatcharr_log "info" "Found $count channels missing station IDs"
        else
            _dispatcharr_log "info" "No channels missing station IDs"
        fi
        echo "$missing_channels"
        return 0
    else
        _dispatcharr_log "error" "Failed to analyze channel data"
        return 1
    fi
}

#LOGOS

# Check if logo already exists in Dispatcharr (with local caching)
dispatcharr_check_existing_logo() {
    local logo_url="$1"
    
    if [[ -z "$logo_url" || "$logo_url" == "null" ]]; then
        _dispatcharr_log "debug" "No logo URL provided for existence check"
        return 1
    fi
    
    _dispatcharr_log "debug" "Checking for existing logo: $logo_url"
    
    # First check our local cache
    if [[ -f "$DISPATCHARR_LOGOS" ]]; then
        local cached_id=$(jq -r --arg url "$logo_url" '.[$url].id // empty' "$DISPATCHARR_LOGOS" 2>/dev/null)
        if [[ -n "$cached_id" && "$cached_id" != "null" ]]; then
            _dispatcharr_log "debug" "Found logo in local cache (ID: $cached_id)"
            echo "$cached_id"
            return 0
        fi
    fi
    
    # If not in local cache, query Dispatcharr API using modern API wrapper
    _dispatcharr_log "debug" "Logo not in cache, querying Dispatcharr API"
    local response
    response=$(dispatcharr_api_wrapper "GET" "/api/channels/logos/")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        local logo_id=$(echo "$response" | jq -r --arg url "$logo_url" \
            '.[] | select(.url == $url) | .id // empty' 2>/dev/null)
        
        if [[ -n "$logo_id" && "$logo_id" != "null" ]]; then
            # Cache this for future use
            local logo_name=$(echo "$response" | jq -r --arg url "$logo_url" \
                '.[] | select(.url == $url) | .name // "Unknown"' 2>/dev/null)
            
            _dispatcharr_log "info" "Found existing logo via API (ID: $logo_id) - caching locally"
            cache_dispatcharr_logo_info "$logo_url" "$logo_id" "$logo_name"
            echo "$logo_id"
            return 0
        else
            _dispatcharr_log "debug" "Logo not found in Dispatcharr"
            return 1
        fi
    else
        _dispatcharr_log "error" "Failed to query Dispatcharr logos API"
        return 1
    fi
}

# Download logo file from Dispatcharr to local file
dispatcharr_download_logo_file() {
    local logo_id="$1"
    local output_file="$2"
    
    if [[ -z "$logo_id" || -z "$output_file" ]]; then
        _dispatcharr_log "error" "Logo ID and output file path are required"
        return 1
    fi
    
    _dispatcharr_log "info" "Downloading logo $logo_id to $output_file"
    
    # Get logo information using documented API
    local logo_info
    logo_info=$(dispatcharr_api_wrapper "GET" "/api/channels/logos/$logo_id/")
    
    if [[ $? -ne 0 ]] || [[ -z "$logo_info" ]]; then
        _dispatcharr_log "error" "Failed to get logo info for ID $logo_id"
        return 1
    fi
    
    # Extract cache_url (preferred) or url from the response
    local download_url
    download_url=$(echo "$logo_info" | jq -r '.cache_url // .url // empty' 2>/dev/null)
    
    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        _dispatcharr_log "error" "No download URL found in logo info for ID $logo_id"
        return 1
    fi
    
    # Download directly from the URL (no auth needed for external URLs)
    local http_code
    http_code=$(curl -s \
        --connect-timeout "${API_TIMEOUT:-10}" \
        --max-time "${API_MAX_TIME:-30}" \
        -o "$output_file" \
        -w "%{http_code}" \
        "$download_url" 2>/dev/null)
    
    local curl_exit_code=$?
    
    # Handle curl errors
    if [[ $curl_exit_code -ne 0 ]]; then
        _dispatcharr_log "error" "Network error downloading logo from $download_url (curl exit: $curl_exit_code)"
        [[ -f "$output_file" ]] && rm -f "$output_file"
        return 1
    fi
    
    # Check HTTP status and validate image
    case "$http_code" in
        200)
            if [[ -f "$output_file" ]] && [[ -s "$output_file" ]]; then
                # Verify it's actually an image
                local mime_type=$(file --mime-type -b "$output_file" 2>/dev/null)
                if [[ "$mime_type" == image/* ]]; then
                    _dispatcharr_log "info" "Successfully downloaded logo $logo_id to $output_file"
                    return 0
                else
                    _dispatcharr_log "error" "Downloaded file is not an image (MIME: $mime_type)"
                    [[ -f "$output_file" ]] && rm -f "$output_file"
                    return 1
                fi
            else
                _dispatcharr_log "error" "Logo file download failed - empty or missing file"
                [[ -f "$output_file" ]] && rm -f "$output_file"
                return 1
            fi
            ;;
        404)
            _dispatcharr_log "error" "Logo file not found at URL: $download_url"
            [[ -f "$output_file" ]] && rm -f "$output_file"
            return 1
            ;;
        *)
            _dispatcharr_log "error" "HTTP error $http_code downloading logo from $download_url"
            [[ -f "$output_file" ]] && rm -f "$output_file"
            return 1
            ;;
    esac
}

# Cache logo information locally for faster future lookups
dispatcharr_cache_logo_info() {
    local logo_url="$1"
    local logo_id="$2"
    local logo_name="$3"
    
    if [[ -z "$logo_url" || -z "$logo_id" ]]; then
        _dispatcharr_log "error" "Logo URL and ID required for caching"
        return 1
    fi
    
    _dispatcharr_log "debug" "Caching logo info: ID=$logo_id, name=$logo_name"
    
    # Initialize cache file if needed
    if [[ ! -f "$DISPATCHARR_LOGOS" ]]; then
        echo '{}' > "$DISPATCHARR_LOGOS"
        _dispatcharr_log "debug" "Initialized logo cache file: $DISPATCHARR_LOGOS"
    fi
    
    # Add/update logo info in cache
    local temp_file="${DISPATCHARR_LOGOS}.tmp"
    jq --arg url "$logo_url" \
       --arg id "$logo_id" \
       --arg name "${logo_name:-Unknown}" \
       --arg timestamp "$(date -Iseconds)" \
       '. + {($url): {id: $id, name: $name, cached: $timestamp}}' \
       "$DISPATCHARR_LOGOS" > "$temp_file" 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        mv "$temp_file" "$DISPATCHARR_LOGOS"
        _dispatcharr_log "debug" "Successfully cached logo info for ID $logo_id"
        return 0
    else
        rm -f "$temp_file"
        _dispatcharr_log "error" "Failed to cache logo info for ID $logo_id"
        return 1
    fi
}

# Get specific logo by ID
dispatcharr_get_logo() {
    local logo_id="$1"
    
    if [[ -z "$logo_id" ]]; then
        _dispatcharr_log "error" "Logo ID is required"
        return 1
    fi
    
    _dispatcharr_log "info" "Fetching logo $logo_id from Dispatcharr"
    
    local response
    response=$(dispatcharr_api_wrapper "GET" "/api/channels/logos/$logo_id/")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        # Verify we got a logo object with the expected ID
        local returned_id=$(echo "$response" | jq -r '.id // empty' 2>/dev/null)
        if [[ "$returned_id" == "$logo_id" ]]; then
            _dispatcharr_log "info" "Successfully retrieved logo $logo_id"
            echo "$response"
            return 0
        else
            _dispatcharr_log "error" "Logo ID mismatch: requested $logo_id, got $returned_id"
            return 1
        fi
    else
        _dispatcharr_log "error" "Failed to fetch logo $logo_id from Dispatcharr"
        return 1
    fi
}

# Upload logo to Dispatcharr  
dispatcharr_upload_logo() {
    local station_name="$1"
    local logo_url="$2"
    
    if [[ -z "$station_name" || -z "$logo_url" ]]; then
        _dispatcharr_log "error" "Station name and logo URL are required"
        return 1
    fi
    
    _dispatcharr_log "info" "Uploading logo for station: $station_name from URL: $logo_url"
    
    # Prepare JSON payload for logo upload
    local json_data
    json_data=$(jq -n --arg name "$station_name" --arg url "$logo_url" '{
        name: $name,
        url: $url
    }')
    
    local response
    response=$(dispatcharr_api_wrapper "POST" "/api/channels/logos/" "$json_data")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        # Verify upload was successful by checking for ID in response
        local logo_id=$(echo "$response" | jq -r '.id // empty' 2>/dev/null)
        if [[ -n "$logo_id" && "$logo_id" != "null" ]]; then
            _dispatcharr_log "info" "Successfully uploaded logo for $station_name (ID: $logo_id)"
            echo "$response"
            return 0
        else
            _dispatcharr_log "error" "Logo upload verification failed - no ID returned"
            return 1
        fi
    else
        _dispatcharr_log "error" "Failed to upload logo for station: $station_name"
        return 1
    fi
}

# Upload station logo with caching and duplicate checking
dispatcharr_upload_station_logo() {
    local station_name="$1"
    local logo_url="$2"
    
    if [[ -z "$logo_url" || "$logo_url" == "null" ]]; then
        _dispatcharr_log "error" "No logo URL provided for station: $station_name"
        return 1
    fi
    
    _dispatcharr_log "info" "Processing logo upload for station: $station_name"
    
    # Check for existing logo first to avoid duplicates
    local existing_logo_id=$(check_existing_dispatcharr_logo "$logo_url")
    if [[ -n "$existing_logo_id" && "$existing_logo_id" != "null" ]]; then
        _dispatcharr_log "info" "Logo already exists for $station_name (ID: $existing_logo_id)"
        echo "$existing_logo_id"
        return 0
    fi
    
    # Upload new logo
    _dispatcharr_log "info" "Uploading new logo for $station_name from URL: $logo_url"
    local response
    response=$(dispatcharr_upload_logo "$station_name" "$logo_url")
    
    if [[ $? -eq 0 ]]; then
        local logo_id=$(echo "$response" | jq -r '.id')
        if [[ -n "$logo_id" && "$logo_id" != "null" ]]; then
            # Cache the logo info for future use
            cache_dispatcharr_logo_info "$logo_url" "$logo_id" "$station_name"
            _dispatcharr_log "info" "Successfully uploaded and cached logo for $station_name (ID: $logo_id)"
            echo "$logo_id"
            return 0
        else
            _dispatcharr_log "error" "Upload succeeded but no logo ID returned for $station_name"
            return 1
        fi
    else
        _dispatcharr_log "error" "Failed to upload logo for station: $station_name"
        return 1
    fi
}

# Delete logo from Dispatcharr
dispatcharr_delete_logo() {
    local logo_id="$1"
    
    if [[ -z "$logo_id" ]]; then
        _dispatcharr_log "error" "Logo ID is required"
        return 1
    fi
    
    _dispatcharr_log "info" "Deleting logo $logo_id from Dispatcharr"
    
    local response
    response=$(dispatcharr_api_wrapper "DELETE" "/api/channels/logos/$logo_id/")
    
    # DELETE requests typically return 204 No Content on success
    if [[ $? -eq 0 ]]; then
        _dispatcharr_log "info" "Successfully deleted logo $logo_id"
        return 0
    else
        _dispatcharr_log "error" "Failed to delete logo $logo_id from Dispatcharr"
        return 1
    fi
}

# Clean up old entries from logo cache (removes entries older than 30 days)
dispatcharr_cleanup_logo_cache() {
    _dispatcharr_log "info" "Starting logo cache cleanup"
    
    if [[ ! -f "$DISPATCHARR_LOGOS" ]]; then
        _dispatcharr_log "debug" "No logo cache file found - nothing to clean"
        return 0
    fi
    
    local cache_size_before=$(jq 'length' "$DISPATCHARR_LOGOS" 2>/dev/null || echo "0")
    _dispatcharr_log "debug" "Logo cache contains $cache_size_before entries before cleanup"
    
    # Cross-platform date calculation (30 days ago)
    local cutoff_date
    cutoff_date=$(date -d '30 days ago' -Iseconds 2>/dev/null || date -v-30d -Iseconds 2>/dev/null)
    
    if [[ -z "$cutoff_date" ]]; then
        _dispatcharr_log "error" "Failed to calculate cutoff date for cache cleanup"
        return 1
    fi
    
    _dispatcharr_log "debug" "Removing logo cache entries older than: $cutoff_date"
    
    # Remove entries older than cutoff date
    local temp_file="${DISPATCHARR_LOGOS}.tmp"
    jq --arg cutoff "$cutoff_date" \
        'to_entries | map(select(.value.cached >= $cutoff)) | from_entries' \
        "$DISPATCHARR_LOGOS" > "$temp_file" 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        mv "$temp_file" "$DISPATCHARR_LOGOS"
        local cache_size_after=$(jq 'length' "$DISPATCHARR_LOGOS" 2>/dev/null || echo "0")
        local removed_count=$((cache_size_before - cache_size_after))
        
        _dispatcharr_log "info" "Logo cache cleanup completed: removed $removed_count entries, $cache_size_after entries remaining"
        return 0
    else
        rm -f "$temp_file"
        _dispatcharr_log "error" "Failed to process logo cache cleanup"
        return 1
    fi
}

# GROUPS

# Get all channel groups from Dispatcharr
dispatcharr_get_groups() {
    _dispatcharr_log "info" "Fetching channel groups from Dispatcharr"
    
    local response
    response=$(dispatcharr_api_wrapper "GET" "/api/channels/groups/")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        # Handle both direct array and paginated response
        local results=$(echo "$response" | jq -r '.results // . // empty' 2>/dev/null)
        if [[ -n "$results" ]] && [[ "$results" != "[]" ]]; then
            local group_count=$(echo "$results" | jq 'length' 2>/dev/null || echo "0")
            _dispatcharr_log "info" "Retrieved $group_count channel groups successfully"
            echo "$results"
        else
            _dispatcharr_log "warn" "No channel groups found"
            echo "[]"
        fi
        return 0
    else
        _dispatcharr_log "error" "Failed to fetch channel groups from Dispatcharr"
        return 1
    fi
}

# ============================================================================
# ENHANCED ERROR HANDLING AND LOGGING
# ============================================================================

# Module-specific logging function
_dispatcharr_log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Use existing auth logging if available, otherwise basic logging
    if declare -f log_auth_${level} >/dev/null 2>&1; then
        log_auth_${level} "[DISPATCHARR] $message"
    else
        echo "[$timestamp] [${level^^}] [DISPATCHARR] $message" >&2
    fi
}

# ============================================================================
# WORKFLOWS
# ============================================================================

# Apply queued station ID matches from file to Dispatcharr channels
dispatcharr_apply_station_id_matches() {
  _dispatcharr_log "info" "Starting batch station ID application workflow"
  
  echo -e "\n${BOLD}${BLUE}📍 Step 3 of 3: Commit Station ID Changes${RESET}"
  echo -e "${CYAN}This will apply all queued station ID matches to your Dispatcharr channels.${RESET}"
  echo
  
  if [[ ! -f "$DISPATCHARR_MATCHES" ]] || [[ ! -s "$DISPATCHARR_MATCHES" ]]; then
    echo -e "${YELLOW}⚠️  No pending station ID matches found${RESET}"
    echo -e "${CYAN}💡 Run 'Interactive Station ID Matching' first to create matches${RESET}"
    echo -e "${CYAN}💡 Ensure you selected 'Batch Mode' during the matching process${RESET}"
    _dispatcharr_log "warn" "No pending station ID matches found in $DISPATCHARR_MATCHES"
    return 1
  fi
  
  local total_matches
  total_matches=$(wc -l < "$DISPATCHARR_MATCHES")
  
  _dispatcharr_log "info" "Found $total_matches pending station ID matches to process"
  echo -e "${GREEN}✅ Found $total_matches pending station ID matches${RESET}"
  echo
  
  # Show enhanced preview of matches with better formatting
  echo -e "${BOLD}${CYAN}=== Pending Station ID Matches ===${RESET}"
  echo -e "${YELLOW}Preview of changes that will be applied to Dispatcharr:${RESET}"
  echo
  printf "${BOLD}${YELLOW}%-8s %-25s %-12s %-20s %s${RESET}\n" "Ch ID" "Channel Name" "Station ID" "Station Name" "Quality"
  echo "--------------------------------------------------------------------------------"
  
  local line_count=0
  while IFS=$'\t' read -r channel_id channel_name station_id station_name confidence; do
    # Get quality info for the station
    local quality=$(get_station_quality "$station_id")
    
    # Format row with proper alignment
    printf "%-8s %-25s " "$channel_id" "${channel_name:0:25}"
    echo -n -e "${CYAN}${station_id}${RESET}"
    printf "%*s" $((12 - ${#station_id})) ""
    printf "%-20s " "${station_name:0:20}"
    echo -e "${GREEN}${quality}${RESET}"
    
    ((line_count++))
    # Show only first 10 for preview
    [[ $line_count -ge 10 ]] && break
  done < "$DISPATCHARR_MATCHES"
  
  if [[ $total_matches -gt 10 ]]; then
    echo -e "${CYAN}... and $((total_matches - 10)) more matches${RESET}"
  fi
  echo
  
  echo -e "${BOLD}Confirmation Required:${RESET}"
  echo -e "Total matches to apply: ${YELLOW}$total_matches${RESET}"
  echo -e "Target: ${CYAN}Dispatcharr at $DISPATCHARR_URL${RESET}"
  echo -e "Action: ${GREEN}Set station IDs for channel EPG matching${RESET}"
  echo
  
  if ! confirm_action "Apply all $total_matches station ID matches to Dispatcharr?"; then
    echo -e "${YELLOW}⚠️  Batch update cancelled${RESET}"
    echo -e "${CYAN}💡 Matches remain queued - you can commit them later${RESET}"
    _dispatcharr_log "info" "Batch update cancelled by user"
    return 1
  fi
  
  local success_count=0
  local failure_count=0
  local current_item=0

  echo -e "\n${BOLD}${CYAN}=== Applying Station ID Updates ===${RESET}"
  echo -e "${CYAN}🔄 Processing $total_matches updates to Dispatcharr...${RESET}"
  echo
  
  while IFS=$'\t' read -r channel_id channel_name station_id station_name confidence; do
    # Skip empty lines
    [[ -z "$channel_id" ]] && continue
    
    ((current_item++))
    local percent=$((current_item * 100 / total_matches))
    
    # Show progress with channel info
    printf "\r${CYAN}[%3d%%] (%d/%d) Updating: %-25s → %-12s${RESET}" \
      "$percent" "$current_item" "$total_matches" "${channel_name:0:25}" "$station_id"
    
    if dispatcharr_update_channel_station_id "$channel_id" "$station_id"; then
      ((success_count++))
    else
      ((failure_count++))
      echo -e "\n${RED}❌ Failed: $channel_name (ID: $channel_id)${RESET}"
    fi
  done < "$DISPATCHARR_MATCHES"
  
  # Clear progress line
  echo
  echo
  
  # Show comprehensive completion summary
  echo -e "${BOLD}${GREEN}=== Batch Update Results ===${RESET}"
  echo -e "${GREEN}✅ Successfully applied: $success_count station IDs${RESET}"
  
  if [[ $failure_count -gt 0 ]]; then
    echo -e "${RED}❌ Failed to apply: $failure_count station IDs${RESET}"
    echo -e "${CYAN}💡 Check Dispatcharr logs for failed update details${RESET}"
  fi
  
  echo -e "${CYAN}📊 Total processed: $((success_count + failure_count)) of $total_matches${RESET}"
  echo
  
  if [[ $success_count -gt 0 ]]; then
    echo -e "${BOLD}${CYAN}Next Steps:${RESET}"
    echo -e "• Changes are now active in Dispatcharr"
    echo -e "• Channels will use station IDs for EPG matching"
    echo -e "• Consider using 'Populate Other Dispatcharr Fields' to enhance remaining data"
    
    if [[ $failure_count -eq 0 ]]; then
      echo -e "${GREEN}💡 Perfect! All station IDs applied successfully${RESET}"
    fi
  fi
  
  # Clear processed matches
  echo
  echo -e "${CYAN}🧹 Clearing processed matches from queue...${RESET}"
  > "$DISPATCHARR_MATCHES"
  echo -e "${GREEN}✅ Match queue cleared${RESET}"
  
  _dispatcharr_log "info" "Batch station ID application completed: $success_count successful, $failure_count failed"
  
  return 0
}

# ============================================================================
# LEGACY COMPATIBILITY WRAPPERS
# ============================================================================
# These functions provide backwards compatibility with existing code.
# TODO: Eventually update all calling code to use the core functions directly
# and remove these wrappers for a cleaner API.

update_dispatcharr_channel_epg() {
    local channel_id="$1"
    local station_id="$2"
    dispatcharr_update_channel_station_id "$channel_id" "$station_id"
}

authenticate_dispatcharr() {
    _dispatcharr_full_authentication
}

refresh_dispatcharr_access_token() {
    _dispatcharr_refresh_token
}

is_dispatcharr_authenticated() {
    # Delegate to JIT system instead of managing state locally
    dispatcharr_test_connection >/dev/null 2>&1
}

ensure_dispatcharr_auth() {
    dispatcharr_ensure_valid_token
}

get_dispatcharr_access_token() {
    _dispatcharr_get_access_token "$@";
}

get_dispatcharr_refresh_token() {
    _dispatcharr_get_refresh_token "$@";
}

save_dispatcharr_config() {
    _dispatcharr_save_config "$@";
}

reload_dispatcharr_config() {
    _dispatcharr_reload_config "$@";
}

update_dispatcharr_url() {
    _dispatcharr_update_url "$@";
}

update_dispatcharr_credentials() {
    _dispatcharr_update_credentials "$@";
}

update_dispatcharr_enabled() {
    _dispatcharr_update_enabled "$@";
}

batch_update_stationids() {
    dispatcharr_apply_station_id_matches "$@"
}

get_and_cache_dispatcharr_channels() {
    dispatcharr_get_and_cache_channels "$@"
}

find_channels_missing_stationid() {
    dispatcharr_find_missing_station_ids "$@"
}

upload_station_logo_to_dispatcharr() {
    dispatcharr_upload_station_logo "$@"
}

check_existing_dispatcharr_logo() {
    dispatcharr_check_existing_logo "$@"
}

cache_dispatcharr_logo_info() {
    dispatcharr_cache_logo_info "$@"
}

cleanup_dispatcharr_logo_cache() {
    dispatcharr_cleanup_logo_cache "$@"
}