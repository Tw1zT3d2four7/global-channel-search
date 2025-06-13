#!/bin/bash

# === UI Display Functions ===
# Consolidated display, status, and formatting functions
# Extracted from main script to reduce duplication

# ============================================================================
# CORE DISPLAY UTILITIES
# ============================================================================

# Generic status indicator formatter
format_status_indicator() {
    local status="$1"
    local item="$2"
    local detail="${3:-}"
    
    case "$status" in
        "success"|"ok"|"enabled"|"active")
            echo -e "${GREEN}✅ $item${RESET}${detail:+ ($detail)}"
            ;;
        "warning"|"missing"|"disabled")
            echo -e "${YELLOW}⚠️  $item${RESET}${detail:+ ($detail)}"
            ;;
        "error"|"failed"|"not_found")
            echo -e "${RED}❌ $item${RESET}${detail:+ ($detail)}"
            ;;
        "info"|"note")
            echo -e "${CYAN}💡 $item${RESET}${detail:+ ($detail)}"
            ;;
        *)
            echo -e "${CYAN}$item${RESET}${detail:+ ($detail)}"
            ;;
    esac
}

# Generic table header formatter
format_table_header() {
    local title="$1"
    shift
    local columns=("$@")
    
    echo -e "${BOLD}${BLUE}=== $title ===${RESET}"
    
    # Build header row
    local header_format=""
    local separator=""
    for col in "${columns[@]}"; do
        header_format+="%-20s "
        separator+="--------------------"
    done
    
    printf "${BOLD}${YELLOW}${header_format}${RESET}\n" "${columns[@]}"
    echo "$separator"
}

# ============================================================================
# UNIFIED STATUS DISPLAY SYSTEM
# ============================================================================

# Main system status display (consolidates show_system_status)
show_unified_system_status() {
    local context="${1:-normal}"  # normal, detailed, summary
    local debug_trace=${DEBUG_CACHE_TRACE:-false}
    
    if [ "$debug_trace" = true ]; then
        echo -e "${CYAN}[TRACE] show_unified_system_status($context) called${RESET}" >&2
    fi
    
    # Get core metrics once
    local breakdown=$(get_stations_breakdown)
    local base_count=$(echo "$breakdown" | cut -d' ' -f1)
    local user_count=$(echo "$breakdown" | cut -d' ' -f2)
    local total_count=$(get_total_stations_count "$context")
    
    # Ensure total_count is valid
    if ! [[ "$total_count" =~ ^[0-9]+$ ]]; then
        total_count=0
    fi
    
    # Station Database Status
    _show_database_status "$base_count" "$user_count" "$total_count"
    
    # Market Configuration (only in detailed mode)
    if [[ "$context" == "detailed" ]]; then
        _show_market_status
    fi
    
    # Integration Status  
    _show_integration_status
    
    echo
}

# Private: Database status section
_show_database_status() {
    local base_count="$1"
    local user_count="$2" 
    local total_count="$3"
    
    if [ "$base_count" -gt 0 ]; then
        format_status_indicator "success" "Base Station Database: $base_count stations" "USA, CAN, and GBR coverage"
    else
        format_status_indicator "warning" "Base Station Database: Not found"
    fi
    
    # User market configuration
    local market_count=0
    if [ -f "$CSV_FILE" ]; then
        market_count=$(awk 'END {print NR-1}' "$CSV_FILE" 2>/dev/null || echo "0")
        if [ "$market_count" -gt 0 ]; then
            echo -e "📍 User Markets Configured: $market_count"
        else
            format_status_indicator "warning" "User Markets Configured: 0" "no custom markets"
        fi
    else
        format_status_indicator "warning" "User Markets Configured: 0" "no custom markets"
    fi
    
    if [ "$user_count" -gt 0 ]; then
        format_status_indicator "success" "User Station Database: $user_count stations"
    else
        format_status_indicator "warning" "User Station Database: No custom stations"
    fi
    
    echo -e "${CYAN}📊 Total Available Stations: $total_count${RESET}"
    
    # Search capability status
    if [ "$total_count" -gt 0 ]; then
        format_status_indicator "success" "Local Database Search: Available with full features"
    else
        format_status_indicator "error" "Local Database Search: No station data available"
    fi
}

# Private: Integration status section
_show_integration_status() {
    # Channels DVR Integration
    if [[ -n "${CHANNELS_URL:-}" ]]; then
        if curl -s --connect-timeout 2 "$CHANNELS_URL" >/dev/null 2>&1; then
            format_status_indicator "success" "Channels DVR Integration: Connected" "$CHANNELS_URL"
        else
            format_status_indicator "error" "Channels DVR Integration: Connection Failed" "$CHANNELS_URL"
        fi
    else
        format_status_indicator "warning" "Channels DVR Integration: Not configured" "optional"
    fi
    
    # Dispatcharr Integration  
    if [[ "$DISPATCHARR_ENABLED" == "true" ]]; then
        if dispatcharr_test_connection 2>/dev/null; then
            format_status_indicator "success" "Dispatcharr Integration: Connected" "$DISPATCHARR_URL"
        else
            format_status_indicator "error" "Dispatcharr Integration: Connection Failed" "$DISPATCHARR_URL"
        fi
    else
        format_status_indicator "warning" "Dispatcharr Integration: Disabled"
    fi
}

