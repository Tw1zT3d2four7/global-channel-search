#!/bin/bash

# ============================================================================
# DISPATCHARR AUTHENTICATION MODULE
# ============================================================================
# Pure authentication management for Dispatcharr JWT tokens
# Handles token lifecycle, refresh logic, and authentication state

# ============================================================================
# AUTHENTICATION STATE TRACKING
# ============================================================================

# EMBY AUTHENTICATION STATE TRACKING
EMBY_AUTH_STATE="unknown"      # unknown, authenticated, failed
EMBY_LAST_TOKEN_CHECK=0        # Last successful auth check timestamp
EMBY_TOKEN_CHECK_INTERVAL=300  # 5 minutes between forced checks

# ============================================================================
# LOGGING FUNCTIONS (shared with emby and dispatcharr before, but dispatcharr has its own now)
# ============================================================================

# Authentication logging helpers
log_auth_error() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [AUTH-ERROR] $message" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
}

log_auth_warn() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [AUTH-WARN] $message" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
}

log_auth_success() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [AUTH-SUCCESS] $message" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
}

log_auth_info() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [AUTH-INFO] $message" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
}

log_auth_debug() {
    local message="$1"
    if [[ "${DEBUG_AUTH:-false}" == "true" ]]; then
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[$timestamp] [AUTH-DEBUG] $message" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
    fi
}

# ============================================================================
# EMBY CONFIGURATION MANAGEMENT
# ============================================================================

# Save Emby configuration change and refresh auth state
save_emby_config() {
    local config_key="$1"
    local config_value="$2"
    local config_file="${CONFIG_FILE:-data/globalstationsearch.env}"
    
    # Validate required parameters
    if [[ -z "$config_key" ]]; then
        log_auth_error "save_emby_config: config_key required"
        return 1
    fi
    
    log_auth_info "Saving Emby configuration: $config_key"
    
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
    reload_emby_config
    
    # Invalidate auth state since config changed
    invalidate_emby_auth_state "Configuration changed: $config_key"
    
    return 0
}

# Reload Emby configuration from file and refresh auth state
reload_emby_config() {
    local config_file="${CONFIG_FILE:-data/globalstationsearch.env}"
    
    log_auth_info "Reloading Emby configuration from: $config_file"
    
    if [[ -f "$config_file" ]]; then
        # Source the config file to reload variables
        source "$config_file" 2>/dev/null || {
            log_auth_warn "Failed to source config file: $config_file"
            return 1
        }
        
        log_auth_info "Emby configuration reloaded successfully"
        
        # Log current config state (without sensitive info)
        log_auth_debug "EMBY_ENABLED: ${EMBY_ENABLED:-unset}"
        log_auth_debug "EMBY_URL: ${EMBY_URL:-unset}"
        log_auth_debug "EMBY_USERNAME: ${EMBY_USERNAME:+***set***}"
        log_auth_debug "EMBY_API_KEY: ${EMBY_API_KEY:+***set***}"
        
        return 0
    else
        log_auth_warn "Config file not found: $config_file"
        return 1
    fi
}

# Invalidate Emby authentication state when config changes
invalidate_emby_auth_state() {
    local reason="${1:-Configuration changed}"
    
    log_auth_info "Invalidating Emby auth state: $reason"
    
    # Reset auth state variables
    EMBY_AUTH_STATE="unknown"
    EMBY_LAST_TOKEN_CHECK=0
    
    log_auth_info "Emby auth state invalidated - will re-authenticate on next API call"
}

# ============================================================================
# EMBY CORE AUTHENTICATION FUNCTIONS
# ============================================================================