# Private: Market status section (detailed mode only)
_show_market_status() {
    if [ ! -f "$CSV_FILE" ]; then
        return 0
    fi
    
    echo -e "${BOLD}${BLUE}Market Status:${RESET}"
    
    local total_markets=$(awk 'END {print NR-1}' "$CSV_FILE" 2>/dev/null || echo "0")
    local cached_markets=0
    local base_cache_markets=0
    local pending_markets=0
    
    # CORRECT WAY: Count markets from CSV, not from state file
    if [ "$total_markets" -gt 0 ]; then
        while IFS=, read -r country zip; do
            [[ "$country" == "Country" ]] && continue
            
            if is_market_cached "$country" "$zip"; then
                ((cached_markets++))
            elif is_market_in_base_cache "$country" "$zip" 2>/dev/null; then
                ((base_cache_markets++))
            else
                ((pending_markets++))
            fi
        done < "$CSV_FILE"
    fi
    
    echo -e "${CYAN}📊 Total configured: $total_markets${RESET}"
    echo -e "${CYAN}📊 User cached: $cached_markets${RESET}"
    echo -e "${CYAN}📊 Base covered: $base_cache_markets${RESET}"
    echo -e "${CYAN}📊 Pending: $pending_markets${RESET}"
    
    # Verification
    local total_counted=$((cached_markets + base_cache_markets + pending_markets))
    if [ "$total_counted" -ne "$total_markets" ]; then
        echo -e "${RED}⚠️  Market count verification failed${RESET}"
    fi
}

# ============================================================================
# CACHE STATISTICS DISPLAY
# ============================================================================

# Unified cache statistics (consolidates display_cache_statistics + show_cache_state_stats)
show_unified_cache_stats() {
    local detail_level="${1:-summary}"  # summary, detailed, debug
    
    echo -e "${BOLD}${BLUE}Cache Statistics:${RESET}"
    
    # Core cache breakdown
    _show_cache_breakdown
    
    # Additional file information
    _show_cache_files "$detail_level"
    
    # State tracking info
    if [[ "$detail_level" != "summary" ]]; then
        _show_state_tracking_stats
    fi
    
    echo
}

# Private: Core cache breakdown
_show_cache_breakdown() {
    local breakdown=$(get_stations_breakdown)
    local base_count=$(echo "$breakdown" | cut -d' ' -f1)
    local user_count=$(echo "$breakdown" | cut -d' ' -f2)  
    local total_count=$(get_total_stations_count)
    
    if [ "$base_count" -gt 0 ]; then
        echo "Base Stations: $base_count"
    else
        echo "Base Stations: 0 (not found)"
    fi
    
    if [ "$user_count" -gt 0 ]; then
        echo "User Stations: $user_count"
    else
        echo "User Stations: 0 (none added)"
    fi
    
    echo "Total Available: $total_count"
}

# Private: Cache files information
_show_cache_files() {
    local detail_level="$1"
    
    [ -f "$LINEUP_CACHE" ] && echo "Lineups: $(wc -l < "$LINEUP_CACHE" 2>/dev/null || echo "0")"
    [ -d "$LOGO_DIR" ] && echo "Logos cached: $(find "$LOGO_DIR" -name "*.png" 2>/dev/null | wc -l)"
    [ -f "$API_SEARCH_RESULTS" ] && echo "API search results: $(wc -l < "$API_SEARCH_RESULTS" 2>/dev/null || echo "0") entries"
    echo "Total cache size: $(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1 || echo "unknown")"
}

# Private: State tracking statistics  
_show_state_tracking_stats() {
    if [ -f "$CACHED_MARKETS" ] && [ -s "$CACHED_MARKETS" ]; then
        local cached_market_count=$(jq -s 'length' "$CACHED_MARKETS" 2>/dev/null || echo "0")
        echo "Cached Markets: $cached_market_count"
        
        # Show breakdown by country
        if command -v jq >/dev/null 2>&1; then
            local countries=$(jq -s '.[] | .country' "$CACHED_MARKETS" 2>/dev/null | sort | uniq -c | sort -rn)
            if [ -n "$countries" ]; then
                echo "  By Country:"
                echo "$countries" | while read -r count country; do
                    if [ -n "$country" ] && [ "$country" != "null" ] && [ "$country" != '""' ]; then
                        country=$(echo "$country" | tr -d '"')
                        echo "    $country: $count markets"
                    fi
                done
            fi
        fi
    else
        echo "Cached Markets: 0"
    fi
    
    if [ -f "$CACHED_LINEUPS" ] && [ -s "$CACHED_LINEUPS" ]; then
        local cached_lineup_count=$(jq -s 'length' "$CACHED_LINEUPS" 2>/dev/null || echo "0")
        echo "Cached Lineups: $cached_lineup_count"
        
        if command -v jq >/dev/null 2>&1; then
            local total_stations=$(jq -s '.[] | .stations_found' "$CACHED_LINEUPS" 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
            echo "  Total Stations (pre-dedup): $total_stations"
        fi
    else
        echo "Cached Lineups: 0"
    fi
    
    # Show last update
    if [ -f "$CACHE_STATE_LOG" ] && [ -s "$CACHE_STATE_LOG" ]; then
        local last_update=$(tail -1 "$CACHE_STATE_LOG" 2>/dev/null | cut -d' ' -f1-2)
        if [ -n "$last_update" ]; then
            echo "Last Cache Update: $last_update"
        fi
    fi
}