# Authenticate with Emby server using username/password
authenticate_emby() {
    if [[ -z "${EMBY_URL:-}" ]] || [[ "$EMBY_ENABLED" != "true" ]]; then
        log_auth_error "Emby not configured or disabled"
        return 1
    fi
    
    if [[ -z "${EMBY_USERNAME:-}" ]] || [[ -z "${EMBY_PASSWORD:-}" ]]; then
        log_auth_error "Missing Emby credentials"
        return 1
    fi
    
    log_auth_info "Authenticating with Emby server..."
    
    # Emby authentication endpoint
    local auth_response
    auth_response=$(curl -s \
        --connect-timeout ${STANDARD_TIMEOUT:-10} \
        --max-time ${MAX_OPERATION_TIME:-20} \
        -H "Content-Type: application/json" \
        -H "X-Emby-Authorization: MediaBrowser Client=\"GlobalStationSearch\", Device=\"Script\", DeviceId=\"gss-$(hostname)\", Version=\"1.0\"" \
        -d "{\"Username\":\"$EMBY_USERNAME\",\"Pw\":\"$EMBY_PASSWORD\"}" \
        "${EMBY_URL}/emby/Users/AuthenticateByName" 2>&1)
    
    local curl_exit_code=$?
    
    # Handle network errors
    if [[ $curl_exit_code -ne 0 ]]; then
        log_auth_error "Network error during Emby authentication (curl exit: $curl_exit_code)"
        EMBY_AUTH_STATE="failed"
        return 1
    fi
    
    # Validate JSON response and extract access token
    if echo "$auth_response" | jq empty 2>/dev/null; then
        local access_token=$(echo "$auth_response" | jq -r '.AccessToken // empty' 2>/dev/null)
        local user_id=$(echo "$auth_response" | jq -r '.User.Id // empty' 2>/dev/null)
        
        if [[ -n "$access_token" && -n "$user_id" ]]; then
            log_auth_success "Emby authentication successful"
            
            # Store the API key (access token) for future use
            save_emby_config "EMBY_API_KEY" "$access_token"
            save_emby_config "EMBY_USER_ID" "$user_id"
            
            EMBY_AUTH_STATE="authenticated"
            EMBY_LAST_TOKEN_CHECK=$(date +%s)
            return 0
        else
            log_auth_error "Invalid Emby authentication response - missing token or user ID"
            EMBY_AUTH_STATE="failed"
            return 1
        fi
    else
        log_auth_error "Invalid Emby authentication response - not valid JSON"
        EMBY_AUTH_STATE="failed"
        return 1
    fi
}

# Check if current Emby authentication is valid
is_emby_authenticated() {
    if [[ -z "${EMBY_URL:-}" ]] || [[ "$EMBY_ENABLED" != "true" ]]; then
        return 1
    fi
    
    if [[ -z "${EMBY_API_KEY:-}" ]]; then
        return 1
    fi
    
    local now=$(date +%s)
    
    # Check if we need to revalidate
    if (( now - EMBY_LAST_TOKEN_CHECK > EMBY_TOKEN_CHECK_INTERVAL )); then
        log_auth_info "Validating Emby authentication..."
        
        # Test current API key with a simple endpoint
        local test_response
        test_response=$(curl -s \
            --connect-timeout ${QUICK_TIMEOUT:-5} \
            -H "X-Emby-Token: $EMBY_API_KEY" \
            "${EMBY_URL}/emby/System/Info" 2>/dev/null)
        
        if echo "$test_response" | jq empty 2>/dev/null; then
            log_auth_info "Emby authentication validated successfully"
            EMBY_AUTH_STATE="authenticated"
            EMBY_LAST_TOKEN_CHECK=$now
            return 0
        else
            log_auth_warn "Current Emby API key is invalid or expired"
            EMBY_AUTH_STATE="failed"
            return 1
        fi
    else
        # Recent check was successful
        return 0
    fi
}

# Ensure we have valid Emby authentication
ensure_emby_auth() {
    # First check current state
    if is_emby_authenticated; then
        return 0
    fi
    
    # Try full authentication
    log_auth_info "Emby authentication needed, attempting authentication..."
    if authenticate_emby; then
        return 0
    fi
    
    # Authentication failed
    log_auth_error "Emby authentication failed"
    EMBY_AUTH_STATE="failed"
    return 1
}

# Get Emby authentication status for display
get_emby_auth_status() {
    if [[ -z "${EMBY_URL:-}" ]] || [[ "$EMBY_ENABLED" != "true" ]]; then
        echo "⚠️ Emby not configured or disabled"
        return 1
    fi
    
    case "$EMBY_AUTH_STATE" in
        "authenticated")
            echo "✅ Authenticated"
            return 0
            ;;
        "failed")
            echo "❌ Authentication failed"
            return 1
            ;;
        *)
            if is_emby_authenticated; then
                echo "✅ Authenticated"
                return 0
            else
                echo "⚠️ Authentication status unknown"
                return 1
            fi
            ;;
    esac
}