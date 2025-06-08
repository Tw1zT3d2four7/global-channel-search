#!/bin/bash

# === Global Station Search ===
# Description: Television station search tool using Channels DVR API
# dispatcharr integration for direct field population from search results
# Created: 2025/05/26
VERSION="2.0.4"
VERSION_INFO="Last Modified: 2025/06/06
Patch (2.0.4)
• Bugfixes

Patch (2.0.3)
• Definitive fix of Emby integration

Patch (2.0.1)
• Fixed emby API calls
• Fixed module loading order/dependency chain 

MAJOR RELEASE (2.0.0)
• All data from any previous version must be deleted as it is no longer backward
  compatible
• Added multi-country filtering support and lineup tracing when caching is performed
• Emby integration to populate necessary lineupIds for all channels in m3u playlist
• Significant enhacnements to codebase

Improvements (1.4.5)
• Moved all dispatcharr auth functions to lib/core/auth.sh
  - This allows background token refresh without incrementing interactions
    or requiring user input
• Move all API calls to lib/core/api.sh
• Option to select a specific channel from the 'scan for missing station IDs'
• Addid lib/features/update.sh to manage in-script update management, including 
  update check on startup (or at user-defined intervals)

Patch (1.4.2)
• Removed unused channel parsing fields (language, confidence)
  These were intended for future update but broke core functionality

Patch (1.4.1)
• Fixed issues with first time setup
• Fixed some poor regex
• Fixed terminal style formatting
• Clear all automatically applied filters if user enters their own search term 
  in Dispatcharr matching 

MAJOR RELEASE (1.4.0)
• New modular script framework with many functions moved to subcscripts in lib/ folder
• New filesystem layout
• Channels DVR API search was broken - fixed
• User caching was broken - fixed

Previous Versions:
• 1.3.3 - New menu system, improved regex logic, better Dispatcharr integration
• 1.2.0 - Major base cache overhaul, better user cache handling
• 1.1.0 - Added comprehensive local base cache
• 1.0.0 - Initial release with Dispatcharr integration

System Requirements:
• Required: jq, curl, bash 4.0+
• Optional: viu (logo previews), bc (progress calculations)
• Integration: Channels DVR server (optional), Dispatcharr (optional)

Quick Start:
1. Run: ./globalstationsearch.sh
2. Use 'Search Local Database' for immediate access
3. Use 'Dispatcharr Integration' for automated Dispatcharr field population
3. Add custom markets via 'Manage Television Markets' (optional)
4. Configure integrations in 'Settings' (optional)"

check_version_flags() {
  case "${1:-}" in
    --version|-v)
      echo "Global Station Search v$VERSION"
      exit 0
      ;;
    --version-info|--info)
      show_version_info
      exit 0
      ;;
    --help|-h)
      show_usage_help
      exit 0
      ;;
  esac
}

show_version_info() {
  echo -e "${BOLD}${CYAN}=== Global Station Search v$VERSION ===${RESET}"
  echo "$VERSION_INFO"
}

show_usage_help() {
  echo -e "${BOLD}${CYAN}Global Station Search v$VERSION${RESET}"
  echo "Television station search tool with optional Dispatcharr and Channels DVR integration"
  echo
  echo -e "${BOLD}Usage:${RESET}"
  echo "  ./globalstationsearch.sh [options]"
  echo
  echo -e "${BOLD}Options:${RESET}"
  echo "  -h, --help         Show this help message"
  echo "  -v, --version      Show version number only"
  echo "      --version-info Show detailed version information"
  echo
  echo -e "${BOLD}Key Features:${RESET}"
  echo "• ${GREEN}Local Database Search${RESET} - Search thousands of stations instantly"
  echo "• ${GREEN}User Cache Expansion${RESET} - Add custom markets to your database (requires Channels DVR server)"
  echo "• ${GREEN}Dispatcharr Integration${RESET} - Automated channel field population in Dispatcharr"
  echo "  - Station ID assignment with smart matching"
  echo "  - Logo upload and channel name updates"
  echo "  - TVG-ID (call sign) population"
  echo "• ${GREEN}Channels DVR Integration${RESET} - Direct API search"
  echo "• ${GREEN}Reverse Station Lookup${RESET} - Get detailed info from station IDs"
  echo
  echo -e "${BOLD}Quick Start Guide:${RESET}"
  echo "1. ${CYAN}First Run${RESET}: Script will guide you through initial setup"
  echo "2. ${CYAN}Immediate Use${RESET}: Try 'Search Local Database' (works out of the box)"
  echo "3. ${CYAN}Integration${RESET}: Use 'Dispatcharr Integration' for channel management"
  echo "4. ${CYAN}Customization${RESET}: Configure servers and filters in 'Settings'"
  echo "5. ${CYAN}Expansion${RESET}: Add custom markets via 'Manage Television Markets' (requires CHannels DVR server)"
  echo
  echo -e "${BOLD}Getting Help:${RESET}"
  echo "• Run without options for interactive menus with built-in guidance"
  echo "• Check 'Developer Information' in Settings for technical details"
  echo "• All operations include help text and examples"
}

if [[ -z "${TERM:-}" ]]; then
    export TERM="xterm"
fi

# ============================================================================
# TERMINAL STYLING
# ============================================================================
ESC="\033"
RESET="${ESC}[0m"
BOLD="${ESC}[1m"
UNDERLINE="${ESC}[4m"
YELLOW="${ESC}[33m"
GREEN="${ESC}[32m"
RED="${ESC}[31m"
CYAN="${ESC}[36m"
BLUE="${ESC}[34m"

# ============================================================================
# CONSTANTS
# ============================================================================

# Pagination settings
readonly DEFAULT_RESULTS_PER_PAGE=10
readonly DEFAULT_CHANNELS_PER_PAGE=10
readonly MAX_RESULTS_PER_PAGE=20

# Network timeout settings (seconds)
readonly QUICK_TIMEOUT=5        # For quick connection tests
readonly STANDARD_TIMEOUT=10    # For standard API calls
readonly EXTENDED_TIMEOUT=15    # For complex operations
readonly MAX_OPERATION_TIME=20  # Maximum time for single operation
readonly DOWNLOAD_TIMEOUT=30    # For file downloads

# ============================================================================
# FILES AND DIRECTORIES
# ============================================================================

# TOP LEVEL DIRECTORIES
DATA_DIR="data"
CACHE_DIR="cache"

# CONFIGURATION
CONFIG_FILE="$DATA_DIR/globalstationsearch.env"

# SUBDIRECTORIES
LOGS_DIR="$DATA_DIR/logs"
USER_CACHE_DIR="$DATA_DIR/user_cache"
BACKUP_DIR="$DATA_DIR/backups"
LOGO_DIR="$CACHE_DIR/logos"
STATION_CACHE_DIR="$CACHE_DIR/stations"

# INPUT FILES
USER_MARKETS_CSV="$DATA_DIR/sampled_markets_user.csv"    # User's configured markets
BASE_MARKETS_CSV="$DATA_DIR/sampled_markets_base.csv"    # Base cache source markets (distributed)
CSV_FILE="$USER_MARKETS_CSV"  # Primary reference for user operations
VALID_CODES_FILE="$DATA_DIR/valid_country_codes.txt"

# CACHE FILES
LINEUP_CACHE="$CACHE_DIR/all_lineups.jsonl"

# MODERN TWO-FILE CACHE SYSTEM
BASE_STATIONS_JSON="all_stations_base.json"        # Distributed base cache (script directory)
USER_STATIONS_JSON="$USER_CACHE_DIR/all_stations_user.json"     # User's custom additions
COMBINED_STATIONS_JSON="$CACHE_DIR/all_stations_combined.json"  # Runtime combination

# CACHE STATE TRACKING FILES
CACHED_MARKETS="$USER_CACHE_DIR/cached_markets.jsonl"
CACHED_LINEUPS="$USER_CACHE_DIR/cached_lineups.jsonl"
LINEUP_TO_MARKET="$USER_CACHE_DIR/lineup_to_market.json"
CACHE_STATE_LOG="$LOGS_DIR/cache_state.log"

# SEARCH RESULT FILES
API_SEARCH_RESULTS="$CACHE_DIR/api_search_results.tsv"
SEARCH_RESULTS="$CACHE_DIR/search_results.tsv"

# DISPATCHARR INTEGRATION FILES
DISPATCHARR_CACHE="$CACHE_DIR/dispatcharr_channels.json"
DISPATCHARR_MATCHES="$CACHE_DIR/dispatcharr_matches.tsv"
DISPATCHARR_LOG="$LOGS_DIR/dispatcharr_operations.log"        # FIXED: Moved to logs directory
DISPATCHARR_TOKENS="$CACHE_DIR/dispatcharr_tokens.json"
DISPATCHARR_LOGOS="$CACHE_DIR/dispatcharr_logos.json"

# TEMPORARY FILES
TEMP_CONFIG="${CONFIG_FILE}.tmp"                              # FIXED: Simplified temp file naming

# ============================================================================
# LOAD CORE MODULES
# ============================================================================

# Universal module loader function
load_module() {
    local module_path="$1"
    local module_description="$2"
    local required="${3:-true}"
    
    if [[ -f "$module_path" ]]; then
        if source "$module_path"; then
            return 0
        else
            echo -e "${RED}❌ Failed to source: $module_path${RESET}" >&2
            echo -e "${CYAN}💡 Module loaded but contains errors${RESET}" >&2
            [[ "$required" == "true" ]] && exit 1 || return 1
        fi
    else
        echo -e "${RED}❌ Module not found: $module_path${RESET}" >&2
        echo -e "${CYAN}💡 Description: $module_description${RESET}" >&2
        
        if [[ "$required" == "true" ]]; then
            echo -e "${CYAN}💡 Please ensure the lib/ directory structure is present${RESET}" >&2
            exit 1
        else
            return 1
        fi
    fi
}

load_essential_modules() {
    local essential_modules=(
        "lib/core/utils.sh|Core Utility Functions|true"
        "lib/core/config.sh|Configuration Management|true"
    )
    
    echo -e "${CYAN}📦 Loading essential modules...${RESET}" >&2

    for module_info in "${essential_modules[@]}"; do
        IFS='|' read -r module_path module_desc required <<< "$module_info"
        load_module "$module_path" "$module_desc" "$required"
    done
    
    echo -e "${GREEN}✅ Essential modules loaded successfully${RESET}" >&2
}

load_remaining_modules() {
    local remaining_modules=(
        "lib/ui/display.sh|UI Display Framework|true"
        "lib/core/settings.sh|Settings Configuration|true"
        "lib/ui/menus.sh|Menu Framework|true"
        "lib/core/channel_parsing.sh|Channel Name Parsing|true"
        "lib/core/cache.sh|Cache Management Module|true"
        "lib/core/auth.sh|Authentication Management|true"
        "lib/core/api.sh|API Functions|true"
        "lib/core/backup.sh|Unified Backup System|true"       
        "lib/features/update.sh|Auto-Update System|true"
    )
    
    echo -e "${CYAN}📦 Loading remaining modules...${RESET}" >&2

    for module_info in "${remaining_modules[@]}"; do
        IFS='|' read -r module_path module_desc required <<< "$module_info"
        load_module "$module_path" "$module_desc" "$required"
    done
    
    echo -e "${GREEN}✅ All remaining modules loaded successfully${RESET}" >&2
}

# ============================================================================
# CONFIGURATION & SETUP FUNCTIONS
# ============================================================================

check_dependency() {
  local cmd="$1"
  local required="$2"
  local install_hint="$3"
  
  if ! command -v "$cmd" &> /dev/null; then
    if [[ "$required" == "true" ]]; then
      echo -e "${RED}❌ Missing required dependency: $cmd${RESET}"
      echo "$install_hint"
      exit 1
    else
      echo -e "${YELLOW}⚠️ Missing optional dependency: $cmd${RESET}"
      echo "$install_hint"
      return 1
    fi
  fi
  return 0
}

check_dependencies() {
  check_dependency "jq" "true" "Install with: sudo apt-get install jq (Ubuntu/Debian) or brew install jq (macOS)"
  check_dependency "curl" "true" "Install with: sudo apt-get install curl (Ubuntu/Debian) or brew install curl (macOS)"

  # Check for optional viu dependency for logo previews
  if check_dependency "viu" "false" "viu is not installed, logo previews disabled. Install with: cargo install viu"; then
    echo -e "${CYAN}💡 Logo previews available - enable in Settings if desired${RESET}"
  else
    echo -e "${CYAN}💡 To enable logo previews: install viu with 'cargo install viu'${RESET}"
  fi

  # Note: SHOW_LOGOS setting is managed through Settings menu, not overridden here
}

setup_directories() {
  # Create new organized directory structure
  local directories=(
    "$DATA_DIR"
    "$CACHE_DIR"
    "$USER_CACHE_DIR" 
    "$BACKUP_DIR"
    "$LOGS_DIR"
    "$STATION_CACHE_DIR"
    "$LOGO_DIR"
    "$BACKUP_DIR/config_backups"
    "$BACKUP_DIR/cache_backups" 
    "$BACKUP_DIR/export_backups"
  )
  
  for dir in "${directories[@]}"; do
    mkdir -p "$dir" || {
      echo -e "${RED}Error: Cannot create directory: $dir${RESET}"
      exit 1
    }
  done

  # Download country codes if needed (now in data directory)
  if [ ! -f "$VALID_CODES_FILE" ]; then
    echo "Downloading valid country codes..."
    
    if curl -s --connect-timeout $STANDARD_TIMEOUT --max-time $DOWNLOAD_TIMEOUT \
        "https://raw.githubusercontent.com/lukes/ISO-3166-Countries-with-Regional-Codes/master/all/all.json" \
        | jq -r '.[]."alpha-3"' \
        | sort -u > "$VALID_CODES_FILE" 2>/dev/null; then
      echo -e "${GREEN}✅ Country codes downloaded successfully${RESET}"
    else
      echo -e "${YELLOW}⚠️  Failed to download country codes, using fallback list${RESET}"
      echo -e "USA\nCAN\nGBR\nAUS\nDEU\nFRA\nJPN\nITA\nESP\nNLD" > "$VALID_CODES_FILE"
    fi
  fi
}

# ============================================================================
# CACHE FRESHNESS CHECKING
# ============================================================================

check_combined_cache_freshness() {
  # If combined cache doesn't exist, needs rebuild
  if [ ! -f "$COMBINED_STATIONS_JSON" ]; then
    COMBINED_CACHE_VALID=false
    return 1
  fi
  
  # Get current timestamps of source files
  local base_time=0
  local user_time=0
  local combined_time=0
  
  if [ -f "$BASE_STATIONS_JSON" ]; then
    base_time=$(stat -c %Y "$BASE_STATIONS_JSON" 2>/dev/null || stat -f %m "$BASE_STATIONS_JSON" 2>/dev/null || echo "0")
  fi
  
  if [ -f "$USER_STATIONS_JSON" ]; then
    user_time=$(stat -c %Y "$USER_STATIONS_JSON" 2>/dev/null || stat -f %m "$USER_STATIONS_JSON" 2>/dev/null || echo "0")
  fi
  
  combined_time=$(stat -c %Y "$COMBINED_STATIONS_JSON" 2>/dev/null || stat -f %m "$COMBINED_STATIONS_JSON" 2>/dev/null || echo "0")
  
  # Load saved state from config
  local saved_state=$(load_combined_cache_state)
  IFS='|' read -r saved_combined_time saved_base_time saved_user_time <<< "$saved_state"
  
  # Check if cache is valid based on multiple criteria
  local cache_valid=false
  
  # Method 1: File timestamps (traditional method)
  if [ "$combined_time" -gt "$base_time" ] && [ "$combined_time" -gt "$user_time" ]; then
    cache_valid=true
  fi
  
  # Method 2: Saved state comparison (more reliable across restarts)
  if [ "$saved_combined_time" != "0" ] && 
     [ "$saved_base_time" = "$base_time" ] && 
     [ "$saved_user_time" = "$user_time" ] && 
     [ -f "$COMBINED_STATIONS_JSON" ]; then
    cache_valid=true
    combined_time="$saved_combined_time"  # Use saved timestamp
  fi
  
  if [ "$cache_valid" = true ]; then
    COMBINED_CACHE_VALID=true
    COMBINED_CACHE_TIMESTAMP="$combined_time"
    return 0
  else
    COMBINED_CACHE_VALID=false
    return 1
  fi
}

# ============================================================================
# CACHE CLEANUP
# ============================================================================

cleanup_combined_cache() {
  if [ -f "$COMBINED_STATIONS_JSON" ]; then
    rm -f "$COMBINED_STATIONS_JSON" 2>/dev/null || true
  fi
  COMBINED_CACHE_VALID=false
  COMBINED_CACHE_TIMESTAMP=0
}

# ============================================================================
# DATABASE STATUS FUNCTIONS
# ============================================================================

has_stations_database() {
  local context="${1:-normal}"
  
  case "$context" in
    "startup"|"menu"|"status")
      has_stations_database_fast
      ;;
    *)
      # Full check for actual operations
      local effective_file
      effective_file=$(get_effective_stations_file 2>/dev/null)
      return $?
      ;;
  esac
}

has_stations_database_fast() {
  # Check if any individual cache exists
  if [ -f "$BASE_STATIONS_JSON" ] && [ -s "$BASE_STATIONS_JSON" ]; then
    return 0
  fi
  
  if [ -f "$USER_STATIONS_JSON" ] && [ -s "$USER_STATIONS_JSON" ]; then
    return 0
  fi
  
  return 1
}

get_total_stations_count() {
  local context="${1:-normal}"
  local debug_trace=${DEBUG_CACHE_TRACE:-false}
  
  if [ "$debug_trace" = true ]; then
    echo -e "${CYAN}[TRACE] get_total_stations_count($context) called${RESET}" >&2
  fi
  
  case "$context" in
    "startup"|"menu"|"status")
      # Use fast count for menu display, avoiding cache rebuilds
      get_total_stations_count_fast
      ;;
    *)
      # Full merge for actual operations
      local effective_file
      effective_file=$(get_effective_stations_file 2>/dev/null)
      if [ $? -eq 0 ] && [ -f "$effective_file" ]; then
        local count=$(jq 'length' "$effective_file" 2>/dev/null || echo "0")
        if [ "$debug_trace" = true ]; then
          echo -e "${CYAN}[TRACE] Full count from $effective_file: $count${RESET}" >&2
        fi
        echo "$count"
      else
        if [ "$debug_trace" = true ]; then
          echo -e "${RED}[TRACE] No effective file found, returning 0${RESET}" >&2
        fi
        echo "0"
      fi
      ;;
  esac
}

get_total_stations_count_fast() {
  local debug_trace=${DEBUG_CACHE_TRACE:-false}
  
  if [ "$debug_trace" = true ]; then
    echo -e "${CYAN}[TRACE] get_total_stations_count_fast() called${RESET}" >&2
  fi
  
  # If we have a valid combined cache, use it (no rebuild)
  if [ "$COMBINED_CACHE_VALID" = "true" ] && [ -f "$COMBINED_STATIONS_JSON" ]; then
    local count=$(jq 'length' "$COMBINED_STATIONS_JSON" 2>/dev/null || echo "0")
    if [ "$debug_trace" = true ]; then
      echo -e "${GREEN}[TRACE] Using valid combined cache: $count${RESET}" >&2
    fi
    echo "$count"
    return 0
  fi
  
  # Check if combined cache exists and is readable without triggering rebuild
  if [ -f "$COMBINED_STATIONS_JSON" ]; then
    local count=$(jq 'length' "$COMBINED_STATIONS_JSON" 2>/dev/null || echo "0")
    if [ "$count" != "0" ]; then
      if [ "$debug_trace" = true ]; then
        echo -e "${CYAN}[TRACE] Using existing combined cache: $count${RESET}" >&2
      fi
      echo "$count"
      return 0
    fi
  fi
  
  # Otherwise, estimate without triggering a merge
  local base_count=0
  local user_count=0
  
  if [ -f "$BASE_STATIONS_JSON" ] && [ -s "$BASE_STATIONS_JSON" ]; then
    base_count=$(jq 'length' "$BASE_STATIONS_JSON" 2>/dev/null || echo "0")
  fi
  
  if [ -f "$USER_STATIONS_JSON" ] && [ -s "$USER_STATIONS_JSON" ]; then
    user_count=$(jq 'length' "$USER_STATIONS_JSON" 2>/dev/null || echo "0")
  fi
  
  local total=$((base_count + user_count))
  
  if [ "$debug_trace" = true ]; then
    echo -e "${YELLOW}[TRACE] Estimated count (no merge): base=$base_count + user=$user_count = $total${RESET}" >&2
  fi
  
  # Return sum (slight overestimate due to potential duplicates, but avoids rebuild)
  echo "$total"
}

get_stations_breakdown() {
  local debug_trace=${DEBUG_CACHE_TRACE:-false}
  local base_count=0
  local user_count=0
  
  if [ "$debug_trace" = true ]; then
    echo -e "${CYAN}[TRACE] get_stations_breakdown() called${RESET}" >&2
  fi
  
  # Get counts directly from files without triggering merges
  if [ -f "$BASE_STATIONS_JSON" ] && [ -s "$BASE_STATIONS_JSON" ]; then
    base_count=$(jq 'length' "$BASE_STATIONS_JSON" 2>/dev/null || echo "0")
  fi
  
  if [ -f "$USER_STATIONS_JSON" ] && [ -s "$USER_STATIONS_JSON" ]; then
    user_count=$(jq 'length' "$USER_STATIONS_JSON" 2>/dev/null || echo "0")
  fi
  
  if [ "$debug_trace" = true ]; then
    echo -e "${CYAN}[TRACE] Breakdown: base=$base_count user=$user_count${RESET}" >&2
  fi
  
  echo "$base_count $user_count"
}

# ============================================================================
# CACHE STATE TRACKING FUNCTIONS
# ============================================================================

init_cache_state_tracking() {
  touch "$CACHED_MARKETS" "$CACHED_LINEUPS"
  
  # Initialize lineup-to-market mapping as empty JSON object
  if [ ! -f "$LINEUP_TO_MARKET" ]; then
    echo '{}' > "$LINEUP_TO_MARKET"
  fi
  
  # Create state log if it doesn't exist
  touch "$CACHE_STATE_LOG"
}

record_market_processed() {
  local country="$1"
  local zip="$2"
  local lineups_found="$3"
  local timestamp=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
  
  # Create JSONL entry - make sure it's a single line
  local market_record
  market_record=$(jq -n -c \
    --arg country "$country" \
    --arg zip "$zip" \
    --arg timestamp "$timestamp" \
    --argjson lineups_found "$lineups_found" \
    '{
      country: $country,
      zip: $zip, 
      timestamp: $timestamp,
      lineups_found: $lineups_found
    }')
  
  # Remove duplicates first
  if [ -f "$CACHED_MARKETS" ] && [ -s "$CACHED_MARKETS" ]; then
    grep -v "\"country\":\"$country\".*\"zip\":\"$zip\"" "$CACHED_MARKETS" > "${CACHED_MARKETS}.tmp" || touch "${CACHED_MARKETS}.tmp"
    mv "${CACHED_MARKETS}.tmp" "$CACHED_MARKETS"
  fi
  
  # Add new entry as a single line
  echo "$market_record" >> "$CACHED_MARKETS"
}

record_lineup_processed() {
  local lineup_id="$1"
  local country="$2"
  local zip="$3"
  local stations_found="$4"
  local timestamp=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
  
  # Create JSONL entry for this lineup
  local lineup_record=$(jq -n \
    --arg lineup_id "$lineup_id" \
    --arg timestamp "$timestamp" \
    --argjson stations_found "$stations_found" \
    '{
      lineup_id: $lineup_id,
      timestamp: $timestamp,
      stations_found: $stations_found
    }')
  
  # Remove any existing entry for this lineup
  if [ -f "$CACHED_LINEUPS" ]; then
    grep -v "\"lineup_id\":\"$lineup_id\"" "$CACHED_LINEUPS" > "$CACHED_LINEUPS.tmp" 2>/dev/null || true
    mv "$CACHED_LINEUPS.tmp" "$CACHED_LINEUPS"
  fi
  
  # Add new entry
  echo "$lineup_record" >> "$CACHED_LINEUPS"
  
  # Update lineup-to-market mapping
  local temp_mapping="${LINEUP_TO_MARKET}.tmp"
  jq --arg lineup "$lineup_id" \
     --arg country "$country" \
     --arg zip "$zip" \
     '. + {($lineup): {country: $country, zip: $zip}}' \
     "$LINEUP_TO_MARKET" > "$temp_mapping" 2>/dev/null
  
  if [ $? -eq 0 ]; then
    mv "$temp_mapping" "$LINEUP_TO_MARKET"
  else
    rm -f "$temp_mapping"
  fi
  
  # Log the action
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Recorded lineup: $lineup_id from $country/$zip ($stations_found stations)" >> "$CACHE_STATE_LOG"
}

is_market_cached() {
  local country="$1"
  local zip="$2"
  
  if [ ! -f "$CACHED_MARKETS" ] || [ ! -s "$CACHED_MARKETS" ]; then
    return 1
  fi
  
  # Count matching records (handles duplicates gracefully)
  local count
  count=$(jq --arg country "$country" --arg zip "$zip" \
    'select(.country == $country and .zip == $zip)' \
    "$CACHED_MARKETS" 2>/dev/null | wc -l)
  
  # If count is a valid number and > 0, market is cached
  if [[ "$count" =~ ^[0-9]+$ ]] && [[ "$count" -gt 0 ]]; then
    return 0
  else
    return 1
  fi
}

is_lineup_cached() {
  local lineup_id="$1"
  
  if [ ! -f "$CACHED_LINEUPS" ]; then
    return 1  # Not cached (file doesn't exist)
  fi
  
  grep -q "\"lineup_id\":\"$lineup_id\"" "$CACHED_LINEUPS" 2>/dev/null
}

get_unprocessed_markets() {
  if [ ! -f "$CSV_FILE" ] || [ ! -s "$CSV_FILE" ]; then
    return 1
  fi
  
  # If no cache state exists, all markets are unprocessed
  if [ ! -f "$CACHED_MARKETS" ]; then
    tail -n +2 "$CSV_FILE"  # Skip header
    return 0
  fi
  
  # Compare CSV against cached markets, accounting for base cache coverage
  tail -n +2 "$CSV_FILE" | while IFS=, read -r country zip; do
    # Skip if already processed in user cache
    if is_market_cached "$country" "$zip"; then
      continue
    fi
    
    # Include market for processing (base cache filtering happens elsewhere)
    echo "$country,$zip"
  done
}

refresh_market_display() {
  echo -e "${CYAN}🔄 Refreshing market status display...${RESET}"
  
  # Clear any cached state in the manage_markets function
  # Force re-read of state files
  if [ -f "$CACHED_MARKETS" ]; then
    echo -e "${GREEN}✅ State file exists with $(jq -s 'length' "$CACHED_MARKETS" 2>/dev/null || echo "0") entries${RESET}"
  else
    echo -e "${YELLOW}⚠️  State file missing - creating minimal state${RESET}"
    > "$CACHED_MARKETS"
  fi
  
  echo -e "${GREEN}✅ Market display refreshed${RESET}"
}

# ============================================================================
# RESULTS FILTERING
# ============================================================================

build_resolution_filter() {
  local runtime_resolution="${1:-}"  # Optional runtime override
  
  # Use runtime resolution if provided, otherwise use configured filter
  if [[ -n "$runtime_resolution" ]]; then
    echo "and (.videoQuality.videoType // \"\" | . == \"$runtime_resolution\")"
  elif [ "$FILTER_BY_RESOLUTION" = "true" ]; then
    local filter_conditions=""
    IFS=',' read -ra RESOLUTIONS <<< "$ENABLED_RESOLUTIONS"
    for res in "${RESOLUTIONS[@]}"; do
      if [ -n "$filter_conditions" ]; then
        filter_conditions+=" or "
      fi
      filter_conditions+="(.videoQuality.videoType // \"\" | . == \"$res\")"
    done
    echo "and ($filter_conditions)"
  else
    echo ""
  fi
}

build_country_filter() {
  local runtime_country="${1:-}"  # Optional runtime override
  
  # Use runtime country if provided, otherwise use configured filter
  if [[ -n "$runtime_country" ]]; then
    echo "and (.availableIn[]? // \"\" | . == \"$runtime_country\")"
  elif [ "$FILTER_BY_COUNTRY" = "true" ] && [ -n "$ENABLED_COUNTRIES" ]; then
    local filter_conditions=""
    IFS=',' read -ra COUNTRIES <<< "$ENABLED_COUNTRIES"
    for country in "${COUNTRIES[@]}"; do
      if [ -n "$filter_conditions" ]; then
        filter_conditions+=" or "
      fi
      filter_conditions+="(.availableIn[]? // \"\" | . == \"$country\")"
    done
    echo "and ($filter_conditions)"
  else
    echo ""
  fi
}

get_available_countries() {
  local debug_trace=${DEBUG_COUNTRY_FILTER:-false}
  
  if [ "$debug_trace" = true ]; then
    echo -e "${CYAN}[DEBUG] get_available_countries() - extracting from availableIn arrays${RESET}" >&2
  fi
  
  # Get countries from availableIn arrays instead of legacy country field
  local stations_file
  if stations_file=$(get_effective_stations_file 2>/dev/null); then
    if [ "$debug_trace" = true ]; then
      echo -e "${CYAN}[DEBUG] Using stations file: $stations_file${RESET}" >&2
    fi
    
    local countries
    countries=$(jq -r '[.[] | .availableIn[]? // empty | select(. != "")] | unique | join(",")' "$stations_file" 2>/dev/null)
    
    if [[ -n "$countries" && "$countries" != "null" && "$countries" != "" ]]; then
      if [ "$debug_trace" = true ]; then
        echo -e "${CYAN}[DEBUG] Found countries from arrays: $countries${RESET}" >&2
      fi
      echo "$countries"
      return 0
    else
      if [ "$debug_trace" = true ]; then
        echo -e "${CYAN}[DEBUG] No countries found in availableIn arrays${RESET}" >&2
      fi
      echo ""
      return 1
    fi
  else
    if [ "$debug_trace" = true ]; then
      echo -e "${CYAN}[DEBUG] No effective stations file available${RESET}" >&2
    fi
    echo ""
    return 1
  fi
}

# ============================================================================
# SEARCH FUNCTIONS
# ============================================================================

shared_station_search() {
  local search_term="$1"
  local page="${2:-1}"
  local output_format="${3:-tsv}"     # "tsv", "count", or "full"
  local runtime_country="${4:-}"      # For future channel name parsing
  local runtime_resolution="${5:-}"   # For future channel name parsing
  local results_per_page=$DEFAULT_RESULTS_PER_PAGE
  
  local start_index=$(( (page - 1) * results_per_page ))
  
  # Get effective stations file (same source for all searches)
  local stations_file
  stations_file=$(get_effective_stations_file)
  if [ $? -ne 0 ]; then
    if [[ "$output_format" == "count" ]]; then
      echo "0"
    fi
    return 1
  fi
  
  # Escape special regex characters for safety (same as local search)
  local escaped_term=$(echo "$search_term" | sed 's/[[\.*^$()+?{|]/\\&/g')
  
  # Build filters with runtime override capability (for future parsing)
  local resolution_filter=$(build_resolution_filter "$runtime_resolution")
  local country_filter=$(build_country_filter "$runtime_country")
  
  # Core search logic - identical for all callers
  if [[ "$output_format" == "count" ]]; then
    # Return count only
    jq -r --arg term "$escaped_term" --arg exact_term "$search_term" '
      [.[] | select(
        ((.name // "" | test($term; "i")) or
         (.callSign // "" | test($term; "i")) or
         (.name // "" | . == $exact_term) or
         (.callSign // "" | . == $exact_term))
        '"$resolution_filter"'
        '"$country_filter"'
      )] | length
    ' "$stations_file" 2>/dev/null || echo "0"
  elif [[ "$output_format" == "tsv" ]]; then
    # Return paginated TSV results (for Dispatcharr tables)
    jq -r --arg term "$escaped_term" --arg exact_term "$search_term" --argjson start "$start_index" --argjson limit "$results_per_page" '
      [.[] | select(
        ((.name // "" | test($term; "i")) or
         (.callSign // "" | test($term; "i")) or
         (.name // "" | . == $exact_term) or
         (.callSign // "" | . == $exact_term))
        '"$resolution_filter"'
        '"$country_filter"'
      )] | .[$start:($start + $limit)][] | 
      (.stationId // "") + "\t" + 
      (.name // "") + "\t" + 
      (.callSign // "") + "\t" + 
      ((.availableIn // []) | if length > 1 then join(",") else .[0] // "UNK" end)
    ' "$stations_file" 2>/dev/null
  else
    # Return full JSON results (for local search display)
    jq -r --arg term "$escaped_term" --arg exact_term "$search_term" --argjson start "$start_index" --argjson limit "$results_per_page" '
      [.[] | select(
        ((.name // "" | test($term; "i")) or
         (.callSign // "" | test($term; "i")) or
         (.name // "" | . == $exact_term) or
         (.callSign // "" | . == $exact_term))
        '"$resolution_filter"'
        '"$country_filter"'
      )] | .[$start:($start + $limit)][] | 
      [.name, .callSign, (.videoQuality.videoType // "Unknown"), .stationId, ((.availableIn // []) | if length > 1 then join(",") else .[0] // "UNK" end)] | @tsv
    ' "$stations_file" 2>/dev/null
  fi
}

get_station_quality() {
  local station_id="$1"
  
  # Get effective stations file
  local stations_file
  stations_file=$(get_effective_stations_file)
  if [ $? -ne 0 ]; then
    echo "Unknown"
    return 1
  fi
  
  # Extract quality for this station
  local quality=$(jq -r --arg id "$station_id" \
    '.[] | select(.stationId == $id) | .videoQuality.videoType // "Unknown"' \
    "$stations_file" 2>/dev/null | head -n 1)
  
  echo "${quality:-Unknown}"
}

display_logo() {
  local stid="$1"
  local logo_file="$LOGO_DIR/${stid}.png"
  
  if [[ "$SHOW_LOGOS" == true ]]; then
    if [[ ! -f "$logo_file" ]]; then
      # Get effective stations file for logo lookup
      local stations_file
      stations_file=$(get_effective_stations_file)
      if [ $? -eq 0 ]; then
        local logo_url=$(jq -r --arg id "$stid" '.[] | select(.stationId == $id) | .preferredImage.uri // empty' "$stations_file" | head -n 1)
        
        # CRITICAL FIX: Check if logo_url is valid HTTP URL before curl
        if [[ -n "$logo_url" ]] && [[ "$logo_url" =~ ^https?:// ]] && [[ ! "$logo_url" =~ ^sources/ ]]; then
          curl -sL --connect-timeout 5 --max-time 10 "$logo_url" --output "$logo_file" 2>/dev/null
        fi
      fi
    fi
    
    if [[ -f "$logo_file" ]]; then
      local mime_type=$(file --mime-type -b "$logo_file")
      if [[ "$mime_type" == image/* ]]; then
        viu -h 3 -w 20 "$logo_file" || echo "[no logo available]"
      else
        echo "[no logo available]"
      fi
    else
      echo "[no logo available]"
    fi
  else
    echo "[logo previews disabled]"
  fi
}

search_local_database() {
  # Check if any database exists, provide helpful guidance if not
  if ! has_stations_database; then
    clear
    echo -e "${BOLD}${YELLOW}Local Database Search${RESET}\n"
    
    echo -e "${RED}❌ Local Database Search: No station data available${RESET}"
    echo
    
    # Provide detailed status of what's available/missing
    local breakdown=$(get_stations_breakdown)
    local base_count=$(echo "$breakdown" | cut -d' ' -f1)
    local user_count=$(echo "$breakdown" | cut -d' ' -f2)
    
    echo -e "${BOLD}${BLUE}Database Status Analysis:${RESET}"
    
    if [ "$base_count" -eq 0 ]; then
      echo -e "${RED}❌ Base Station Database: Not found${RESET}"
      echo -e "${CYAN}💡 Expected location: $(basename "$BASE_STATIONS_JSON") in script directory${RESET}"
      echo -e "${CYAN}💡 Contact script distributor for base database file${RESET}"
    else
      echo -e "${GREEN}✅ Base Station Database: $base_count stations available${RESET}"
    fi
    
    if [ "$user_count" -eq 0 ]; then
      echo -e "${YELLOW}⚠️  User Station Database: Empty${RESET}"
      echo -e "${CYAN}💡 Build via 'Manage Television Markets' → 'Run User Caching'${RESET}"
    else
      echo -e "${GREEN}✅ User Station Database: $user_count stations available${RESET}"
    fi
    
    echo
    
    # Show guidance based on what's available
    if [ "$base_count" -gt 0 ] && [ "$user_count" -eq 0 ]; then
      echo -e "${CYAN}💡 You have the base database - Local Database Search should work!${RESET}"
      echo -e "${CYAN}💡 You can search immediately or add custom markets for expansion${RESET}"
    elif [ "$base_count" -eq 0 ] && [ "$user_count" -gt 0 ]; then
      echo -e "${CYAN}💡 You have user stations - Local Database Search should work!${RESET}"
      echo -e "${CYAN}💡 Consider getting base database for broader coverage${RESET}"
    elif [ "$base_count" -eq 0 ] && [ "$user_count" -eq 0 ]; then
      echo -e "${CYAN}💡 No station database found - need to build or obtain one${RESET}"
      show_workflow_guidance
    fi
    
    echo
    echo -e "${BOLD}${CYAN}Available Options:${RESET}"
    echo -e "${GREEN}1.${RESET} Manage Television Markets → Build User Station Database"
    echo -e "${GREEN}2.${RESET} Use Direct Channels DVR API Search (requires Channels DVR server)"
    echo -e "${GREEN}3.${RESET} Return to main menu"
    echo
    
    read -p "Select option: " choice < /dev/tty
    
    case $choice in
      1)
        echo -e "\n${CYAN}🔄 Opening Television Markets management...${RESET}"
        pause_for_user
        manage_markets
        return
        ;;
      2)
        echo -e "\n${CYAN}🔄 Opening Direct Channels DVR API Search...${RESET}"
        pause_for_user
        run_direct_api_search
        return
        ;;
      3|"")
        return
        ;;
      *)
        echo -e "${RED}❌ Invalid option. Please try again.${RESET}"
        sleep 1
        return
        ;;
    esac
  fi
  
  # Database exists, proceed with search
  run_search_interface
}

run_search_interface() {
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== Local Database Search ===${RESET}\n"
    
    # Show database status with standardized patterns
    local breakdown=$(get_stations_breakdown)
    local base_count=$(echo "$breakdown" | cut -d' ' -f1)
    local user_count=$(echo "$breakdown" | cut -d' ' -f2)
    local total_count=$(get_total_stations_count)
    
    echo -e "${GREEN}✅ Database Available: $total_count stations${RESET}"
    if [ "$base_count" -gt 0 ]; then
      echo -e "   Base Station Database: $base_count stations"
    fi
    if [ "$user_count" -gt 0 ]; then
      echo -e "   User Station Database: $user_count stations"
    fi
    echo
    
    # STANDARDIZED: Current Search Filters with consistent patterns
    echo -e "${BOLD}${BLUE}Current Search Filters:${RESET}"
    if [ "$FILTER_BY_RESOLUTION" = "true" ]; then
      echo -e "${GREEN}✅ Resolution Filter: Active ${RESET}(${YELLOW}$ENABLED_RESOLUTIONS${RESET})"
    else
      echo -e "${YELLOW}⚠️  Resolution Filter: Disabled ${RESET}(${YELLOW}Showing all resolutions${RESET})"
    fi
    
    if [ "$FILTER_BY_COUNTRY" = "true" ]; then
      echo -e "${GREEN}✅ Country Filter: Active ${RESET}(${YELLOW}$ENABLED_COUNTRIES${RESET})"
    else
      echo -e "${YELLOW}⚠️  Country Filter: Disabled ${RESET}(${YELLOW}Showing all countries${RESET})"
    fi
    
    echo -e "${CYAN}💡 Configure filters in Settings to narrow results${RESET}"
    echo
    
    read -p "Enter search term (station name or call sign) or 'q' to return: " search_term < /dev/tty
    
    case "$search_term" in
      q|Q|"") return 0 ;;
      *)
        if [[ -n "$search_term" && ! "$search_term" =~ ^[[:space:]]*$ ]]; then
          perform_search "$search_term"
        else
          echo -e "${RED}❌ Please enter a search term${RESET}"
          echo -e "${CYAN}💡 Try station names like 'CNN' or call signs like 'WABC'${RESET}"
          pause_for_user
        fi
        ;;
    esac
  done
}

perform_search() {
  local search_term="$1"
  local page=1
  local results_per_page=$DEFAULT_RESULTS_PER_PAGE
  
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== Local Database Search Results ===${RESET}\n"
    echo -e "${YELLOW}Search: '$search_term' (Page $page)${RESET}"
    
    # STANDARDIZED: Show active filters with consistent formatting
    local filter_status=""
    if [ "$FILTER_BY_RESOLUTION" = "true" ]; then
      filter_status+="Resolution: ${GREEN}$ENABLED_RESOLUTIONS${RESET} "
    fi
    if [ "$FILTER_BY_COUNTRY" = "true" ]; then
      filter_status+="Country: ${GREEN}$ENABLED_COUNTRIES${RESET} "
    fi
    if [ -n "$filter_status" ]; then
      echo -e "${BLUE}🔍 Active Filters: $filter_status${RESET}"
    else
      echo -e "${CYAN}🔍 No filters active - showing all available stations${RESET}"
    fi
    echo

    # STANDARDIZED: Progress indicator for search
    echo -e "${CYAN}🔄 Searching database...${RESET}"
    
    # Get search results using shared function
    local results
    results=$(shared_station_search "$search_term" "$page" "full")
    
    local total_results
    total_results=$(shared_station_search "$search_term" 1 "count")

    # STANDARDIZED: Result display with consistent error handling
    if [[ -z "$results" ]]; then
      echo -e "\n${YELLOW}⚠️  No results found for '$search_term'${RESET}"
      echo
      echo -e "${BOLD}${CYAN}Suggestions to improve your search:${RESET}"
      if [ "$FILTER_BY_RESOLUTION" = "true" ] || [ "$FILTER_BY_COUNTRY" = "true" ]; then
        echo -e "${CYAN}💡 Try disabling filters in Settings → Search Filters${RESET}"
      fi
      echo -e "${CYAN}💡 Try partial names: 'ESPN' instead of 'ESPN Sports Center'${RESET}"
      echo -e "${CYAN}💡 Try call signs: 'CNN' for CNN stations${RESET}"
      echo -e "${CYAN}💡 Check spelling and try alternative names${RESET}"
      echo
    else
      echo -e "\n${GREEN}✅ Found $total_results total results${RESET}"
      echo -e "${CYAN}💡 Showing page $page with up to $results_per_page results${RESET}"
      echo

      # Enhanced table header with selection column (in perform_search function)
      printf "${BOLD}${YELLOW}%-3s %-30s %-10s %-8s %-12s %s${RESET}\n" "Key" "Channel Name" "Call Sign" "Quality" "Station ID" "Country"
      echo "---------------------------------------------------------------------------------"

      local result_count=0
      local key_letters=("a" "b" "c" "d" "e" "f" "g" "h" "i" "j")

      # FIXED: Process search results with GREEN selection highlighting
      while IFS=$'\t' read -r name call_sign quality station_id country; do
        [[ -z "$name" ]] && continue

        local key="${key_letters[$result_count]}"

        # FIXED: Format table row with GREEN selection highlighting
        printf "${GREEN}%-3s${RESET} " "${key})"
        printf "%-30s %-10s %-8s " "${name:0:30}" "${call_sign:0:10}" "${quality:0:8}"
        echo -n -e "${CYAN}${station_id}${RESET}"
        printf "%*s" $((12 - ${#station_id})) ""
        echo -e "${GREEN}${country}${RESET}"

        # STANDARDIZED: Logo display with consistent messaging
        if [[ "$SHOW_LOGOS" == true ]]; then
          display_logo "$station_id"
        else
          echo "   [logo previews disabled - enable in Settings]"
        fi
        echo

        ((result_count++))
      done <<< "$results"
    fi

    # STANDARDIZED: Calculate pagination info with error handling
    local total_pages=$(( (total_results + results_per_page - 1) / results_per_page ))
    [[ $total_pages -eq 0 ]] && total_pages=1

    echo -e "${BOLD}${BLUE}Page $page of $total_pages${RESET}"
    echo

    # STANDARDIZED: Navigation options with consistent formatting
    echo -e "${BOLD}${CYAN}Navigation Options:${RESET}"
    [[ $result_count -gt 0 ]] && echo -e "${GREEN}a-j)${RESET} View detailed info for selected station"
    [[ $page -lt $total_pages ]] && echo -e "${GREEN}n)${RESET} Next page"
    [[ $page -gt 1 ]] && echo -e "${GREEN}p)${RESET} Previous page"
    echo -e "${GREEN}s)${RESET} New search"
    echo -e "${GREEN}q)${RESET} Back to search menu"
    echo

    read -p "Your choice: " choice < /dev/tty

    case "$choice" in
      a|A|b|B|c|C|d|D|e|E|f|F|g|G|h|H|i|I|j|J)
        if [[ $result_count -gt 0 ]]; then
          show_station_details "$choice" "$results"
        else
          echo -e "${RED}❌ No results to select from${RESET}"
          echo -e "${CYAN}💡 Try a different search term${RESET}"
          sleep 2
        fi
        ;;
      n|N)
        if [[ $page -lt $total_pages ]]; then
          ((page++))
        else
          echo -e "${YELLOW}⚠️  Already on last page${RESET}"
          sleep 1
        fi
        ;;
      p|P)
        if [[ $page -gt 1 ]]; then
          ((page--))
        else
          echo -e "${YELLOW}⚠️  Already on first page${RESET}"
          sleep 1
        fi
        ;;
      s|S)
        return 0  # Return to search interface for new search
        ;;
      q|Q|"")
        return 0  # Return to search interface
        ;;
      *)
        echo -e "${RED}❌ Invalid option. Please try again.${RESET}"
        sleep 1
        ;;
    esac
  done
}

show_station_details() {
  local choice="$1"
  local results="$2"
  
  # Convert letter to array index
  local letter_lower=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
  local index=-1
  local key_letters=("a" "b" "c" "d" "e" "f" "g" "h" "i" "j")
  
  for ((idx=0; idx<10; idx++)); do
    if [[ "${key_letters[$idx]}" == "$letter_lower" ]]; then
      index=$idx
      break
    fi
  done
  
  if [[ $index -ge 0 ]]; then
    # Get the selected result (line number = index + 1)
    local selected_line=$(echo "$results" | sed -n "$((index + 1))p")
    
    if [[ -n "$selected_line" ]]; then
      IFS=$'\t' read -r name call_sign quality station_id country <<< "$selected_line"
      
      clear
      echo -e "${BOLD}${CYAN}=== Station Details ===${RESET}\n"
      
      # STANDARDIZED: Basic Information with enhanced formatting
      echo -e "${BOLD}${BLUE}Basic Information:${RESET}"
      echo -e "${CYAN}Station Name:${RESET} ${GREEN}$name${RESET}"
      echo -e "${CYAN}Call Sign:${RESET} ${GREEN}$call_sign${RESET}"
      echo -e "${CYAN}Station ID:${RESET} ${GREEN}$station_id${RESET}"
      echo -e "${CYAN}Country:${RESET} ${GREEN}$country${RESET}"
      echo -e "${CYAN}Video Quality:${RESET} ${GREEN}$quality${RESET}"
      echo
      
      # STANDARDIZED: Progress indicator for additional data lookup
      echo -e "${CYAN}🔄 Retrieving additional station information...${RESET}"
      
      # Get additional details from database with error handling
      local stations_file
      stations_file=$(get_effective_stations_file)
      if [[ $? -eq 0 ]]; then
        local details=$(jq -r --arg id "$station_id" \
          '.[] | select(.stationId == $id) | 
           "Network: " + (.network // "N/A") + "\n" +
           "Language: " + (.language // "N/A") + "\n" +
           "Logo URL: " + (.preferredImage.uri // "N/A") + "\n" +
           "Description: " + (.description // "N/A")' \
          "$stations_file" 2>/dev/null)
        
        if [[ -n "$details" ]]; then
          echo -e "${BOLD}${BLUE}Extended Information:${RESET}"
          echo "$details"
          echo
        else
          echo -e "${YELLOW}⚠️  Extended information not available for this station${RESET}"
          echo -e "${CYAN}💡 This may occur with manually-added or API-sourced stations${RESET}"
          echo
        fi
      else
        echo -e "${RED}❌ Station Database: Unable to access extended information${RESET}"
        echo -e "${CYAN}💡 Database may be temporarily unavailable${RESET}"
        echo
      fi
      
      # STANDARDIZED: Logo display with enhanced messaging
      echo -e "${BOLD}${BLUE}Station Logo:${RESET}"
      if [[ "$SHOW_LOGOS" == true ]]; then
        echo -e "${CYAN}🖼️  Logo preview:${RESET}"
        display_logo "$station_id"
        echo
      else
        echo -e "${YELLOW}⚠️  Logo previews disabled${RESET}"
        echo -e "${CYAN}💡 Enable in Settings → Logo Display for visual previews${RESET}"
        echo -e "${CYAN}💡 Requires 'viu' tool for terminal image display${RESET}"
        echo
      fi
      
      # STANDARDIZED: Usage guidance
      echo -e "${BOLD}${BLUE}Usage Information:${RESET}"
      echo -e "${CYAN}💡 This station can be used for:${RESET}"
      echo -e "${GREEN}• Search results and filtering${RESET}"
      echo -e "${GREEN}• Dispatcharr integration and channel matching${RESET}"
      echo -e "${GREEN}• Station ID lookups and reverse searches${RESET}"
      echo -e "${GREEN}• Export to CSV for external use${RESET}"
      echo
      
      # STANDARDIZED: Data source information
      local data_source="Unknown"
      local stations_data=$(jq -r --arg id "$station_id" '.[] | select(.stationId == $id) | .source // "Unknown"' "$stations_file" 2>/dev/null)
      if [[ -n "$stations_data" && "$stations_data" != "null" ]]; then
        data_source="$stations_data"
      fi
      
      echo -e "${BOLD}${BLUE}Data Source:${RESET}"
      case "$data_source" in
        "user")
          echo -e "${GREEN}✅ User Station Database${RESET} (from your configured markets)"
          ;;
        "base"|"combined")
          echo -e "${GREEN}✅ Base Station Database${RESET} (distributed with script)"
          ;;
        *)
          echo -e "${CYAN}💡 Combined Database${RESET} (merged from available sources)"
          ;;
      esac
      echo
      
      pause_for_user
    else
      echo -e "${RED}❌ Station Details: Could not retrieve information${RESET}"
      echo -e "${CYAN}💡 The selected station may no longer be available${RESET}"
      echo -e "${CYAN}💡 Try refreshing your search results${RESET}"
      sleep 2
    fi
  else
    echo -e "${RED}❌ Invalid Selection: '$choice' is not a valid option${RESET}"
    echo -e "${CYAN}💡 Use letters a-j to select from the displayed results${RESET}"
    sleep 2
  fi
}

run_direct_api_search() {
  # Validate server is configured and accessible
  if [[ -z "${CHANNELS_URL:-}" ]]; then
    echo -e "${RED}❌ Channels DVR Integration: No server configured${RESET}"
    echo -e "${CYAN}💡 Configure server in Settings → Channels DVR Server first${RESET}"
    pause_for_user
    return 1
  fi
  
  # Test server connection
  echo -e "${CYAN}🔗 Testing connection to Channels DVR server...${RESET}"
  if ! channels_dvr_test_connection; then
      pause_for_user
      return 1
  fi
  
  echo -e "${GREEN}✅ Connection to Channels DVR server confirmed${RESET}"
  
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== Direct Channels DVR API Search ===${RESET}\n"
    
    echo -e "${GREEN}✅ Connected to: $CHANNELS_URL${RESET}"
    echo
    echo -e "${BOLD}${YELLOW}⚠️  IMPORTANT API LIMITATIONS:${RESET}"
    echo -e "${RED}• Results limited to 6 stations per search${RESET}"
    echo -e "${RED}• No country information available${RESET}"
    echo -e "${RED}• Search filters (resolution, country) not available${RESET}"
    echo -e "${RED}• Less comprehensive than Local Database Search${RESET}"
    echo
    echo -e "${GREEN}💡 For better results: Use 'Local Database Search' instead${RESET}"
    echo
    
    read -p "Search API by station name or call sign (or 'q' to return): " SEARCH_TERM < /dev/tty
    
    case "$SEARCH_TERM" in
      q|Q|"") break ;;
      *)
        if [[ -z "$SEARCH_TERM" || "$SEARCH_TERM" =~ ^[[:space:]]*$ ]]; then
          echo -e "${RED}❌ Please enter a search term${RESET}"
          echo -e "${CYAN}💡 Try station names like 'CNN' or call signs like 'ESPN'${RESET}"
          pause_for_user
          continue
        fi

        perform_direct_api_search "$SEARCH_TERM"
        ;;
    esac
  done
}

perform_direct_api_search() {
  local search_term="$1"
  
  echo -e "\n${CYAN}🔍 Searching Channels DVR API for '$search_term'...${RESET}"
  echo -e "${CYAN}💡 This may take a moment to query the server${RESET}"
  
  # Call the TMS API using the API module
  local api_response
  echo -e "${CYAN}📡 Querying: $CHANNELS_URL/tms/stations/$search_term${RESET}"
  
  api_response=$(channels_dvr_search_stations "$search_term")
  if [[ $? -ne 0 ]]; then
    echo -e "${CYAN}💡 Alternative: Use Local Database Search for reliable results${RESET}"
    pause_for_user
    return
  fi
  
  # Process the response and convert to TSV format
  echo "$api_response" | jq -r '
    .[] | [
      .name // "Unknown", 
      .callSign // "N/A", 
      .videoQuality.videoType // "Unknown", 
      .stationId // "Unknown",
      "API-Direct"
    ] | @tsv
  ' > "$API_SEARCH_RESULTS" 2>/dev/null
  
  if [[ $? -ne 0 ]]; then
    clear
    echo -e "${BOLD}${CYAN}=== Direct Channels DVR API Search ===${RESET}"
    echo -e "${CYAN}Searched for: '$search_term' on $CHANNELS_URL${RESET}"
    echo
    echo -e "${RED}❌ API Response Processing: Failed to parse station data${RESET}"
    echo -e "${CYAN}💡 API response format may have changed${RESET}"
    echo -e "${CYAN}💡 Try Local Database Search as alternative${RESET}"
    pause_for_user
    return
  fi
  
  # Success case - pass search context to display function
  display_direct_api_results "$search_term"
}

display_direct_api_results() {
  local search_term="$1"
  
  mapfile -t RESULTS < "$API_SEARCH_RESULTS"
  local count=${#RESULTS[@]}
  
  clear
  echo -e "${BOLD}${CYAN}=== Direct Channels DVR API Search ===${RESET}"
  echo -e "${CYAN}Searched for: '$search_term' on $CHANNELS_URL${RESET}"
  echo -e "${GREEN}✅ API search completed successfully${RESET}"
  echo
  
  if [[ $count -eq 0 ]]; then
    echo -e "${YELLOW}⚠️  No results found for '$search_term' in API${RESET}"
    echo -e "${CYAN}💡 Try: Different spelling, call signs, or partial names${RESET}"
    echo -e "${GREEN}💡 Local Database Search may have more comprehensive results${RESET}"
  else
    echo -e "${GREEN}✅ Found $count result(s) for '$search_term'${RESET}"
    echo -e "${YELLOW}⚠️  Direct API results (limited to 6 maximum)${RESET}"
    echo -e "${CYAN}💡 No country data available, no filtering applied${RESET}"
    echo -e "${RED}⚠️  Station details not available for API results${RESET}"
    echo

    # Table header WITHOUT selection column (no Key column)
    printf "${BOLD}${YELLOW}%-30s %-10s %-8s %-12s${RESET}\n" "Channel Name" "Call Sign" "Quality" "Station ID"
    echo "----------------------------------------------------------------"

    for ((i = 0; i < count; i++)); do
      IFS=$'\t' read -r NAME CALLSIGN RES STID SOURCE <<< "${RESULTS[$i]}" 
      printf "%-30s %-10s %-8s ${CYAN}%-12s${RESET}\n" "$NAME" "$CALLSIGN" "$RES" "$STID"

      # Display logo if available
      display_logo "$STID"
      echo
    done

    echo -e "${CYAN}💡 Tip: For detailed station information and filtering, use Local Database Search${RESET}"
    echo -e "${CYAN}💡 Local Database Search provides comprehensive station details and advanced features${RESET}"
  fi
  
  pause_for_user
}

reverse_station_id_lookup() {
  local station_id="$1"
  
  if [[ -z "$station_id" ]]; then
    echo -e "${RED}❌ Station ID required for lookup${RESET}"
    return 1
  fi
  
  echo -e "${CYAN}🔍 Looking up station ID: $station_id${RESET}"
  
  # Check local database only
  if ! has_stations_database; then
    echo -e "${RED}❌ No station database available${RESET}"
    echo -e "${CYAN}💡 Build database via 'Manage Television Markets' → 'Run User Caching'${RESET}"
    return 1
  fi
  
  local stations_file
  stations_file=$(get_effective_stations_file)
  local local_result=$(jq -r --arg id "$station_id" \
    '.[] | select(.stationId == $id) | 
     "Name: " + (.name // "Unknown") + "\n" +
     "Call Sign: " + (.callSign // "N/A") + "\n" + 
     "Country: " + (.country // "Unknown") + "\n" +
     "Quality: " + (.videoQuality.videoType // "Unknown") + "\n" +
     "Network: " + (.network // "N/A") + "\n" +
     "Logo: " + (.preferredImage.uri // "No logo available")' \
    "$stations_file" 2>/dev/null)
  
  if [[ -n "$local_result" ]]; then
    echo -e "${GREEN}✅ Station found:${RESET}"
    echo "$local_result"
    echo
    
    # Show logo if available and enabled
    if [[ "$SHOW_LOGOS" == true ]]; then
      echo -e "${CYAN}Logo preview:${RESET}"
      display_logo "$station_id"
    fi
    
    echo -e "${GREEN}✅ Lookup completed successfully${RESET}"
    return 0
  else
    echo -e "${RED}❌ Station ID '$station_id' not found${RESET}"
    echo
    echo -e "${BOLD}${CYAN}Troubleshooting:${RESET}"
    echo -e "${CYAN}• Verify the station ID is correct${RESET}"
    echo -e "${CYAN}• Try searching by name using 'Search Local Database'${RESET}"
    echo -e "${CYAN}• Add more markets for broader coverage${RESET}"
    
    local total_count=$(get_total_stations_count)
    echo -e "${CYAN}• Database contains $total_count stations total${RESET}"
    
    return 1
  fi
}

reverse_station_id_lookup_menu() {
  clear
  echo -e "${BOLD}${CYAN}=== Reverse Station ID Lookup ===${RESET}\n"
  echo -e "${BLUE}📍 Station Information Retrieval${RESET}"
  echo -e "${YELLOW}Enter a station ID to get comprehensive information about that station.${RESET}"
  echo
  
  # Show database status
  local total_count=$(get_total_stations_count)
  if [ "$total_count" -gt 0 ]; then
    echo -e "${GREEN}✅ Database Available: $total_count stations ready for lookup${RESET}"
    
    # Show sample station IDs for guidance
    local stations_file
    stations_file=$(get_effective_stations_file)
    if [ $? -eq 0 ]; then
      local sample_ids=$(jq -r '.[] | .stationId' "$stations_file" 2>/dev/null | head -5 | tr '\n' ', ' | sed 's/,$//')
      if [ -n "$sample_ids" ]; then
        echo -e "${CYAN}Examples: $sample_ids${RESET}"
      fi
    fi
  else
    echo -e "${RED}❌ No station database available${RESET}"
    echo -e "${CYAN}💡 Use 'Manage Television Markets' → 'Run User Caching' to build database${RESET}"
    pause_for_user
    return 1
  fi
  echo
  
  # Station ID input with validation
  local lookup_id
  while true; do
    read -p "Enter station ID (or press Enter to return): " lookup_id < /dev/tty
    
    # Handle empty input (user wants to exit)
    if [[ -z "$lookup_id" ]]; then
      return 0
    fi
    
    # Remove any whitespace
    lookup_id=$(echo "$lookup_id" | tr -d '[:space:]')
    
    # Validate station ID format
    if [[ "$lookup_id" =~ ^[0-9]+$ ]]; then
      if (( lookup_id >= 1 && lookup_id <= 999999 )); then
        echo -e "${GREEN}✅ Station ID accepted: $lookup_id${RESET}"
        break
      else
        echo -e "${RED}❌ Station ID out of valid range (1-999999)${RESET}"
      fi
    else
      echo -e "${RED}❌ Station ID must be numeric only${RESET}"
    fi
  done
  
  echo
  
  # Perform lookup
  if reverse_station_id_lookup "$lookup_id"; then
    echo
    echo -e "${BOLD}${CYAN}Next Steps:${RESET}"
    echo -e "${GREEN}• Search for more stations using 'Search Local Database'${RESET}"
    echo -e "${GREEN}• Look up additional station IDs${RESET}"
    echo -e "${GREEN}• Use this information in Dispatcharr integration${RESET}"
  fi
  
  pause_for_user
}

# ============================================================================
# EMBY INTEGRATION FUNCTIONS
# ============================================================================

configure_emby_connection() {
    clear
    echo -e "${BOLD}${CYAN}=== Configure Emby Integration ===${RESET}\n"
    
    show_setting_status "EMBY_ENABLED" "$EMBY_ENABLED" "Emby Integration" \
        "$([ "$EMBY_ENABLED" = "true" ] && echo "enabled" || echo "disabled")"
    echo
    
    if configure_setting "boolean" "Integration" "$EMBY_ENABLED"; then
        EMBY_ENABLED=true
        save_setting "EMBY_ENABLED" "$EMBY_ENABLED"
        
        # Use the config.sh configure_emby_server function
        if configure_emby_server; then
            echo -e "${GREEN}✅ Emby integration configured successfully!${RESET}"
        else
            echo -e "${YELLOW}⚠️  Emby integration configuration incomplete${RESET}"
        fi
    else
        EMBY_ENABLED=false
        save_setting "EMBY_ENABLED" "$EMBY_ENABLED"
        echo -e "${CYAN}💡 Emby integration disabled${RESET}"
    fi
    
    echo -e "\n${GREEN}✅ Emby configuration completed${RESET}"
}

debug_emby_integration() {
    echo -e "\n${BOLD}${CYAN}=== Comprehensive Emby Debug ===${RESET}"
    
    # Basic connectivity
    echo -e "\n${BOLD}1️⃣ Basic Connectivity${RESET}"
    if curl -s --connect-timeout 10 "$EMBY_URL" >/dev/null; then
        echo -e "${GREEN}✅ Server reachable at $EMBY_URL${RESET}"
    else
        echo -e "${RED}❌ Cannot reach $EMBY_URL${RESET}"
        return 1
    fi
    
    # Authentication
    echo -e "\n${BOLD}2️⃣ Authentication Test${RESET}"
    if emby_test_connection >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Authentication successful${RESET}"
        echo -e "${CYAN}   🔑 API Key: ${EMBY_API_KEY:0:8}...${RESET}"
    else
        echo -e "${RED}❌ Authentication failed${RESET}"
        return 1
    fi
    
    # Channel data structure
    echo -e "\n${BOLD}3️⃣ Channel Data Analysis${RESET}"
    local test_response
    test_response=$(curl -s -H "X-Emby-Token: $EMBY_API_KEY" "${EMBY_URL}/emby/LiveTv/Manage/Channels?Fields=ManagementId,ListingsId,Name,ChannelNumber,Id&Limit=1")
    
    if echo "$test_response" | jq empty 2>/dev/null; then
        echo -e "${GREEN}✅ Valid JSON response${RESET}"
        
        if echo "$test_response" | jq -e 'type == "array"' >/dev/null 2>&1; then
            echo -e "${CYAN}   📋 Response type: Direct array${RESET}"
        elif echo "$test_response" | jq -e '.Items' >/dev/null 2>&1; then
            echo -e "${CYAN}   📋 Response type: Object with Items property${RESET}"
        else
            echo -e "${YELLOW}   ⚠️  Unknown response structure${RESET}"
        fi
        
        # Show first channel structure
        echo -e "${CYAN}   📋 Sample channel structure:${RESET}"
        echo "$test_response" | jq '.[0] // .Items[0] // . | {Id, Name, ChannelNumber, ListingsId, ManagementId}' 2>/dev/null | sed 's/^/     /'
    else
        echo -e "${RED}❌ Invalid JSON response${RESET}"
        echo -e "${CYAN}Response: ${test_response:0:200}...${RESET}"
    fi
    
    echo -e "\n${CYAN}💡 Use this information to troubleshoot any issues${RESET}"
}

# Main Emby workflow function - COMPLETE IMPLEMENTATION with Enhanced User Guidance
scan_emby_missing_listingsids() {
    echo -e "\n${BOLD}Emby Channel ListingsId Auto-Assignment${RESET}"
    echo -e "${BLUE}📍 Enhanced workflow: Scan → Extract Station IDs → Lookup → Add Listing Providers${RESET}"
    echo -e "${CYAN}This will add missing listing providers to Emby and let Emby automatically map channels.${RESET}"
    echo
    
    # Step 1: Test connection
    echo -e "${CYAN}🔗 Connecting to Emby server...${RESET}"
    if ! emby_test_connection >/dev/null 2>&1; then
        echo -e "${RED}❌ Emby Integration: Connection Failed${RESET}"
        echo -e "${CYAN}💡 Configure connection in Settings → Emby Integration${RESET}"
        pause_for_user
        return 1
    fi
    echo -e "${GREEN}✅ Successfully connected to Emby server${RESET}"
    echo
    
    # Step 2: Find channels missing ListingsId and extract station IDs
    echo -e "${CYAN}🔍 Scanning Emby Live TV channels for missing ListingsId...${RESET}"
    local missing_channels
    missing_channels=$(emby_find_channels_missing_listingsid)
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}❌ Failed to scan Emby channels${RESET}"
        pause_for_user
        return 1
    fi
    
    # ADD PROCESSING MESSAGE HERE to fill the silent gap
    echo -e "${CYAN}⚙️  Processing extracted channel data...${RESET}"
    
    # Parse the missing channels and extract station IDs
    local station_ids=()
    local channel_mapping=()
    
    while IFS= read -r channel_line; do
        if [[ -n "$channel_line" && "$channel_line" != "null" ]]; then
            local channel_id=$(echo "$channel_line" | jq -r '.Id')
            local channel_name=$(echo "$channel_line" | jq -r '.Name')
            local channel_number=$(echo "$channel_line" | jq -r '.ChannelNumber')
            local extracted_id=$(echo "$channel_line" | jq -r '.ExtractedId')
            
            if [[ -n "$extracted_id" && "$extracted_id" != "null" ]]; then
                station_ids+=("$extracted_id")
                channel_mapping+=("$channel_id|$channel_name|$channel_number|$extracted_id")
            fi
        fi
    done < <(echo "$missing_channels" | jq -c '.')
    
    local channel_count=${#station_ids[@]}
    
    # Clean summary - no spam
    if [[ "$channel_count" -eq 0 ]]; then
        echo -e "${GREEN}🎉 Excellent! All your Emby channels already have ListingsId assigned${RESET}"
        echo -e "${CYAN}💡 No action needed - your Emby channels are fully configured${RESET}"
        pause_for_user
        return 0
    fi
    
    echo -e "${GREEN}📊 Found ${BOLD}$channel_count channels${RESET}${GREEN} missing ListingsId${RESET}"
    echo -e "${CYAN}💡 Station IDs extracted successfully${RESET}"
    
    # Step 3: Automatic reverse lookup (no user confirmation needed)
    echo
    echo -e "${CYAN}🔍 Starting reverse lookup for ${BOLD}$channel_count Station IDs${RESET}${CYAN}...${RESET}"
    
    local lookup_results
    lookup_results=$(emby_reverse_lookup_station_ids "${station_ids[@]}")
    
    if [[ $? -ne 0 ]] || [[ -z "$lookup_results" ]]; then
        echo -e "${RED}❌ Reverse lookup failed${RESET}"
        echo -e "${CYAN}💡 Ensure you have a station database built via 'Manage Television Markets'${RESET}"
        pause_for_user
        return 1
    fi
    
    # Parse and validate lookup results
    local lookup_count
    lookup_count=$(echo "$lookup_results" | jq 'length' 2>/dev/null || echo "0")
    
    if [[ "$lookup_count" -eq 0 ]]; then
        echo -e "${YELLOW}⚠️  No station matches found in your database${RESET}"
        echo -e "${CYAN}💡 Try expanding your station database with additional markets${RESET}"
        pause_for_user
        return 0
    fi
    
    # Show unique listing providers that will be added
    local unique_providers
    unique_providers=$(echo "$lookup_results" | jq -r '.[] | "\(.lineupId)|\(.country)|\(.lineupName)"' | sort -u)
    local provider_count=$(echo "$unique_providers" | wc -l)
    
    echo
    echo -e "${BOLD}${CYAN}=== Ready to Add Listing Providers ===${RESET}"
    echo -e "${CYAN}Found matches for ${BOLD}$lookup_count${RESET}${CYAN} of ${BOLD}$channel_count${RESET}${CYAN} channels${RESET}"
    echo -e "${CYAN}This creates ${BOLD}$provider_count unique listing providers${RESET}${CYAN} to add to Emby${RESET}"
    echo
    
    # Show the providers (condensed - max 10)
    printf "${BOLD}${YELLOW}%-20s %-10s %-30s${RESET}\n" "LineupId" "Country" "LineupName"
    echo "------------------------------------------------------------"
    echo "$unique_providers" | head -10 | while IFS='|' read -r lineup_id country lineup_name; do
        [[ -n "$lineup_id" ]] && printf "%-20s %-10s %-30s\n" "$lineup_id" "$country" "$lineup_name"
    done
    
    if [[ "$provider_count" -gt 10 ]]; then
        echo -e "${CYAN}... and $((provider_count - 10)) more providers${RESET}"
    fi
    echo
    
    # Final confirmation before adding to Emby
    echo -e "${BOLD}${YELLOW}Final Step: Add Listing Providers${RESET}"
    echo -e "${CYAN}This will add ${BOLD}$provider_count listing providers${RESET}${CYAN} to your Emby server.${RESET}"
    echo -e "${CYAN}Emby will then automatically map your $channel_count channels to these listings.${RESET}"
    echo
    
    if ! confirm_action "Add these $provider_count listing providers to Emby now?"; then
        echo -e "${YELLOW}⚠️  Operation cancelled by user${RESET}"
        pause_for_user
        return 0
    fi
    
    # Step 4: Add listing providers to Emby
    echo
    echo -e "${CYAN}📡 Adding listing providers to Emby server...${RESET}"
    echo
    
    # Call the new function to process listing providers
    if process_emby_missing_listings "$lookup_results" "${channel_mapping[@]}"; then
        echo -e "\n${GREEN}✅ Emby listing provider integration complete${RESET}"
    else
        echo -e "\n${RED}❌ Some listing providers failed to add${RESET}"
    fi
    
    pause_for_user
}

# ============================================================================
# DISPATCHARR INTEGRATION FUNCTIONS
# ============================================================================

get_dispatcharr_channels() {
  local response
  response=$(dispatcharr_get_channels)
  if [[ $? -eq 0 ]]; then
    echo "$response" > "$DISPATCHARR_CACHE"
    echo "$response"
  else
    return 1
  fi
}

find_channels_missing_stationid() {
  local channels_data="$1"
  
  # Extract missing channels and sort by channel number
  echo "$channels_data" | jq -r '
    .[] | 
    select((.tvc_guide_stationid // "") == "" or (.tvc_guide_stationid // "") == null) |
    [.id, .name, .channel_group_id // "Ungrouped", (.channel_number // 0)] | 
    @tsv
  ' 2>/dev/null | sort -t$'\t' -k4 -n
}

search_stations_by_name() {
  local search_term="$1"
  local page="${2:-1}"
  local runtime_country="${3:-}"     # Future: from channel name parsing
  local runtime_resolution="${4:-}"  # Future: from channel name parsing
  
  # Delegate to shared search function
  shared_station_search "$search_term" "$page" "tsv" "$runtime_country" "$runtime_resolution"
}

get_total_search_results() {
  local search_term="$1"
  local runtime_country="${2:-}"     # Future: from channel name parsing
  local runtime_resolution="${3:-}"  # Future: from channel name parsing
  
  # Delegate to shared search function
  shared_station_search "$search_term" 1 "count" "$runtime_country" "$runtime_resolution"
}

update_dispatcharr_channel_station_id() {
  local channel_id="$1"
  local station_id="$2"
  
  dispatcharr_update_channel_station_id "$channel_id" "$station_id"
}

configure_dispatcharr_connection() {
    clear
    echo -e "${BOLD}${CYAN}=== Configure Dispatcharr Integration ===${RESET}\n"
    
    show_setting_status "DISPATCHARR_ENABLED" "$DISPATCHARR_ENABLED" "Dispatcharr Integration" \
        "$([ "$DISPATCHARR_ENABLED" = "true" ] && echo "enabled" || echo "disabled")"
    
    if configure_setting "boolean" "Integration" "$DISPATCHARR_ENABLED"; then
        DISPATCHARR_ENABLED=true
        save_setting "DISPATCHARR_ENABLED" "$DISPATCHARR_ENABLED"
        
        if configure_setting "network" "DISPATCHARR_URL" "$DISPATCHARR_URL"; then
            # Reload config to get the updated settings
            source "$CONFIG_FILE" 2>/dev/null
            configure_setting "credentials" "Dispatcharr"
        fi
    else
        DISPATCHARR_ENABLED=false
        save_setting "DISPATCHARR_ENABLED" "$DISPATCHARR_ENABLED"
    fi
}

scan_missing_stationids() {
  echo -e "\n${BOLD}Scanning Dispatcharr Channels${RESET}"
  echo -e "${BLUE}📍 Step 1 of 3: Identify Channels Needing Station IDs${RESET}"
  echo -e "${CYAN}This will analyze your Dispatcharr channels and identify which ones need station ID assignment.${RESET}"
  echo
  
  if ! dispatcharr_test_connection >/dev/null 2>&1; then
    echo -e "${RED}❌ Dispatcharr Integration: Connection Failed${RESET}"
    echo -e "${CYAN}💡 Configure connection in Settings → Dispatcharr Integration${RESET}"
    echo -e "${CYAN}💡 Verify server is running and credentials are correct${RESET}"
    pause_for_user
    return 1
  fi
  
  if ! has_stations_database; then
    echo -e "${RED}❌ Local Database Search: No station data available${RESET}"
    echo -e "${CYAN}💡 Base Station Database: Add $(basename "$BASE_STATIONS_JSON") to script directory${RESET}"
    echo -e "${CYAN}💡 User Station Database: Use 'Manage Television Markets' → 'Run User Caching'${RESET}"
    pause_for_user
    return 1
  fi
  
  echo -e "${CYAN}📡 Fetching channels from Dispatcharr...${RESET}"
  local channels_data
  channels_data=$(get_dispatcharr_channels)
  
  if [[ -z "$channels_data" ]]; then
    echo -e "${RED}❌ Failed to retrieve channels from Dispatcharr${RESET}"
    echo -e "${CYAN}💡 Check Dispatcharr connection and try again${RESET}"
    pause_for_user
    return 1
  fi
  
  echo -e "${CYAN}📡 Fetching channel groups from Dispatcharr...${RESET}"
  local groups_data
  groups_data=$(dispatcharr_get_groups)
  
  if [[ -z "$groups_data" ]]; then
    echo -e "${YELLOW}⚠️  Could not retrieve channel groups - will show group IDs${RESET}"
    groups_data="[]"
  fi
  
  echo -e "${CYAN}🔍 Analyzing channels for missing station IDs...${RESET}"
  local missing_channels
  missing_channels=$(find_channels_missing_stationid "$channels_data")
  
  if [[ -z "$missing_channels" ]]; then
    clear
    echo -e "${BOLD}${CYAN}=== Dispatcharr Channel Scan ===${RESET}"
    echo -e "${BLUE}📍 Step 1 of 3: Identify Channels Needing Station IDs${RESET}"
    echo -e "${CYAN}This analyzed your Dispatcharr channels and identified which ones need station ID assignment.${RESET}"
    echo
    echo -e "${BOLD}${GREEN}=== Scan Results ===${RESET}\n"
    echo -e "${GREEN}✅ Excellent! All channels have station IDs assigned!${RESET}"
    echo
    echo -e "${CYAN}📊 Analysis Complete:${RESET}"
    local total_channels=$(echo "$channels_data" | jq 'length' 2>/dev/null || echo "0")
    
    printf "${BOLD}${YELLOW}%-25s %s${RESET}\n" "Analysis Category" "Count"
    echo "----------------------------------------"
    printf "%-25s " "Total channels scanned:" && echo -e "${CYAN}$total_channels${RESET}"
    printf "%-25s " "Missing station IDs:" && echo -e "${GREEN}0${RESET}"
    printf "%-25s " "Channels with IDs:" && echo -e "${GREEN}$total_channels${RESET}"
    echo
    
    echo -e "${BOLD}${CYAN}Next Steps:${RESET}"
    echo -e "• Your Dispatcharr channels are fully configured for station IDs"
    echo -e "• Consider using 'Populate Other Dispatcharr Fields' to enhance channel data"
    echo -e "• No station ID matching needed at this time"
    echo
    pause_for_user
    return 0
  fi
  
  echo -e "${CYAN}📋 Sorting channels by channel number...${RESET}"
  local sorted_missing_channels
  sorted_missing_channels=$(echo "$missing_channels" | sort -t$'\t' -k4 -n)
  
  mapfile -t missing_array <<< "$sorted_missing_channels"
  local total_missing=${#missing_array[@]}
  
  # Helper function to get group name from group ID
  get_group_name() {
    local group_id="$1"
    if [[ -z "$group_id" || "$group_id" == "null" || "$group_id" == "Ungrouped" ]]; then
      echo "Ungrouped"
    else
      local group_name=$(echo "$groups_data" | jq -r --arg id "$group_id" '.[] | select(.id == ($id | tonumber)) | .name // empty' 2>/dev/null)
      if [[ -n "$group_name" && "$group_name" != "null" ]]; then
        echo "$group_name"
      else
        echo "Group $group_id"
      fi
    fi
  }
  
  # Paginated display with enhanced formatting and channel selection
  local offset=0
  local results_per_page=$DEFAULT_RESULTS_PER_PAGE
  
  while (( offset < total_missing )); do
    clear
    echo -e "${BOLD}${CYAN}=== Dispatcharr Channel Scan ===${RESET}"
    echo -e "${BLUE}📍 Step 1 of 3: Identify Channels Needing Station IDs${RESET}"
    echo -e "${CYAN}This analyzed your Dispatcharr channels and identified which ones need station ID assignment.${RESET}"
    echo
    echo -e "${BOLD}${GREEN}=== Scan Results ===${RESET}"
    echo -e "${GREEN}✅ Scan completed: $total_missing channels need station IDs${RESET}"
    echo -e "${CYAN}💡 Channels are sorted by number for easy navigation${RESET}"
    echo
    
    # Calculate current page info
    local start_num=$((offset + 1))
    local end_num=$((offset + results_per_page < total_missing ? offset + results_per_page : total_missing))
    local current_page=$(( (offset / results_per_page) + 1 ))
    local total_pages=$(( (total_missing + results_per_page - 1) / results_per_page ))
    
    echo -e "${BOLD}Showing results $start_num-$end_num of $total_missing (Page $current_page of $total_pages)${RESET}"
    echo
    
    # Table header
    printf "${BOLD}${YELLOW}%-3s %-8s %-8s %-30s %-15s %s${RESET}\n" "Key" "Number" "Ch ID" "Channel Name" "Group" "Station ID"
    echo "--------------------------------------------------------------------------------"
    
    # Store channels for selection
    local page_channels=()
    local key_letters=("a" "b" "c" "d" "e" "f" "g" "h" "i" "j")
    local result_count=0
    
    # Display results with letter keys
    for ((i = offset; i < offset + results_per_page && i < total_missing; i++)); do
      IFS=$'\t' read -r id name group number <<< "${missing_array[$i]}"
      
      [[ -z "$id" ]] && continue
      
      # Convert group ID to group name
      local group_name=$(get_group_name "$group")
      
      local key="${key_letters[$result_count]}"
      
      printf "${GREEN}%-3s${RESET} " "${key})"
      printf "%-8s %-8s %-30s %-15s " "$number" "$id" "${name:0:30}" "${group_name:0:15}"
      echo -e "${RED}Missing${RESET}"
      
      # Store channel data as JSON
      local channel_json=$(jq -n \
        --arg id "$id" \
        --arg name "$name" \
        --arg group "$group" \
        --arg group_name "$group_name" \
        --arg number "$number" \
        '{
          id: $id,
          name: $name,
          channel_group_id: $group,
          channel_group_name: $group_name,
          channel_number: ($number | tonumber)
        }')
      
      page_channels+=("$channel_json")
      ((result_count++))
    done
    
    echo
    echo -e "${BOLD}Channel Selection:${RESET}"
    if [[ $result_count -gt 0 ]]; then
      echo -e "${GREEN}a-j)${RESET} Process specific channel directly ${CYAN}(skip to interactive matching)${RESET}"
    fi
    echo
    echo -e "${BOLD}Navigation Options:${RESET}"
    [[ $current_page -lt $total_pages ]] && echo -e "${GREEN}n)${RESET} Next page"
    [[ $current_page -gt 1 ]] && echo -e "${GREEN}p)${RESET} Previous page"
    echo -e "${GREEN}m)${RESET} Go to Interactive Station ID Matching ${CYAN}(process all channels)${RESET}"
    echo -e "${GREEN}q)${RESET} Back to Dispatcharr Integration menu"
    echo
    
    read -p "Select option: " choice < /dev/tty
    
    case "$choice" in
      a|A|b|B|c|C|d|D|e|E|f|F|g|G|h|H|i|I|j|J)
        if [[ $result_count -gt 0 ]]; then
          local letter_lower=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
          local index=-1
          for ((idx=0; idx<10; idx++)); do
            if [[ "${key_letters[$idx]}" == "$letter_lower" ]]; then
              index=$idx
              break
            fi
          done
          
          if [[ $index -ge 0 ]] && [[ $index -lt $result_count ]]; then
            local selected_channel_json="${page_channels[$index]}"
            
            local sel_id=$(echo "$selected_channel_json" | jq -r '.id')
            local sel_name=$(echo "$selected_channel_json" | jq -r '.name // "Unnamed"')
            local sel_group=$(echo "$selected_channel_json" | jq -r '.channel_group_id // "Ungrouped"')
            local sel_group_name=$(echo "$selected_channel_json" | jq -r '.channel_group_name // "Ungrouped"')
            local sel_number=$(echo "$selected_channel_json" | jq -r '.channel_number // "N/A"')
            
            echo
            echo -e "${BOLD}${GREEN}Selected Channel:${RESET}"
            echo -e "Channel Name: ${YELLOW}$sel_name${RESET}"
            echo -e "Channel ID: ${CYAN}$sel_id${RESET}"
            echo -e "Number: ${CYAN}$sel_number${RESET}"
            echo -e "Group: ${CYAN}$sel_group_name${RESET}"
            echo
            
            if confirm_action "Process station ID matching for this channel?"; then
              echo -e "${CYAN}🔄 Starting direct channel processing...${RESET}"
              sleep 1
              
              process_single_channel_station_id "$selected_channel_json"
              local process_result=$?
              
              case $process_result in
                0)
                  echo -e "\n${GREEN}✅ Channel processing completed successfully${RESET}"
                  echo -e "${CYAN}💡 Station ID has been assigned to the channel${RESET}"
                  ;;
                1)
                  echo -e "\n${YELLOW}⚠️  Channel processing was skipped or cancelled${RESET}"
                  ;;
                2)
                  echo -e "\n${RED}❌ Channel processing failed${RESET}"
                  ;;
              esac
              
              echo
              echo -e "${BOLD}${CYAN}Next Steps:${RESET}"
              echo -e "${GREEN}c)${RESET} Continue processing more channels from this list"
              echo -e "${GREEN}m)${RESET} Go to full Interactive Station ID Matching"
              echo -e "${GREEN}q)${RESET} Return to Dispatcharr Integration menu"
              echo
              
              read -p "What would you like to do next? " next_choice < /dev/tty
              
              case "$next_choice" in
                c|C|"")
                  ;;
                m|M)
                  echo -e "${CYAN}🔄 Starting full Interactive Station ID Matching...${RESET}"
                  sleep 1
                  interactive_stationid_matching "skip_intro"
                  return 0
                  ;;
                q|Q)
                  return 0
                  ;;
                *)
                  echo -e "${CYAN}Continuing with channel scan...${RESET}"
                  sleep 1
                  ;;
              esac
            fi
          else
            echo -e "${RED}❌ Invalid selection${RESET}"
            sleep 1
          fi
        else
          echo -e "${RED}❌ No channels available for selection${RESET}"
          sleep 1
        fi
        ;;
      n|N)
        if [[ $current_page -lt $total_pages ]]; then
          offset=$((offset + results_per_page))
        else
          echo -e "${YELLOW}⚠️  Already on last page${RESET}"
          sleep 1
        fi
        ;;
      p|P)
        if [[ $current_page -gt 1 ]]; then
          offset=$((offset - results_per_page))
        else
          echo -e "${YELLOW}⚠️  Already on first page${RESET}"
          sleep 1
        fi
        ;;
      m|M)
        echo -e "${CYAN}🔄 Starting Interactive Station ID Matching...${RESET}"
        sleep 1
        interactive_stationid_matching "skip_intro"
        return 0
        ;;
      q|Q|"")
        return 0
        ;;
      *)
        echo -e "${RED}❌ Invalid option. Please try again.${RESET}"
        sleep 1
        ;;
    esac
  done
  
  echo
  echo -e "${BOLD}${CYAN}Next Steps:${RESET}"
  echo -e "• Use 'Interactive Station ID Matching' to assign station IDs"
  echo -e "• Each channel will be matched against your Local Database Search"
  echo -e "• Choose immediate apply or batch mode for changes"
  echo -e "${GREEN}💡 Tip: Start with a few channels to test the workflow${RESET}"
  
  return 0
}

# Process a single channel for station ID assignment (called from scan results)
process_single_channel_station_id() {
  local channel_data="$1"
  
  # Extract channel information exactly like process_single_channel_fields does
  local channel_id=$(echo "$channel_data" | jq -r '.id')
  local channel_name=$(echo "$channel_data" | jq -r '.name // "Unnamed"')
  local channel_number=$(echo "$channel_data" | jq -r '.channel_number // "N/A"')
  local channel_group=$(echo "$channel_data" | jq -r '.channel_group_id // "Ungrouped"')
  local channel_group_name=$(echo "$channel_data" | jq -r '.channel_group_name // "Ungrouped"')
  local current_tvc_stationid=$(echo "$channel_data" | jq -r '.tvc_guide_stationid // ""')
  
  # Validate database access
  if ! has_stations_database; then
    echo -e "${RED}❌ Local Database Search: No station data available${RESET}"
    echo -e "${CYAN}💡 Cannot process channel without station database${RESET}"
    return 2
  fi
  
  # Parse the channel name using existing parsing rules
  local parsed_data=$(parse_channel_name "$channel_name")
  IFS='|' read -r clean_name detected_country detected_resolution <<< "$parsed_data"
  
  # Fallback to original channel name if parsing didn't extract a useful clean name
  if [[ -z "$clean_name" || "$clean_name" == "null" || "$clean_name" == "" ]]; then
    clean_name="$channel_name"
  fi
  
  # Main processing loop for this specific channel
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== Direct Channel Station ID Assignment ===${RESET}\n"
    
    echo -e "${BOLD}Selected Channel: ${YELLOW}$channel_name${RESET}"
    echo -e "Group: $channel_group_name | Number: $channel_number | ID: $channel_id"
    echo
    
    # Show parsing results if anything was detected
    if [[ -n "$detected_country" ]] || [[ -n "$detected_resolution" ]] || [[ "$clean_name" != "$channel_name" ]]; then
      echo -e "${BOLD}${BLUE}Smart Parsing Results:${RESET}"
      echo -e "Original: ${YELLOW}$channel_name${RESET}"
      echo -e "Cleaned:  ${GREEN}$clean_name${RESET}"
      [[ -n "$detected_country" ]] && echo -e "Country:  ${GREEN}$detected_country${RESET} (auto-detected)"
      [[ -n "$detected_resolution" ]] && echo -e "Quality:  ${GREEN}$detected_resolution${RESET} (auto-detected)"
      echo -e "${CYAN}💡 Searching with cleaned name and auto-detected filters...${RESET}"
      echo
    else
      echo -e "${BOLD}${BLUE}Search Strategy:${RESET}"
      echo -e "Search Term: ${GREEN}$clean_name${RESET}"
      echo -e "${CYAN}💡 Using channel name as-is (no parsing changes detected)${RESET}"
      echo
    fi
    
    # Use clean name for initial search
    local search_term="$clean_name"
    local current_page=1
    
    # Search and display loop
    while true; do
      echo -e "${CYAN}🔍 Searching for: '$search_term' (Page $current_page)${RESET}"
      
      # Show active filters
      local filter_status=""
      if [[ -n "$detected_country" ]]; then
        filter_status+="Country: $detected_country (auto) "
      fi
      if [[ -n "$detected_resolution" ]]; then
        filter_status+="Quality: $detected_resolution (auto) "
      fi
      if [[ -n "$filter_status" ]]; then
        echo -e "${BLUE}Active Filters: $filter_status${RESET}"
      else
        echo -e "${CYAN}🔍 No auto-filters active - searching all available stations${RESET}"
      fi
      echo
      
      # Get search results with auto-detected filters
      local results
      results=$(search_stations_by_name "$search_term" "$current_page" "$detected_country" "$detected_resolution")
      
      local total_results
      total_results=$(get_total_search_results "$search_term" "$detected_country" "$detected_resolution")
      
      if [[ -z "$results" ]]; then
        echo -e "${YELLOW}⚠️  No results found for '$search_term'${RESET}"
        if [[ -n "$detected_country" ]] || [[ -n "$detected_resolution" ]]; then
          echo -e "${CYAN}💡 Try 's' to search with different term or filters${RESET}"
        fi
      else
        echo -e "${GREEN}✅ Found $total_results total results${RESET}"
        echo
        
        # Enhanced table header with selection highlighting
        printf "${BOLD}${YELLOW}%-3s %-12s %-30s %-10s %-8s %s${RESET}\n" "Key" "Station ID" "Channel Name" "Call Sign" "Quality" "Country"
        echo "--------------------------------------------------------------------------------"
        
        local station_array=()
        local key_letters=("a" "b" "c" "d" "e" "f" "g" "h" "i" "j")
        local result_count=0
        
        # Process TSV results with selection highlighting
        while IFS=$'\t' read -r station_id name call_sign country; do
          [[ -z "$station_id" ]] && continue
          
          # Get additional station info for better display
          local quality=$(get_station_quality "$station_id")
          
          local key="${key_letters[$result_count]}"
          
          # Format table row with selection highlighting
          printf "${GREEN}%-3s${RESET} " "${key})"
          echo -n -e "${CYAN}${station_id}${RESET}"
          printf "%*s" $((12 - ${#station_id})) ""
          printf "%-30s %-10s %-8s " "${name:0:30}" "${call_sign:0:10}" "${quality:0:8}"
          echo -e "${GREEN}${country}${RESET}"
          
          # Display logo if enabled
          if [[ "$SHOW_LOGOS" == true ]]; then
            display_logo "$station_id"
          else
            echo "[logo previews disabled]"
          fi
          echo
          
          station_array+=("$station_id|$name|$call_sign|$country|$quality")
          ((result_count++))
        done <<< "$results"
      fi
      
      # Calculate pagination info
      local total_pages=$(( (total_results + 9) / 10 ))
      [[ $total_pages -eq 0 ]] && total_pages=1
      
      echo -e "${BOLD}Page $current_page of $total_pages${RESET}"
      echo
      echo -e "${BOLD}Options:${RESET}"
      [[ $result_count -gt 0 ]] && echo "a-j) Select a station from the results above"
      [[ $current_page -lt $total_pages ]] && echo "n) Next page"
      [[ $current_page -gt 1 ]] && echo "p) Previous page"
      echo "s) Search with different term"
      echo "m) Enter station ID manually"
      echo "k) Skip this channel (return to scan results)"
      echo "q) Cancel and return to Dispatcharr menu"
      echo
      
      read -p "Your choice: " choice < /dev/tty
      
      case "$choice" in
        a|A|b|B|c|C|d|D|e|E|f|F|g|G|h|H|i|I|j|J)
          if [[ $result_count -gt 0 ]]; then
            # Convert letter to array index
            local letter_lower=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
            local index=-1
            for ((idx=0; idx<10; idx++)); do
              if [[ "${key_letters[$idx]}" == "$letter_lower" ]]; then
                index=$idx
                break
              fi
            done
            
            if [[ $index -ge 0 ]] && [[ $index -lt $result_count ]]; then
              local selected="${station_array[$index]}"
              IFS='|' read -r sel_station_id sel_name sel_call sel_country sel_quality <<< "$selected"
              
              echo
              echo -e "${BOLD}Confirm Station ID Assignment:${RESET}"
              echo -e "Channel: ${YELLOW}$channel_name${RESET}"
              echo -e "Station: ${GREEN}$sel_name${RESET} (${CYAN}$sel_station_id${RESET})"
              echo -e "Call Sign: ${GREEN}$sel_call${RESET}"
              echo -e "Country: ${GREEN}$sel_country${RESET}"
              echo -e "Quality: ${GREEN}$sel_quality${RESET}"
              echo
              
              if confirm_action "Apply this station ID to the channel?"; then
                echo -e "${CYAN}🔄 Updating channel in Dispatcharr...${RESET}"
                if update_dispatcharr_channel_station_id "$channel_id" "$sel_station_id"; then
                  echo -e "${GREEN}✅ Channel updated successfully in Dispatcharr${RESET}"
                  echo -e "${CYAN}💡 Channel $channel_name now has station ID $sel_station_id${RESET}"
                  pause_for_user
                  return 0  # Success
                else
                  echo -e "${RED}❌ Failed to update channel in Dispatcharr${RESET}"
                  pause_for_user
                  return 2  # Failure
                fi
              fi
            else
              echo -e "${RED}❌ Invalid selection${RESET}"
              sleep 1
            fi
          else
            echo -e "${RED}❌ No results to select from${RESET}"
            sleep 1
          fi
          ;;
        n|N)
          if [[ $current_page -lt $total_pages ]]; then
            ((current_page++))
          else
            echo -e "${YELLOW}⚠️  Already on last page${RESET}"
            sleep 1
          fi
          ;;
        p|P)
          if [[ $current_page -gt 1 ]]; then
            ((current_page--))
          else
            echo -e "${YELLOW}⚠️  Already on first page${RESET}"
            sleep 1
          fi
          ;;
        s|S)
          read -p "Enter new search term: " new_search < /dev/tty
          if [[ -n "$new_search" ]]; then
            search_term="$new_search"
            current_page=1
            # Clear auto-detected filters when user enters manual search
            detected_country=""
            detected_resolution=""
            echo -e "${CYAN}💡 Auto-detected filters cleared for manual search${RESET}"
          fi
          ;;
        m|M)
          read -p "Enter station ID manually: " manual_station_id < /dev/tty
          if [[ -n "$manual_station_id" ]]; then
            echo
            echo -e "${BOLD}Confirm Manual Station ID:${RESET}"
            echo -e "Channel: ${YELLOW}$channel_name${RESET}"
            echo -e "Station ID: ${CYAN}$manual_station_id${RESET} (manual entry)"
            echo
            
            if confirm_action "Apply manual station ID to the channel?"; then
              echo -e "${CYAN}🔄 Updating channel in Dispatcharr...${RESET}"
              if update_dispatcharr_channel_station_id "$channel_id" "$manual_station_id"; then
                echo -e "${GREEN}✅ Manual station ID applied successfully${RESET}"
                echo -e "${CYAN}💡 Channel $channel_name now has station ID $manual_station_id${RESET}"
                pause_for_user
                return 0  # Success
              else
                echo -e "${RED}❌ Failed to update channel in Dispatcharr${RESET}"
                pause_for_user
                return 2  # Failure
              fi
            fi
          fi
          ;;
        k|K)
          echo -e "${YELLOW}⚠️  Skipped: $channel_name${RESET}"
          return 1  # Skipped
          ;;
        q|Q)
          echo -e "${CYAN}🔄 Returning to Dispatcharr Integration menu...${RESET}"
          return 1  # Cancelled
          ;;
        *)
          echo -e "${RED}❌ Invalid option. Please try again.${RESET}"
          sleep 1
          ;;
      esac
    done
  done
}

interactive_stationid_matching() {
  local skip_intro="${1:-}"  # Optional parameter to skip intro pause
  
  if ! dispatcharr_test_connection >/dev/null 2>&1; then
    echo -e "${RED}❌ Dispatcharr Integration: Connection Failed${RESET}"
    echo -e "${CYAN}💡 Configure connection in Settings → Dispatcharr Integration${RESET}"
    echo -e "${CYAN}💡 Verify server is running and credentials are correct${RESET}"
    pause_for_user
    return 1
  fi
  
  if ! has_stations_database; then
    echo -e "${RED}❌ Local Database Search: No station data available${RESET}"
    echo -e "${CYAN}💡 Base Station Database: Add $(basename "$BASE_STATIONS_JSON") to script directory${RESET}"
    echo -e "${CYAN}💡 User Station Database: Use 'Manage Television Markets' → 'Run User Caching'${RESET}"
    pause_for_user
    return 1
  fi
  
  echo -e "${BLUE}📍 Step 2 of 3: Interactive Station ID Assignment${RESET}"
  echo -e "${CYAN}This workflow will guide you through matching Dispatcharr channels with stations from your Local Database Search.${RESET}"
  echo
  
  echo -e "${CYAN}📡 Fetching channels from Dispatcharr...${RESET}"
  local channels_data
  channels_data=$(get_dispatcharr_channels)
  
  if [[ -z "$channels_data" ]]; then
    echo -e "${RED}❌ Failed to retrieve channels from Dispatcharr${RESET}"
    echo -e "${CYAN}💡 Check Dispatcharr connection and try again${RESET}"
    pause_for_user
    return 1
  fi
  
  local missing_channels
  missing_channels=$(find_channels_missing_stationid "$channels_data")
  
  if [[ -z "$missing_channels" ]]; then
    echo -e "${GREEN}✅ All channels have station IDs assigned!${RESET}"
    echo -e "${CYAN}💡 Use 'Populate Other Dispatcharr Fields' to enhance channel data${RESET}"
    pause_for_user
    return 0
  fi
  
  # Clear previous matches file
  > "$DISPATCHARR_MATCHES"
  
  # Convert to array
  mapfile -t missing_array <<< "$missing_channels"
  local total_missing=${#missing_array[@]}
  
  echo -e "${GREEN}✅ Found $total_missing channels needing station IDs${RESET}"
  
  # USER CHOICE: Immediate or Batch Mode
  echo
  echo -e "${BOLD}${BLUE}=== Station ID Application Mode ===${RESET}"
  echo -e "${YELLOW}How would you like to apply station ID matches to Dispatcharr?${RESET}"
  echo
  echo -e "${GREEN}1) Immediate Mode${RESET} - Apply each match as you make it"
  echo -e "   ${CYAN}✓ Changes take effect immediately in Dispatcharr${RESET}"
  echo -e "   ${CYAN}✓ No separate commit step needed${RESET}"
  echo -e "   ${CYAN}✓ Can see results in Dispatcharr right away${RESET}"
  echo -e "   ${YELLOW}⚠️  Cannot undo individual changes${RESET}"
  echo
  echo -e "${GREEN}2) Batch Mode${RESET} - Queue matches for review and batch commit"
  echo -e "   ${CYAN}✓ Review all matches before applying to Dispatcharr${RESET}"
  echo -e "   ${CYAN}✓ Apply all changes at once${RESET}"
  echo -e "   ${CYAN}✓ Can cancel or modify before commit${RESET}"
  echo -e "   ${YELLOW}⚠️  Changes don't appear in Dispatcharr until commit${RESET}"
  echo
  
  local apply_mode=""
  while [[ -z "$apply_mode" ]]; do
    read -p "Select mode (1=immediate, 2=batch): " mode_choice
    case "$mode_choice" in
      1) apply_mode="immediate" ;;
      2) apply_mode="batch" ;;
      *) echo -e "${RED}❌ Please enter 1 or 2${RESET}" ;;
    esac
  done
  
  echo
  if [[ "$apply_mode" == "immediate" ]]; then
    echo -e "${GREEN}✅ Immediate Mode selected - changes will apply as you make them${RESET}"
  else
    echo -e "${GREEN}✅ Batch Mode selected - changes will be queued for review${RESET}"
  fi
  
  # Only show intro pause if not called from scan function
  if [[ "$skip_intro" != "skip_intro" ]]; then
    echo -e "${CYAN}🔄 Starting interactive matching process...${RESET}"
    pause_for_user
  else
    echo -e "${CYAN}🔄 Ready to start matching process...${RESET}"
    sleep 1  # Brief pause for visual feedback
  fi
  
  local immediate_success_count=0
  local immediate_failure_count=0
  
  for ((i = 0; i < total_missing; i++)); do
    IFS=$'\t' read -r channel_id channel_name group number <<< "${missing_array[$i]}"
    
    # Skip empty lines
    [[ -z "$channel_id" ]] && continue
    
    # Parse the channel name to extract country, resolution, and clean name
    local parsed_data=$(parse_channel_name "$channel_name")
    IFS='|' read -r clean_name detected_country detected_resolution <<< "$parsed_data"
    
    # Main matching loop for this channel
    while true; do
      clear
      echo -e "${BOLD}${CYAN}=== Channel Station ID Assignment ===${RESET}\n"
      
      # Show mode indicator
      if [[ "$apply_mode" == "immediate" ]]; then
        echo -e "${GREEN}Mode: Immediate Apply${RESET} | Success: $immediate_success_count | Failed: $immediate_failure_count"
      else
        local queued_count
        queued_count=$(wc -l < "$DISPATCHARR_MATCHES" 2>/dev/null || echo "0")
        echo -e "${BLUE}Mode: Batch Queue${RESET} | Queued: $queued_count matches"
      fi
      echo
      
      echo -e "${BOLD}Channel: ${YELLOW}$channel_name${RESET}"
      echo -e "Group: $group | Number: $number | ID: $channel_id"
      echo -e "Progress: $((i + 1)) of $total_missing"
      echo
      
      # Show parsing results if anything was detected
      if [[ -n "$detected_country" ]] || [[ -n "$detected_resolution" ]] || [[ "$clean_name" != "$channel_name" ]]; then
        echo -e "${BOLD}${BLUE}Smart Parsing Results:${RESET}"
        echo -e "Original: ${YELLOW}$channel_name${RESET}"
        echo -e "Cleaned:  ${GREEN}$clean_name${RESET}"
        [[ -n "$detected_country" ]] && echo -e "Country:  ${GREEN}$detected_country${RESET} (auto-detected)"
        [[ -n "$detected_resolution" ]] && echo -e "Quality:  ${GREEN}$detected_resolution${RESET} (auto-detected)"
        echo -e "${CYAN}💡 Searching with cleaned name and auto-detected filters...${RESET}"
        echo
      fi
      
      # Use clean name for initial search
      local search_term="$clean_name"
      local current_page=1
      
      # Search and display loop
      while true; do
        echo -e "${CYAN}🔍 Searching for: '$search_term' (Page $current_page)${RESET}"
        
    echo -e "${CYAN}Searching for: '$search_term' (Page $current_page)${RESET}"
    
        # Show active filters - UPDATED
        local filter_status=""
        if [[ -n "$detected_country" ]]; then
          filter_status+="Country: $detected_country (auto) "
        fi
        if [[ -n "$detected_resolution" ]]; then
          filter_status+="Quality: $detected_resolution (auto) "
        fi
        if [[ -n "$filter_status" ]]; then
          echo -e "${BLUE}Active Filters: $filter_status${RESET}"
        else
          echo -e "${CYAN}🔍 No auto-filters active - searching all available stations${RESET}"
        fi
        echo
            
        # Get search results with auto-detected filters
        local results
        results=$(search_stations_by_name "$search_term" "$current_page" "$detected_country" "$detected_resolution")
        
        local total_results
        total_results=$(get_total_search_results "$search_term" "$detected_country" "$detected_resolution")
        
        if [[ -z "$results" ]]; then
          echo -e "${YELLOW}⚠️  No results found for '$search_term'${RESET}"
          if [[ -n "$detected_country" ]] || [[ -n "$detected_resolution" ]]; then
            echo -e "${CYAN}💡 Try 's' to search with different term or filters${RESET}"
          fi
        else
          echo -e "${GREEN}✅ Found $total_results total results${RESET}"
          echo
          
          # Enhanced table header with FIXED selection highlighting
          printf "${BOLD}${YELLOW}%-3s %-12s %-30s %-10s %-8s %s${RESET}\n" "Key" "Station ID" "Channel Name" "Call Sign" "Quality" "Country"
          echo "--------------------------------------------------------------------------------"
          
          local station_array=()
          local key_letters=("a" "b" "c" "d" "e" "f" "g" "h" "i" "j")
          local result_count=0
          
          # Process TSV results with FIXED selection highlighting
          while IFS=$'\t' read -r station_id name call_sign country; do
            [[ -z "$station_id" ]] && continue
            
            # Get additional station info for better display
            local quality=$(get_station_quality "$station_id")
            
            local key="${key_letters[$result_count]}"
            
            # Format table row with CONSISTENT selection highlighting
            printf "${GREEN}%-3s${RESET} " "${key})"
            echo -n -e "${CYAN}${station_id}${RESET}"
            printf "%*s" $((12 - ${#station_id})) ""
            printf "%-30s %-10s %-8s " "${name:0:30}" "${call_sign:0:10}" "${quality:0:8}"
            echo -e "${GREEN}${country}${RESET}"
            
            # Display logo if enabled
            if [[ "$SHOW_LOGOS" == true ]]; then
              display_logo "$station_id"
            else
              echo "[logo previews disabled]"
            fi
            echo
            
            station_array+=("$station_id|$name|$call_sign|$country|$quality")
            ((result_count++))
          done <<< "$results"
        fi
        
        # Calculate pagination info
        local total_pages=$(( (total_results + 9) / 10 ))
        [[ $total_pages -eq 0 ]] && total_pages=1
        
        echo -e "${BOLD}Page $current_page of $total_pages${RESET}"
        echo
        echo -e "${BOLD}Options:${RESET}"
        [[ $result_count -gt 0 ]] && echo "a-j) Select a station from the results above"
        [[ $current_page -lt $total_pages ]] && echo "n) Next page"
        [[ $current_page -gt 1 ]] && echo "p) Previous page"
        echo "s) Search with different term"
        echo "m) Enter station ID manually"
        echo "k) Skip this channel"
        echo "q) Quit matching"
        echo

        maintain_session_tokens
        
        read -p "Your choice: " choice < /dev/tty
        
        case "$choice" in
          a|A|b|B|c|C|d|D|e|E|f|F|g|G|h|H|i|I|j|J)
            if [[ $result_count -gt 0 ]]; then
              # Convert letter to array index
              local letter_lower=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
              local index=-1
              for ((idx=0; idx<10; idx++)); do
                if [[ "${key_letters[$idx]}" == "$letter_lower" ]]; then
                  index=$idx
                  break
                fi
              done
              
              if [[ $index -ge 0 ]] && [[ $index -lt $result_count ]]; then
                local selected="${station_array[$index]}"
                IFS='|' read -r sel_station_id sel_name sel_call sel_country sel_quality <<< "$selected"
                
                echo
                echo -e "${BOLD}Confirm Station ID Assignment:${RESET}"
                echo -e "Channel: ${YELLOW}$channel_name${RESET}"
                echo -e "Station: ${GREEN}$sel_name${RESET} (${CYAN}$sel_station_id${RESET})"
                echo -e "Call Sign: ${GREEN}$sel_call${RESET}"
                echo -e "Country: ${GREEN}$sel_country${RESET}"
                echo -e "Quality: ${GREEN}$sel_quality${RESET}"
                echo
                
                # APPLY MODE LOGIC: Immediate vs Batch
                if [[ "$apply_mode" == "immediate" ]]; then
                  if confirm_action "Apply this station ID immediately to Dispatcharr?"; then
                    echo -e "${CYAN}🔄 Updating channel in Dispatcharr...${RESET}"
                    if update_dispatcharr_channel_station_id "$channel_id" "$sel_station_id"; then
                      echo -e "${GREEN}✅ Channel updated successfully in Dispatcharr${RESET}"
                      ((immediate_success_count++))
                      # Also record for logging
                      echo -e "$channel_id\t$channel_name\t$sel_station_id\t$sel_name\t100" >> "$DISPATCHARR_MATCHES"
                    else
                      echo -e "${RED}❌ Failed to update channel in Dispatcharr${RESET}"
                      ((immediate_failure_count++))
                    fi
                    pause_for_user
                    break 2  # Exit both loops, move to next channel
                  fi
                else
                  if confirm_action "Queue this match for batch commit to Dispatcharr?"; then
                    echo -e "$channel_id\t$channel_name\t$sel_station_id\t$sel_name\t100" >> "$DISPATCHARR_MATCHES"
                    echo -e "${GREEN}✅ Match queued for batch commit${RESET}"
                    sleep 1
                    break 2  # Exit both loops, move to next channel
                  fi
                fi
              else
                echo -e "${RED}❌ Invalid selection${RESET}"
                sleep 1
              fi
            else
              echo -e "${RED}❌ No results to select from${RESET}"
              sleep 1
            fi
            ;;
          n|N)
            if [[ $current_page -lt $total_pages ]]; then
              ((current_page++))
            else
              echo -e "${YELLOW}⚠️  Already on last page${RESET}"
              sleep 1
            fi
            ;;
          p|P)
            if [[ $current_page -gt 1 ]]; then
              ((current_page--))
            else
              echo -e "${YELLOW}⚠️  Already on first page${RESET}"
              sleep 1
            fi
            ;;
          s|S)
            read -p "Enter new search term: " new_search < /dev/tty
            if [[ -n "$new_search" ]]; then
              search_term="$new_search"
              current_page=1
              # FIXED: Clear auto-detected filters when user enters manual search
              detected_country=""
              detected_resolution=""
              echo -e "${CYAN}💡 Auto-detected filters cleared for manual search${RESET}"
            fi
            ;;
          m|M)
            read -p "Enter station ID manually: " manual_station_id < /dev/tty
            if [[ -n "$manual_station_id" ]]; then
              echo
              echo -e "${BOLD}Confirm Manual Station ID:${RESET}"
              echo -e "Channel: ${YELLOW}$channel_name${RESET}"
              echo -e "Station ID: ${CYAN}$manual_station_id${RESET} (manual entry)"
              echo
              
              if [[ "$apply_mode" == "immediate" ]]; then
                if confirm_action "Apply manual station ID immediately to Dispatcharr?"; then
                  echo -e "${CYAN}🔄 Updating channel in Dispatcharr...${RESET}"
                  if update_dispatcharr_channel_station_id "$channel_id" "$manual_station_id"; then
                    echo -e "${GREEN}✅ Manual station ID applied successfully${RESET}"
                    ((immediate_success_count++))
                    echo -e "$channel_id\t$channel_name\t$manual_station_id\tManual Entry\t100" >> "$DISPATCHARR_MATCHES"
                  else
                    echo -e "${RED}❌ Failed to update channel in Dispatcharr${RESET}"
                    ((immediate_failure_count++))
                  fi
                  pause_for_user
                fi
              else
                if confirm_action "Queue manual station ID for batch commit?"; then
                  echo -e "$channel_id\t$channel_name\t$manual_station_id\tManual Entry\t100" >> "$DISPATCHARR_MATCHES"
                  echo -e "${GREEN}✅ Manual station ID queued for batch commit${RESET}"
                  sleep 1
                fi
              fi
              break 2  # Exit both loops, move to next channel
            fi
            ;;
          k|K)
            echo -e "${YELLOW}⚠️  Skipped: $channel_name${RESET}"
            sleep 1
            break 2  # Exit both loops, move to next channel
            ;;
          q|Q)
            echo -e "${CYAN}🔄 Ending matching session...${RESET}"
            # Check for pending matches or show immediate results
            if [[ "$apply_mode" == "immediate" ]]; then
              show_immediate_results "$immediate_success_count" "$immediate_failure_count"
            else
              check_and_offer_commit
            fi
            return 0
            ;;
          *)
            echo -e "${RED}❌ Invalid option. Please try again.${RESET}"
            sleep 1
            ;;
        esac
      done
    done
  done
  
  echo -e "\n${GREEN}✅ Matching session completed${RESET}"
  
  # FINAL RESULTS BASED ON MODE
  if [[ "$apply_mode" == "immediate" ]]; then
    show_immediate_results "$immediate_success_count" "$immediate_failure_count"
  else
    # AUTO-FLOW TO COMMIT IF MATCHES EXIST
    check_and_offer_commit
  fi
}

show_immediate_results() {
  local success_count="$1"
  local failure_count="$2"
  
  echo
  echo -e "${BOLD}${GREEN}=== Immediate Mode Results ===${RESET}"
  echo -e "${GREEN}✅ Successfully applied: $success_count station IDs${RESET}"
  [[ $failure_count -gt 0 ]] && echo -e "${RED}❌ Failed to apply: $failure_count station IDs${RESET}"
  echo -e "${CYAN}All changes have been applied immediately to Dispatcharr${RESET}"
  
  if [[ -f "$DISPATCHARR_MATCHES" ]] && [[ -s "$DISPATCHARR_MATCHES" ]]; then
    echo -e "${CYAN}📋 Session log saved for reference${RESET}"
  fi
}

check_and_offer_commit() {
  if [[ -f "$DISPATCHARR_MATCHES" ]] && [[ -s "$DISPATCHARR_MATCHES" ]]; then
    local match_count
    match_count=$(wc -l < "$DISPATCHARR_MATCHES")
    
    echo
    echo -e "${CYAN}📋 Found $match_count queued station ID matches${RESET}"
    
    if confirm_action "Review and commit these station ID changes now?"; then
      echo -e "${GREEN}Opening commit screen...${RESET}"
      sleep 1
      batch_update_stationids
    else
      echo -e "${CYAN}Matches saved. Use 'Commit Station ID Changes' later to apply them.${RESET}"
    fi
  else
    echo -e "${CYAN}No station ID matches were queued${RESET}"
  fi
}

batch_update_stationids() {
  echo -e "\n${BOLD}${BLUE}📍 Step 3 of 3: Commit Station ID Changes${RESET}"
  echo -e "${CYAN}This will apply all queued station ID matches to your Dispatcharr channels.${RESET}"
  echo
  
  if [[ ! -f "$DISPATCHARR_MATCHES" ]] || [[ ! -s "$DISPATCHARR_MATCHES" ]]; then
    echo -e "${YELLOW}⚠️  No pending station ID matches found${RESET}"
    echo -e "${CYAN}💡 Run 'Interactive Station ID Matching' first to create matches${RESET}"
    echo -e "${CYAN}💡 Ensure you selected 'Batch Mode' during the matching process${RESET}"
    return 1
  fi
  
  local total_matches
  total_matches=$(wc -l < "$DISPATCHARR_MATCHES")
  
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
    return 1
  fi
  
  local success_count=0
  local failure_count=0
  local current_item=0
  
  prepare_for_batch_operations "station ID updates" $((total_matches * 3))

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
    
    if update_dispatcharr_channel_station_id "$channel_id" "$station_id"; then
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
  
  return 0
}

populate_dispatcharr_fields() {
  if ! dispatcharr_test_connection >/dev/null 2>&1; then
    echo -e "${RED}❌ Dispatcharr Integration: Connection Failed${RESET}"
    echo -e "${CYAN}💡 Configure connection in Settings → Dispatcharr Integration${RESET}"
    echo -e "${CYAN}💡 Verify server is running and credentials are correct${RESET}"
    pause_for_user
    return 1
  fi
  
  if ! has_stations_database; then
    echo -e "${RED}❌ Local Database Search: No station data available${RESET}"
    echo -e "${CYAN}💡 Base Station Database: Add $(basename "$BASE_STATIONS_JSON") to script directory${RESET}"
    echo -e "${CYAN}💡 User Station Database: Use 'Manage Television Markets' → 'Run User Caching'${RESET}"
    pause_for_user
    return 1
  fi
  
  clear
  echo -e "${BOLD}${CYAN}=== Populate Other Dispatcharr Fields ===${RESET}\n"
  echo -e "${BLUE}📍 Step 2 of 3: Enhance Dispatcharr Channel Data${RESET}"
  echo -e "${YELLOW}This workflow enhances your Dispatcharr channels with comprehensive station information.${RESET}"
  echo
  
  echo -e "${BOLD}How It Works:${RESET}"
  echo -e "${CYAN}1. Select channels to process (all, filtered, specific, or automatic)${RESET}"
  echo -e "${CYAN}2. For each channel, match against your Local Database (channels with statoinId will auto-match)${RESET}"
  echo -e "${CYAN}3. Review proposed field updates and select which to apply${RESET}"
  echo -e "${CYAN}4. Changes are applied immediately to Dispatcharr${RESET}"
  echo
  
  echo -e "${BOLD}Fields that can be populated:${RESET}"
  echo -e "${GREEN}• Channel Name${RESET}"
  echo -e "${GREEN}• TVG-ID${RESET} (Set to station call sign for proper EPG matching in certain software)"
  echo -e "${GREEN}• Channel Logo${RESET}"
  echo
  
  echo -e "${CYAN}📡 Fetching all channels from Dispatcharr...${RESET}"
  local channels_data
  channels_data=$(get_dispatcharr_channels)
  
  if [[ -z "$channels_data" ]]; then
    echo -e "${RED}❌ Failed to retrieve channels from Dispatcharr${RESET}"
    echo -e "${CYAN}💡 Check Dispatcharr connection and try again${RESET}"
    pause_for_user
    return 1
  fi
  
  local total_channels=$(echo "$channels_data" | jq 'length')
  echo -e "${GREEN}✅ Retrieved $total_channels channels from Dispatcharr${RESET}"
  echo
  
  # Enhanced channel selection mode with Mode 4
  echo -e "${BOLD}${BLUE}=== Channel Processing Mode ===${RESET}"
  echo -e "${YELLOW}Which channels would you like to process?${RESET}"
  echo
  echo -e "${GREEN}1) Process All Channels${RESET} - Work through every channel systematically"
  echo -e "   ${YELLOW}⚠️  May take time with many channels${RESET}"
  echo
  echo -e "${GREEN}2) Process Channels Missing Specific Fields${RESET}"
  echo -e "   ${CYAN}✓ Choose which missing fields to target${RESET}"
  echo
  echo -e "${GREEN}3) Process Specific Channel${RESET}"
  echo -e "   ${CYAN}✓ Quick single-channel enhancement${RESET}"
  echo
  echo -e "${GREEN}4) Automatic Complete Data Replacement${RESET}"
  echo -e "   ${CYAN}✓ Automatically processes ALL channels that have station IDs${RESET}"
  echo -e "   ${CYAN}✓ Select which fields to update (name, tvg-id, logo)${RESET}"
  echo -e "   ${CYAN}✓ No user interaction required per channel${RESET}"
  echo -e "   ${RED}⚠️  WARNING: Mass replacement of potentially hundreds of channels${RESET}"
  echo
  echo -e "${GREEN}q) Cancel and Return${RESET}"
  echo

  maintain_session_tokens
  
  read -p "Select channel processing mode: " mode_choice
  
  case "$mode_choice" in
    1) 
      echo -e "${GREEN}✅ Processing all channels in ID order${RESET}"
      process_all_channels_fields "$channels_data" 
      ;;
    2) 
      echo -e "${GREEN}✅ Processing channels with missing fields${RESET}"
      process_channels_missing_fields "$channels_data" 
      ;;
    3) 
      echo -e "${GREEN}✅ Processing specific channel${RESET}"
      process_specific_channel "$channels_data" 
      ;;
    4) 
      echo -e "${GREEN}✅ Starting automatic complete data replacement${RESET}"
      automatic_complete_data_replacement "$channels_data" 
      ;;
    q|Q|"") 
      echo -e "${YELLOW}⚠️  Field population cancelled${RESET}"
      return 0 
      ;;
    *) 
      echo -e "${RED}❌ Invalid option. Please try again.${RESET}"
      sleep 1
      populate_dispatcharr_fields  # Restart the function
      ;;
  esac
}

process_all_channels_fields() {
  local channels_json="$1"
  
  echo -e "\n${BOLD}${CYAN}=== Processing All Channels ===${RESET}"
  echo -e "${CYAN}Organizing channels by channel number for systematic processing...${RESET}"
  
  # Sort channels by .channel_number (lowest to highest) - explicit numeric sort
  local sorted_channels
  sorted_channels=$(echo "$channels_json" | jq -c '.[] | select(.id != null)' | jq -s 'sort_by(.channel_number | tonumber)' | jq -c '.[]')
  
  if [[ -z "$sorted_channels" ]]; then
    echo -e "${RED}❌ No channels with valid IDs found${RESET}"
    echo -e "${CYAN}💡 Check Dispatcharr channel configuration${RESET}"
    pause_for_user
    return 1
  fi
  
  mapfile -t channels_array <<< "$sorted_channels"
  local total_channels=${#channels_array[@]}
  
  echo -e "${GREEN}✅ Processing $total_channels channels in channel number order${RESET}"
  echo
  
  # Starting point selection
  local start_index=0
  
  if [[ -n "$LAST_PROCESSED_CHANNEL_NUMBER" ]]; then
    # Simple resume options - no preview, no confirmation
    echo -e "${BOLD}${YELLOW}Resume Options:${RESET}"
    echo -e "${GREEN}1)${RESET} Resume from channel #$LAST_PROCESSED_CHANNEL_NUMBER"
    echo -e "${GREEN}2)${RESET} Start from beginning"
    echo -e "${GREEN}3)${RESET} Start from specific channel"
    echo
    
    local start_choice
    while true; do
      read -p "Select (1-3): " start_choice < /dev/tty
      
      case "$start_choice" in
        1)
          # Resume - find next channel and start immediately
          local next_channel_number
          next_channel_number=$(find_next_channel_number "$LAST_PROCESSED_CHANNEL_NUMBER" channels_array)
          
          if [[ -n "$next_channel_number" ]]; then
            start_index=$(find_channel_index_by_number "$next_channel_number" channels_array)
            if [[ "$start_index" -ge 0 ]]; then
              echo -e "${GREEN}Resuming from channel #$next_channel_number...${RESET}"
              break
            fi
          fi
          
          # Fallback to beginning if resume fails
          echo -e "${YELLOW}Resume failed, starting from beginning...${RESET}"
          start_index=0
          clear_resume_state
          break
          ;;
        2)
          start_index=0
          clear_resume_state
          break
          ;;
        3)
          read -p "Enter channel number: " custom_channel < /dev/tty
          if [[ "$custom_channel" =~ ^[0-9]+$ ]]; then
            local found_index
            found_index=$(find_channel_index_by_number "$custom_channel" channels_array)
            if [[ "$found_index" -ge 0 ]]; then
              start_index=$found_index
              clear_resume_state
              break
            else
              echo -e "${RED}Channel #$custom_channel not found${RESET}"
            fi
          else
            echo -e "${RED}Invalid channel number${RESET}"
          fi
          ;;
        q|Q|"")
          echo -e "${YELLOW}Field population cancelled${RESET}"
          return 0
          ;;
        *)
          echo -e "${RED}Invalid option${RESET}"
          ;;
      esac
    done
  else
    # No resume state - just start from beginning or ask for specific
    echo -e "${BOLD}${YELLOW}Starting Point:${RESET}"
    echo -e "${GREEN}1)${RESET} Start from beginning"
    echo -e "${GREEN}2)${RESET} Start from specific channel"
    echo
    
    local start_choice
    while true; do
      read -p "Select (1-2): " start_choice < /dev/tty
      
      case "$start_choice" in
        1)
          start_index=0
          break
          ;;
        2)
          read -p "Enter channel number: " custom_channel < /dev/tty
          if [[ "$custom_channel" =~ ^[0-9]+$ ]]; then
            local found_index
            found_index=$(find_channel_index_by_number "$custom_channel" channels_array)
            if [[ "$found_index" -ge 0 ]]; then
              start_index=$found_index
              break
            else
              echo -e "${RED}Channel #$custom_channel not found${RESET}"
            fi
          else
            echo -e "${RED}Invalid channel number${RESET}"
          fi
          ;;
        q|Q|"")
          echo -e "${YELLOW}Field population cancelled${RESET}"
          return 0
          ;;
        *)
          echo -e "${RED}Invalid option${RESET}"
          ;;
      esac
    done
  fi
  
  # Immediately start processing - no additional screens or confirmations
  local channels_to_process=$((total_channels - start_index))
  prepare_for_batch_operations "all channels processing" $((channels_to_process * 30))
  
  echo -e "${CYAN}Starting processing...${RESET}"
  echo -e "${YELLOW}💡 Remember: Press 'q' during any channel to stop and save progress${RESET}"
  echo
  
  for ((i = start_index; i < total_channels; i++)); do
    local channel_data="${channels_array[$i]}"
    local channel_number=$(echo "$channel_data" | jq -r '.channel_number // "0"')
    
    # Convert "N/A" or empty to "0" for consistency
    if [[ "$channel_number" == "N/A" || -z "$channel_number" ]]; then
      channel_number="0"
    fi
    
    echo -e "${BOLD}${BLUE}=== Channel $((i + 1)) of $total_channels (Channel #$channel_number) ===${RESET}"
    
    # Process the channel - capture return code to handle user exit
    process_single_channel_fields "$channel_data" $((i + 1)) "$total_channels"
    local process_result=$?
    
    # Check if user chose to quit during processing
    if [[ $process_result -eq 1 ]]; then
      echo -e "\n${YELLOW}⚠️  Processing stopped by user${RESET}"
      echo -e "${CYAN}💡 Progress saved: Completed through channel #$channel_number${RESET}"
      echo -e "${CYAN}💡 Resume anytime by selecting 'Process All Channels' again${RESET}"
      pause_for_user
      return 0
    fi
    
    # SAVE RESUME STATE AFTER SUCCESSFUL COMPLETION
    # Save the completed channel number for resume functionality
    save_resume_state "$channel_number"
    
    # Show progress status but no interruption
    if [[ $((i + 1)) -lt $total_channels ]]; then
      echo
      echo -e "${CYAN}✅ Channel #$channel_number completed. Moving to next channel...${RESET}"
      echo -e "${YELLOW}📊 Progress: $((i + 1)) of $total_channels channels processed${RESET}"
      
      # Brief pause for visual feedback, but no user input required
      sleep 1
    fi
  done
  
  # Clear resume state when all channels are completed
  clear_resume_state
  
  echo -e "\n${GREEN}✅ All channels field population workflow complete${RESET}"
  echo -e "${CYAN}💡 Processed $total_channels channels successfully${RESET}"
  echo -e "${CYAN}💡 Changes have been applied to Dispatcharr as selected${RESET}"
  echo -e "${GREEN}💡 Resume state cleared - all channels completed${RESET}"
  pause_for_user
}

find_channel_index_by_number() {
  local target_channel_number="$1"
  local channels_array_name="$2"  # Changed from channels_array_ref
  
  # Use eval instead of nameref to avoid circular reference
  local total_channels
  eval "total_channels=\${#${channels_array_name}[@]}"
  
  for ((i = 0; i < total_channels; i++)); do
    local channel_data
    eval "channel_data=\${${channels_array_name}[$i]}"
    local channel_number=$(echo "$channel_data" | jq -r '.channel_number // "0"')
    
    # Convert "N/A" or empty to "0" for consistency
    if [[ "$channel_number" == "N/A" || -z "$channel_number" ]]; then
      channel_number="0"
    fi
    
    # Compare as numbers
    if (( channel_number == target_channel_number )); then
      echo "$i"
      return 0
    fi
  done
  
  # Not found
  echo "-1"
  return 1
}

find_next_channel_number() {
  local last_channel_number="$1"
  local channels_array_name="$2"  # Changed from channels_array_ref
  
  local next_channel_number=""
  local smallest_higher_number=""
  
  # Use eval instead of nameref to avoid circular reference
  local total_channels
  eval "total_channels=\${#${channels_array_name}[@]}"
  
  for ((i = 0; i < total_channels; i++)); do
    local channel_data
    eval "channel_data=\${${channels_array_name}[$i]}"
    local channel_number=$(echo "$channel_data" | jq -r '.channel_number // "0"')
    
    # Convert "N/A" or empty to "0" for consistency
    if [[ "$channel_number" == "N/A" || -z "$channel_number" ]]; then
      channel_number="0"
    fi
    
    # Find the smallest channel number that's higher than last_channel_number
    if (( channel_number > last_channel_number )); then
      if [[ -z "$smallest_higher_number" ]] || (( channel_number < smallest_higher_number )); then
        smallest_higher_number="$channel_number"
      fi
    fi
  done
  
  echo "$smallest_higher_number"
}

process_channels_missing_fields() {
  local channels_data="$1"
  
  echo -e "\n${BOLD}${CYAN}=== Filter Channels by Missing Fields ===${RESET}"
  echo -e "${YELLOW}Select which type of missing field to target:${RESET}"
  echo
  echo -e "${GREEN}1)${RESET} Missing Channel Names - Empty or generic names like 'Channel 123'"
  echo -e "   ${CYAN}✓ Improves channel identification${RESET}"
  echo -e "   ${CYAN}✓ Replaces generic names with official station names${RESET}"
  echo
  echo -e "${GREEN}2)${RESET} Missing TVG-ID - Empty TVG-ID fields"
  echo -e "   ${CYAN}✓ Enables proper EPG matching${RESET}"
  echo -e "   ${CYAN}✓ Sets call signs for guide data correlation${RESET}"
  echo
  echo -e "${GREEN}3)${RESET} Missing TVC Guide Station ID - Empty station ID fields"
  echo -e "   ${CYAN}✓ Enables comprehensive guide data${RESET}"
  echo -e "   ${CYAN}✓ Links channels to station information${RESET}"
  echo
  echo -e "${GREEN}4)${RESET} Missing Any of the Above - Channels with any missing field"
  echo -e "   ${CYAN}✓ Comprehensive cleanup approach${RESET}"
  echo -e "   ${CYAN}✓ Addresses all field gaps systematically${RESET}"
  echo
  
  read -p "Select filter criteria: " filter_choice
  
  local filtered_channels
  case "$filter_choice" in
    1)
      echo -e "${CYAN}🔍 Filtering for channels with missing or generic names...${RESET}"
      filtered_channels=$(echo "$channels_data" | jq -c '.[] | select(.name == "" or .name == null or (.name | test("Channel [0-9]+")))')
      ;;
    2)
      echo -e "${CYAN}🔍 Filtering for channels with missing TVG-ID...${RESET}"
      filtered_channels=$(echo "$channels_data" | jq -c '.[] | select(.tvg_id == "" or .tvg_id == null)')
      ;;
    3)
      echo -e "${CYAN}🔍 Filtering for channels with missing TVC Guide Station ID...${RESET}"
      filtered_channels=$(echo "$channels_data" | jq -c '.[] | select(.tvc_guide_stationid == "" or .tvc_guide_stationid == null)')
      ;;
    4)
      echo -e "${CYAN}🔍 Filtering for channels with any missing fields...${RESET}"
      filtered_channels=$(echo "$channels_data" | jq -c '.[] | select(
        (.name == "" or .name == null or (.name | test("Channel [0-9]+"))) or
        (.tvg_id == "" or .tvg_id == null) or
        (.tvc_guide_stationid == "" or .tvc_guide_stationid == null)
      )')
      ;;
    *)
      echo -e "${RED}❌ Invalid selection${RESET}"
      sleep 1
      return 1
      ;;
  esac
  
  if [[ -z "$filtered_channels" ]]; then
    echo -e "${GREEN}✅ No channels found matching the selected criteria${RESET}"
    echo -e "${CYAN}💡 All channels already have the requested field data${RESET}"
    echo -e "${CYAN}💡 Try a different filter or use 'Process All Channels'${RESET}"
    pause_for_user
    return 0
  fi
  
  echo -e "${CYAN}📋 Sorting filtered channels by channel number (lowest to highest)...${RESET}"
  
  # Sort filtered channels by .channel_number (lowest to highest) - explicit numeric sort
  local sorted_filtered_channels
  sorted_filtered_channels=$(echo "$filtered_channels" | jq -s 'sort_by(.channel_number | tonumber)')
  
  mapfile -t filtered_array < <(echo "$sorted_filtered_channels" | jq -c '.[]')
  local filtered_count=${#filtered_array[@]}
  
  echo -e "${GREEN}✅ Found $filtered_count channels matching criteria (sorted by channel number)${RESET}"
  echo -e "${CYAN}💡 Processing in channel number order for systematic coverage${RESET}"
  echo
  
  # STANDARDIZED: Show preview of filtered channels with professional table
  if [ "$filtered_count" -gt 0 ]; then
    echo -e "${BOLD}${BLUE}Preview of Filtered Channels:${RESET}"
    echo
    
    # STANDARDIZED: Professional table header with consistent formatting
    printf "${BOLD}${YELLOW}%-6s %-8s %-25s %-15s %-10s %-10s %s${RESET}\n" "Number" "Ch ID" "Channel Name" "Group" "TVG-ID" "Station" "Issues"
    echo "--------------------------------------------------------------------------------"
    
    # Show first 10 channels as preview
    local preview_count=$((filtered_count > 10 ? 10 : filtered_count))
    for ((i = 0; i < preview_count; i++)); do
      local channel_data="${filtered_array[$i]}"
      local channel_id=$(echo "$channel_data" | jq -r '.id')
      local channel_name=$(echo "$channel_data" | jq -r '.name // "Unnamed"')
      local channel_number=$(echo "$channel_data" | jq -r '.channel_number // "N/A"')
      local channel_group=$(echo "$channel_data" | jq -r '.channel_group_id // "Ungrouped"')
      local tvg_id=$(echo "$channel_data" | jq -r '.tvg_id // ""')
      local tvc_stationid=$(echo "$channel_data" | jq -r '.tvc_guide_stationid // ""')
      
      # Analyze issues for this channel
      local issues=""
      if [[ -z "$channel_name" || "$channel_name" == "null" || "$channel_name" =~ Channel\ [0-9]+ ]]; then
        issues+="Name "
      fi
      if [[ -z "$tvg_id" || "$tvg_id" == "null" ]]; then
        issues+="TVG "
      fi
      if [[ -z "$tvc_stationid" || "$tvc_stationid" == "null" ]]; then
        issues+="StID "
      fi
      
      # STANDARDIZED: Table row with consistent formatting - FIXED
      printf "%-6s %-8s %-25s %-15s %-10s %-10s " \
        "$channel_number" \
        "$channel_id" \
        "${channel_name:0:25}" \
        "${channel_group:0:15}" \
        "${tvg_id:0:10}" \
        "${tvc_stationid:0:10}"
      echo -e "${RED}$issues${RESET}"
    done
    
    if [ "$filtered_count" -gt 10 ]; then
      echo "..."
      echo -e "${CYAN}... and $((filtered_count - 10)) more channels${RESET}"
    fi
    echo
    
    # STANDARDIZED: Summary statistics table
    echo -e "${BOLD}${BLUE}Filter Results Summary:${RESET}"
    printf "${BOLD}${YELLOW}%-25s %s${RESET}\n" "Statistics" "Count"
    echo "------------------------------------"
    printf "%-25s %s\n" "Total channels matched:" "${GREEN}$filtered_count${RESET}"
    printf "%-25s %s\n" "Filter criteria:" "$(case "$filter_choice" in 1) echo "Missing Names" ;; 2) echo "Missing TVG-ID" ;; 3) echo "Missing Station ID" ;; 4) echo "Any Missing Fields" ;; esac)"
    printf "%-25s %s\n" "Processing order:" "${CYAN}By channel number${RESET}"
    echo
  fi
  
  if ! confirm_action "Process these $filtered_count filtered channels?"; then
    echo -e "${YELLOW}⚠️  Filtered processing cancelled${RESET}"
    return 0
  fi
  
  for ((i = 0; i < filtered_count; i++)); do
    local channel_data="${filtered_array[$i]}"
    
    echo -e "${BOLD}${BLUE}=== Filtered Channel $((i + 1)) of $filtered_count ===${RESET}"
    
    process_single_channel_fields "$channel_data" $((i + 1)) "$filtered_count"
    
    if [[ $((i + 1)) -lt $filtered_count ]]; then
      echo
      echo -e "${BOLD}Continue Processing Filtered Channels?${RESET}"
      echo -e "Completed: $((i + 1)) of $filtered_count filtered channels"
      echo -e "Remaining: $((filtered_count - i - 1)) channels"
      echo
      
      if ! confirm_action "Continue to next filtered channel?"; then
        echo -e "${YELLOW}⚠️  Filtered processing stopped by user${RESET}"
        break
      fi
    fi
  done
  
  echo -e "\n${GREEN}✅ Filtered field population completed${RESET}"
  echo -e "${CYAN}💡 All matching channels have been processed${RESET}"
  pause_for_user
}

process_specific_channel() {
  local channels_data="$1"
  
  # Sort channels by channel number (lowest to highest) and convert to array
  local sorted_channels_array
  sorted_channels_array=$(echo "$channels_data" | jq -c 'sort_by(.channel_number | tonumber)')
  
  # Count total channels correctly
  local total_channels
  total_channels=$(echo "$sorted_channels_array" | jq 'length')
  
  local offset=0
  local channels_per_page=$DEFAULT_CHANNELS_PER_PAGE
  
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== Select Specific Channel ===${RESET}"
    echo -e "${CYAN}Browse available channels and select one for field population.${RESET}"
    echo
    
    # Calculate current page info
    local start_num=$((offset + 1))
    local end_num=$((offset + channels_per_page < total_channels ? offset + channels_per_page : total_channels))
    local current_page=$(( (offset / channels_per_page) + 1 ))
    local total_pages=$(( (total_channels + channels_per_page - 1) / channels_per_page ))
    
    echo -e "${BOLD}Available Channels (sorted by channel number, showing $start_num-$end_num of $total_channels)${RESET}"
    echo -e "${CYAN}Page $current_page of $total_pages${RESET}"
    echo
    
    # STANDARDIZED: Professional table header with selection keys
    printf "${BOLD}${YELLOW}%-3s %-8s %-6s %-30s %-15s %s${RESET}\n" "Key" "ID" "Number" "Channel Name" "Group" "TVG-ID"
    echo "--------------------------------------------------------------------------------"
    
    # Show current page of channels with letter keys for selection
    local key_letters=("a" "b" "c" "d" "e" "f" "g" "h" "i" "j")
    local page_channels=()
    local row_count=0
    
    # Extract the channels for current page and store them properly
    for ((i = offset; i < offset + channels_per_page && i < total_channels; i++)); do
      local channel_json=$(echo "$sorted_channels_array" | jq -c ".[$i]")
      
      # Extract display info
      local id=$(echo "$channel_json" | jq -r '.id // "N/A"')
      local number=$(echo "$channel_json" | jq -r '.channel_number // "N/A"')
      local name=$(echo "$channel_json" | jq -r '.name // "Unnamed"')
      local group=$(echo "$channel_json" | jq -r '.channel_group_id // "Ungrouped"')
      local tvg_id=$(echo "$channel_json" | jq -r '.tvg_id // "Empty"')
      
      local key="${key_letters[$row_count]}"
      
      # STANDARDIZED: Table row formatting with selection highlighting
      printf "${GREEN}%-3s${RESET} " "${key})"
      printf "%-8s %-6s %-30s %-15s %s\n" "$id" "$number" "${name:0:30}" "${group:0:15}" "${tvg_id:0:10}"
      
      # Store the full channel JSON for selection
      page_channels+=("$channel_json")
      ((row_count++))
    done
    
    echo
    echo -e "${BOLD}${CYAN}Navigation Options:${RESET}"
    if [[ $current_page -lt $total_pages ]]; then
      echo -e "${GREEN}n)${RESET} Next page"
    fi
    if [[ $current_page -gt 1 ]]; then
      echo -e "${GREEN}p)${RESET} Previous page"
    fi
    if [[ $current_page -eq 1 && $total_pages -eq 1 ]]; then
      echo -e "${CYAN}(Single page - all channels shown)${RESET}"
    fi
    echo -e "${GREEN}q)${RESET} Cancel and return"
    echo
    
    echo -e "${BOLD}${CYAN}Channel Selection:${RESET}"
    [[ $row_count -gt 0 ]] && echo -e "${GREEN}a-j)${RESET} Select channel from the list above"
    echo -e "${CYAN}💡 Use the letter keys to select a channel for field population${RESET}"
    echo
    
    read -p "Enter selection: " choice
    
    case "$choice" in
      n|N)
        if [[ $current_page -lt $total_pages ]]; then
          offset=$((offset + channels_per_page))
        else
          echo -e "${YELLOW}⚠️  Already on last page${RESET}"
          sleep 1
        fi
        ;;
      p|P)
        if [[ $current_page -gt 1 ]]; then
          offset=$((offset - channels_per_page))
        else
          echo -e "${YELLOW}⚠️  Already on first page${RESET}"
          sleep 1
        fi
        ;;
      a|A|b|B|c|C|d|D|e|E|f|F|g|G|h|H|i|I|j|J)
        # FIXED: Direct letter selection with proper validation
        if [[ $row_count -gt 0 ]]; then
          local letter_lower=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
          local index=-1
          for ((idx=0; idx<10; idx++)); do
            if [[ "${key_letters[$idx]}" == "$letter_lower" ]]; then
              index=$idx
              break
            fi
          done
          
          if [[ $index -ge 0 ]] && [[ $index -lt $row_count ]]; then
            # Get channel data from our stored page_channels array
            local selected_channel="${page_channels[$index]}"
            
            if [[ -n "$selected_channel" && "$selected_channel" != "null" ]]; then
              local channel_id=$(echo "$selected_channel" | jq -r '.id')
              local channel_name=$(echo "$selected_channel" | jq -r '.name // "Unnamed"')
              local channel_number=$(echo "$selected_channel" | jq -r '.channel_number // "N/A"')
              local channel_group=$(echo "$selected_channel" | jq -r '.channel_group_id // "Ungrouped"')
              
              echo
              echo -e "${BOLD}${GREEN}Selected Channel Details:${RESET}"
              
              # STANDARDIZED: Selection confirmation table
              echo -e "${BOLD}${YELLOW}Field           Value${RESET}"
              echo "--------------------------------"
              echo -e "Channel Name:   ${GREEN}$channel_name${RESET}"
              echo -e "Channel ID:     ${CYAN}$channel_id${RESET}"
              echo -e "Number:         ${CYAN}$channel_number${RESET}"
              echo -e "Group:          ${CYAN}$channel_group${RESET}"
              echo
              
              if confirm_action "Process field population for this channel?"; then
                echo -e "${BOLD}${BLUE}=== Processing Selected Channel ===${RESET}"
                process_single_channel_fields_standalone "$selected_channel"
                local process_result=$?
                
                case $process_result in
                  0)
                    echo -e "\n${GREEN}✅ Channel field population completed${RESET}"
                    echo -e "${CYAN}💡 Changes have been applied to Dispatcharr as selected${RESET}"
                    pause_for_user
                    return 0
                    ;;
                  1)
                    # User chose to return to channel selection - continue the loop
                    continue
                    ;;
                  2)
                    # User chose to return to main menu
                    return 0
                    ;;
                esac
              else
                continue  # Stay in selection mode
              fi
            else
              echo -e "${RED}❌ Could not retrieve channel data${RESET}"
              sleep 1
            fi
          else
            echo -e "${RED}❌ Invalid selection${RESET}"
            sleep 1
          fi
        else
          echo -e "${RED}❌ No channels available for selection${RESET}"
          sleep 1
        fi
        ;;
      ""|q|Q)
        echo -e "${YELLOW}⚠️  Channel selection cancelled${RESET}"
        return 1
        ;;
      *)
        echo -e "${RED}❌ Invalid option: '$choice'${RESET}"
        echo -e "${CYAN}💡 Use letters a-j to select from the displayed channels${RESET}"
        sleep 2
        ;;
    esac
  done
}

process_single_channel_fields() {
  local channel_data="$1"
  local current_num="$2"
  local total_num="$3"
  
  # Extract channel information with CORRECT field names
  local channel_id=$(echo "$channel_data" | jq -r '.id')
  local channel_name=$(echo "$channel_data" | jq -r '.name // "Unnamed"')
  local channel_number=$(echo "$channel_data" | jq -r '.channel_number // "N/A"')
  local current_tvg_id=$(echo "$channel_data" | jq -r '.tvg_id // ""')
  local current_tvc_stationid=$(echo "$channel_data" | jq -r '.tvc_guide_stationid // ""')  # CORRECTED
  
  clear
  echo -e "${BOLD}${CYAN}=== Populate Channel Fields ($current_num of $total_num) ===${RESET}\n"
  
  echo -e "${BOLD}Channel: ${YELLOW}$channel_name${RESET}"
  echo -e "Number: $channel_number | ID: $channel_id"
  echo -e "Progress: $current_num of $total_num"
  echo
  
  echo -e "${BOLD}Current Field Values:${RESET}"
  echo -e "TVG-ID: ${current_tvg_id:-"${RED}(empty)${RESET}"}"
  echo -e "TVC Station ID: ${current_tvc_stationid:-"${RED}(empty)${RESET}"}"  # CORRECTED
  echo
  
  # AUTO-MATCHING LOGIC: If station ID exists, use reverse lookup instead of search
  if [[ -n "$current_tvc_stationid" && "$current_tvc_stationid" != "null" ]]; then
    echo -e "${BOLD}${GREEN}=== Auto-Matching with Existing Station ID ===${RESET}"
    echo -e "${GREEN}✅ Station ID found: $current_tvc_stationid${RESET}"
    echo -e "${CYAN}🔄 Using reverse station ID lookup instead of search...${RESET}"
    echo
    
    # Get station data from local database using the existing station ID
    local stations_file
    stations_file=$(get_effective_stations_file)
    if [ $? -ne 0 ]; then
      echo -e "${RED}❌ Local Database Search: No station data available${RESET}"
      echo -e "${CYAN}💡 Cannot auto-match without station database${RESET}"
      pause_for_user
      return 0
    fi
    
    local station_data
    station_data=$(jq -r --arg id "$current_tvc_stationid" '.[] | select(.stationId == $id)' "$stations_file" 2>/dev/null)
    
    if [[ -n "$station_data" && "$station_data" != "null" ]]; then
      # Extract station information for auto-matching
      local station_name=$(echo "$station_data" | jq -r '.name // empty')
      local call_sign=$(echo "$station_data" | jq -r '.callSign // empty')
      local country=$(echo "$station_data" | jq -r '.country // empty')
      local quality=$(echo "$station_data" | jq -r '.videoQuality.videoType // empty')
      
      echo -e "${GREEN}✅ Station found in local database:${RESET}"
      echo -e "Station Name: ${GREEN}$station_name${RESET}"
      echo -e "Call Sign: ${GREEN}$call_sign${RESET}"
      echo -e "Country: ${GREEN}$country${RESET}"
      echo -e "Quality: ${GREEN}$quality${RESET}"
      echo
      
      # Add user options for auto-matched stations
      echo -e "${BOLD}Options:${RESET}"
      echo -e "${GREEN}c)${RESET} Continue with field updates for this station"
      echo -e "${YELLOW}k)${RESET} Skip this channel ${CYAN}(continue to next channel)${RESET}"
      echo -e "${RED}q)${RESET} Quit field population ${CYAN}(stop entire batch processing)${RESET}"
      echo
      
      read -p "Your choice: " auto_choice < /dev/tty
      
      case "$auto_choice" in
        c|C|"")
          # Proceed with field comparison
          show_field_comparison_and_update_simplified "$channel_id" "$channel_name" "$current_tvg_id" "$current_tvc_stationid" "$current_tvc_stationid" "$station_name" "$call_sign"
          local update_result=$?
          
          case $update_result in
            0)
              echo -e "${GREEN}✅ Auto-matched field updates applied successfully${RESET}"
              ;;
            1)
              echo -e "${RED}❌ Failed to apply auto-matched field updates${RESET}"
              ;;
            2)
              echo -e "${CYAN}💡 No field updates requested for auto-matched station${RESET}"
              ;;
          esac
          pause_for_user
          return 0
          ;;
        k|K)
          echo -e "${YELLOW}Skipped: $channel_name${RESET}"
          return 0  # Skip this channel, move to next
          ;;
        q|Q)
          echo -e "${CYAN}Field population ended by user${RESET}"
          return 1  # Signal to parent function to stop entire workflow
          ;;
        *)
          echo -e "${RED}Invalid option. Proceeding with field updates...${RESET}"
          # Default to continuing
          show_field_comparison_and_update_simplified "$channel_id" "$channel_name" "$current_tvg_id" "$current_tvc_stationid" "$current_tvc_stationid" "$station_name" "$call_sign"
          local update_result=$?
          
          case $update_result in
            0)
              echo -e "${GREEN}✅ Auto-matched field updates applied successfully${RESET}"
              ;;
            1)
              echo -e "${RED}❌ Failed to apply auto-matched field updates${RESET}"
              ;;
            2)
              echo -e "${CYAN}💡 No field updates requested for auto-matched station${RESET}"
              ;;
          esac
          pause_for_user
          return 0
          ;;
      esac
    else
      echo -e "${YELLOW}⚠️  Station ID $current_tvc_stationid not found in local database${RESET}"
      echo -e "${CYAN}💡 Falling back to manual search method...${RESET}"
      echo
      # Fall through to manual search below
    fi
  else
    echo -e "${YELLOW}⚠️  No station ID found - using manual search method${RESET}"
    echo
    
    # Add user options for manual search
    echo -e "${BOLD}Options:${RESET}"
    echo -e "${GREEN}c)${RESET} Continue with manual station search"
    echo -e "${YELLOW}k)${RESET} Skip this channel ${CYAN}(continue to next channel)${RESET}"
    echo -e "${RED}q)${RESET} Quit field population ${CYAN}(stop entire batch processing)${RESET}"
    echo
    
    read -p "Your choice: " manual_choice < /dev/tty
    
    case "$manual_choice" in
      c|C|"")
        # Continue to manual search - fall through to search logic below
        ;;
      k|K)
        echo -e "${YELLOW}Skipped: $channel_name${RESET}"
        return 0  # Skip this channel, move to next
        ;;
      q|Q)
        echo -e "${CYAN}Field population ended by user${RESET}"
        return 1  # Signal to parent function to stop entire workflow
        ;;
      *)
        echo -e "${RED}Invalid option. Proceeding with manual search...${RESET}"
        # Default to continuing with manual search
        ;;
    esac
  fi
  
  # MANUAL SEARCH LOGIC: Original search workflow when no station ID or auto-match fails
  # Parse the channel name to get search term
  local parsed_data=$(parse_channel_name "$channel_name")
  IFS='|' read -r clean_name detected_country detected_resolution <<< "$parsed_data"
  
  # Show parsing results if anything was detected
  if [[ -n "$detected_country" ]] || [[ -n "$detected_resolution" ]] || [[ "$clean_name" != "$channel_name" ]]; then
    echo -e "${BOLD}${BLUE}Smart Parsing Results:${RESET}"
    echo -e "Original: ${YELLOW}$channel_name${RESET}"
    echo -e "Cleaned:  ${GREEN}$clean_name${RESET}"
    [[ -n "$detected_country" ]] && echo -e "Country:  ${GREEN}$detected_country${RESET} (auto-detected)"
    [[ -n "$detected_resolution" ]] && echo -e "Quality:  ${GREEN}$detected_resolution${RESET} (auto-detected)"
    echo -e "${CYAN}Searching with cleaned name and auto-detected filters...${RESET}"
    echo
  fi
  
  # Use clean name for initial search
  local search_term="$clean_name"
  local current_page=1
  
  # Search and display loop (IDENTICAL TO STATION ID WORKFLOW)
  while true; do
    echo -e "${CYAN}Searching for: '$search_term' (Page $current_page)${RESET}"
    
    # Show active filters - UPDATED
    local filter_status=""
    if [[ -n "$detected_country" ]]; then
      filter_status+="Country: $detected_country (auto) "
    fi
    if [[ -n "$detected_resolution" ]]; then
      filter_status+="Quality: $detected_resolution (auto) "
    fi
    if [[ -n "$filter_status" ]]; then
      echo -e "${BLUE}Active Filters: $filter_status${RESET}"
    else
      echo -e "${CYAN}🔍 No auto-filters active - searching all available stations${RESET}"
    fi
    echo
    
    # Get search results using SHARED SEARCH FUNCTION
    local results
    results=$(search_stations_by_name "$search_term" "$current_page" "$detected_country" "$detected_resolution")
    
    local total_results
    total_results=$(get_total_search_results "$search_term" "$detected_country" "$detected_resolution")
    
    if [[ -z "$results" ]]; then
      echo -e "${YELLOW}No results found for '$search_term'${RESET}"
      if [[ -n "$detected_country" ]] || [[ -n "$detected_resolution" ]]; then
        echo -e "${CYAN}💡 Try 's' to search with different term or filters${RESET}"
      fi
    else
      echo -e "${GREEN}Found $total_results total results${RESET}"
      echo
      
      # IDENTICAL TABLE HEADER TO STATION ID WORKFLOW with FIXED selection highlighting
      printf "${BOLD}${YELLOW}%-3s %-12s %-30s %-10s %-8s %s${RESET}\n" "Key" "Station ID" "Channel Name" "Call Sign" "Quality" "Country"
      echo "--------------------------------------------------------------------------------"
      
      local station_array=()
      local key_letters=("a" "b" "c" "d" "e" "f" "g" "h" "i" "j")
      local result_count=0
      
      # IDENTICAL RESULT PROCESSING TO STATION ID WORKFLOW with FIXED selection highlighting
      while IFS=$'\t' read -r station_id name call_sign country; do
        [[ -z "$station_id" ]] && continue
        
        # Get additional station info for better display
        local quality=$(get_station_quality "$station_id")
        
        local key="${key_letters[$result_count]}"
        
        # IDENTICAL TABLE ROW FORMATTING with CONSISTENT selection highlighting
        printf "${GREEN}%-3s${RESET} " "${key})"
        echo -n -e "${CYAN}${station_id}${RESET}"
        printf "%*s" $((12 - ${#station_id})) ""
        printf "%-30s %-10s %-8s " "${name:0:30}" "${call_sign:0:10}" "${quality:0:8}"
        echo -e "${GREEN}${country}${RESET}"
        
        # IDENTICAL LOGO DISPLAY TO STATION ID WORKFLOW
        if [[ "$SHOW_LOGOS" == true ]]; then
          display_logo "$station_id"
        else
          echo "[logo previews disabled]"
        fi
        echo
        
        # Store for selection (no logo URI needed now)
        station_array+=("$station_id|$name|$call_sign|$country|$quality")
        ((result_count++))
      done <<< "$results"
    fi
    
    # Calculate pagination info
    local total_pages=$(( (total_results + 9) / 10 ))
    [[ $total_pages -eq 0 ]] && total_pages=1
    
    echo -e "${BOLD}Page $current_page of $total_pages${RESET}"
    echo
    
    # IDENTICAL OPTIONS TO STATION ID WORKFLOW
    echo -e "${BOLD}Options:${RESET}"
    [[ $result_count -gt 0 ]] && echo "a-j) Select a station from the results above"
    [[ $current_page -lt $total_pages ]] && echo "n) Next page"
    [[ $current_page -gt 1 ]] && echo "p) Previous page"
    echo "s) Search with different term"
    echo -e "${YELLOW}k) Skip this channel${RESET} ${CYAN}(continue to next channel)${RESET}"
    echo -e "${RED}q) Quit field population${RESET} ${CYAN}(stop entire batch processing)${RESET}"
    echo
    
    read -p "Your choice: " choice < /dev/tty
    
    # IDENTICAL OPTION HANDLING TO STATION ID WORKFLOW
    case "$choice" in
      a|A|b|B|c|C|d|D|e|E|f|F|g|G|h|H|i|I|j|J)
        if [[ $result_count -gt 0 ]]; then
          # Convert letter to array index
          local letter_lower=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
          local index=-1
          for ((idx=0; idx<10; idx++)); do
            if [[ "${key_letters[$idx]}" == "$letter_lower" ]]; then
              index=$idx
              break
            fi
          done
          
          if [[ $index -ge 0 ]] && [[ $index -lt $result_count ]]; then
            local selected="${station_array[$index]}"
            IFS='|' read -r sel_station_id sel_name sel_call sel_country sel_quality <<< "$selected"
            
            echo
            echo -e "${BOLD}Selected Station:${RESET}"
            echo "  Station ID: $sel_station_id"
            echo "  Name: $sel_name"
            echo "  Call Sign: $sel_call"
            echo "  Country: $sel_country"
            echo "  Quality: $sel_quality"
            echo
            
            read -p "Use this station for field updates? (y/n): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
              # Show field comparison and get user choices (NO LOGO LOGIC)
              show_field_comparison_and_update_simplified "$channel_id" "$channel_name" "$current_tvg_id" "$current_tvc_stationid" "$sel_station_id" "$sel_name" "$sel_call"
              local update_result=$?
              
              case $update_result in
                0)
                  echo -e "${GREEN}Field updates applied successfully${RESET}"
                  ;;
                1)
                  echo -e "${RED}Failed to apply field updates${RESET}"
                  ;;
                2)
                  echo -e "${CYAN}No field updates were requested${RESET}"
                  ;;
              esac
              pause_for_user
              return 0  # Exit channel processing, move to next channel
            fi
          else
            echo -e "${RED}Invalid selection${RESET}"
            sleep 1
          fi
        else
          echo -e "${RED}No results to select from${RESET}"
          sleep 1
        fi
        ;;
      n|N)
        if [[ $current_page -lt $total_pages ]]; then
          ((current_page++))
        else
          echo -e "${YELLOW}Already on last page${RESET}"
          sleep 1
        fi
        ;;
      p|P)
        if [[ $current_page -gt 1 ]]; then
          ((current_page--))
        else
          echo -e "${YELLOW}Already on first page${RESET}"
          sleep 1
        fi
        ;;
      s|S)
        read -p "Enter new search term: " new_search < /dev/tty
        if [[ -n "$new_search" ]]; then
          search_term="$new_search"
          current_page=1
          # FIXED: Clear auto-detected filters when user enters manual search
          detected_country=""
          detected_resolution=""
          echo -e "${CYAN}💡 Auto-detected filters cleared for manual search${RESET}"
        fi
        ;;
      k|K)
        echo -e "${YELLOW}Skipped: $channel_name${RESET}"
        return 0  # Skip this channel, move to next
        ;;
      q|Q)
        echo -e "${CYAN}Field population ended by user${RESET}"
        return 1  # Signal to parent function to stop entire workflow
        ;;
      *)
        echo -e "${RED}Invalid option${RESET}"
        sleep 1
        ;;
    esac
  done
}

process_single_channel_fields_standalone() {
  local channel_data="$1"
  
  # Extract channel information with CORRECT field names
  local channel_id=$(echo "$channel_data" | jq -r '.id')
  local channel_name=$(echo "$channel_data" | jq -r '.name // "Unnamed"')
  local channel_number=$(echo "$channel_data" | jq -r '.channel_number // "N/A"')
  local current_tvg_id=$(echo "$channel_data" | jq -r '.tvg_id // ""')
  local current_tvc_stationid=$(echo "$channel_data" | jq -r '.tvc_guide_stationid // ""')  # CORRECTED
  
  clear
  echo -e "${BOLD}${CYAN}=== Populate Channel Fields ===${RESET}\n"
  
  echo -e "${BOLD}Channel: ${YELLOW}$channel_name${RESET}"
  echo -e "Number: $channel_number | ID: $channel_id"
  echo
  
  echo -e "${BOLD}Current Field Values:${RESET}"
  echo -e "TVG-ID: ${current_tvg_id:-"${RED}(empty)${RESET}"}"
  echo -e "TVC Station ID: ${current_tvc_stationid:-"${RED}(empty)${RESET}"}"  # CORRECTED
  echo
  
  # AUTO-MATCHING LOGIC: If station ID exists, use reverse lookup instead of search
  if [[ -n "$current_tvc_stationid" && "$current_tvc_stationid" != "null" ]]; then
    echo -e "${BOLD}${GREEN}=== Auto-Matching with Existing Station ID ===${RESET}"
    echo -e "${GREEN}✅ Station ID found: $current_tvc_stationid${RESET}"
    echo -e "${CYAN}🔄 Using reverse station ID lookup instead of search...${RESET}"
    echo
    
    # Get station data from local database using the existing station ID
    local stations_file
    stations_file=$(get_effective_stations_file)
    if [ $? -ne 0 ]; then
      echo -e "${RED}❌ Local Database Search: No station data available${RESET}"
      echo -e "${CYAN}💡 Cannot auto-match without station database${RESET}"
      pause_for_user
      return 0
    fi
    
    local station_data
    station_data=$(jq -r --arg id "$current_tvc_stationid" '.[] | select(.stationId == $id)' "$stations_file" 2>/dev/null)
    
    if [[ -n "$station_data" && "$station_data" != "null" ]]; then
      # Extract station information for auto-matching
      local station_name=$(echo "$station_data" | jq -r '.name // empty')
      local call_sign=$(echo "$station_data" | jq -r '.callSign // empty')
      local country=$(echo "$station_data" | jq -r '.country // empty')
      local quality=$(echo "$station_data" | jq -r '.videoQuality.videoType // empty')
      
      echo -e "${GREEN}✅ Station found in local database:${RESET}"
      echo -e "Station Name: ${GREEN}$station_name${RESET}"
      echo -e "Call Sign: ${GREEN}$call_sign${RESET}"
      echo -e "Country: ${GREEN}$country${RESET}"
      echo -e "Quality: ${GREEN}$quality${RESET}"
      echo
      
      # Add user options for auto-matched stations - SINGLE CHANNEL VERSION
      echo -e "${BOLD}Options:${RESET}"
      echo -e "${GREEN}c)${RESET} Continue with field updates for this station"
      echo -e "${YELLOW}r)${RESET} Return to channel selection ${CYAN}(choose different channel)${RESET}"
      echo -e "${RED}q)${RESET} Back to main menu"
      echo
      
      read -p "Your choice: " auto_choice < /dev/tty
      
      case "$auto_choice" in
        c|C|"")
          # Proceed with field comparison
          show_field_comparison_and_update_simplified "$channel_id" "$channel_name" "$current_tvg_id" "$current_tvc_stationid" "$current_tvc_stationid" "$station_name" "$call_sign"
          local update_result=$?
          
          case $update_result in
            0)
              echo -e "${GREEN}✅ Auto-matched field updates applied successfully${RESET}"
              ;;
            1)
              echo -e "${RED}❌ Failed to apply auto-matched field updates${RESET}"
              ;;
            2)
              echo -e "${CYAN}💡 No field updates requested for auto-matched station${RESET}"
              ;;
          esac
          pause_for_user
          return 0
          ;;
        r|R)
          echo -e "${CYAN}Returning to channel selection...${RESET}"
          return 1  # Return to channel selection
          ;;
        q|Q)
          echo -e "${CYAN}Returning to main menu...${RESET}"
          return 2  # Return to main menu
          ;;
        *)
          echo -e "${RED}Invalid option. Proceeding with field updates...${RESET}"
          # Default to continuing
          show_field_comparison_and_update_simplified "$channel_id" "$channel_name" "$current_tvg_id" "$current_tvc_stationid" "$current_tvc_stationid" "$station_name" "$call_sign"
          local update_result=$?
          
          case $update_result in
            0)
              echo -e "${GREEN}✅ Auto-matched field updates applied successfully${RESET}"
              ;;
            1)
              echo -e "${RED}❌ Failed to apply auto-matched field updates${RESET}"
              ;;
            2)
              echo -e "${CYAN}💡 No field updates requested for auto-matched station${RESET}"
              ;;
          esac
          pause_for_user
          return 0
          ;;
      esac
    else
      echo -e "${YELLOW}⚠️  Station ID $current_tvc_stationid not found in local database${RESET}"
      echo -e "${CYAN}💡 Falling back to manual search method...${RESET}"
      echo
      # Fall through to manual search below
    fi
  else
    echo -e "${YELLOW}⚠️  No station ID found - using manual search method${RESET}"
    echo
    
    # Add user options for manual search - SINGLE CHANNEL VERSION
    echo -e "${BOLD}Options:${RESET}"
    echo -e "${GREEN}c)${RESET} Continue with manual station search"
    echo -e "${YELLOW}r)${RESET} Return to channel selection ${CYAN}(choose different channel)${RESET}"
    echo -e "${RED}q)${RESET} Back to main menu"
    echo
    
    read -p "Your choice: " manual_choice < /dev/tty
    
    case "$manual_choice" in
      c|C|"")
        # Continue to manual search - fall through to search logic below
        ;;
      r|R)
        echo -e "${CYAN}Returning to channel selection...${RESET}"
        return 1  # Return to channel selection
        ;;
      q|Q)
        echo -e "${CYAN}Returning to main menu...${RESET}"
        return 2  # Return to main menu
        ;;
      *)
        echo -e "${RED}Invalid option. Proceeding with manual search...${RESET}"
        # Default to continuing with manual search
        ;;
    esac
  fi
  
  # MANUAL SEARCH LOGIC: Original search workflow when no station ID or auto-match fails
  # Parse the channel name to get search term
  local parsed_data=$(parse_channel_name "$channel_name")
  IFS='|' read -r clean_name detected_country detected_resolution <<< "$parsed_data"
  
  # Show parsing results if anything was detected
  if [[ -n "$detected_country" ]] || [[ -n "$detected_resolution" ]] || [[ "$clean_name" != "$channel_name" ]]; then
    echo -e "${BOLD}${BLUE}Smart Parsing Results:${RESET}"
    echo -e "Original: ${YELLOW}$channel_name${RESET}"
    echo -e "Cleaned:  ${GREEN}$clean_name${RESET}"
    [[ -n "$detected_country" ]] && echo -e "Country:  ${GREEN}$detected_country${RESET} (auto-detected)"
    [[ -n "$detected_resolution" ]] && echo -e "Quality:  ${GREEN}$detected_resolution${RESET} (auto-detected)"
    echo -e "${CYAN}Searching with cleaned name and auto-detected filters...${RESET}"
    echo
  fi
  
  # Use clean name for initial search
  local search_term="$clean_name"
  local current_page=1
  
  # Search and display loop - SINGLE CHANNEL VERSION
  while true; do
    echo -e "${CYAN}Searching for: '$search_term' (Page $current_page)${RESET}"
    
    # Show active filters - UPDATED
    local filter_status=""
    if [[ -n "$detected_country" ]]; then
      filter_status+="Country: $detected_country (auto) "
    fi
    if [[ -n "$detected_resolution" ]]; then
      filter_status+="Quality: $detected_resolution (auto) "
    fi
    if [[ -n "$filter_status" ]]; then
      echo -e "${BLUE}Active Filters: $filter_status${RESET}"
    else
      echo -e "${CYAN}🔍 No auto-filters active - searching all available stations${RESET}"
    fi
    echo
    
    # Get search results using SHARED SEARCH FUNCTION
    local results
    results=$(search_stations_by_name "$search_term" "$current_page" "$detected_country" "$detected_resolution")
    
    local total_results
    total_results=$(get_total_search_results "$search_term" "$detected_country" "$detected_resolution")
    
    if [[ -z "$results" ]]; then
      echo -e "${YELLOW}No results found for '$search_term'${RESET}"
      if [[ -n "$detected_country" ]] || [[ -n "$detected_resolution" ]]; then
        echo -e "${CYAN}💡 Try 's' to search with different term or filters${RESET}"
      fi
    else
      echo -e "${GREEN}Found $total_results total results${RESET}"
      echo
      
      # TABLE HEADER with FIXED selection highlighting
      printf "${BOLD}${YELLOW}%-3s %-12s %-30s %-10s %-8s %s${RESET}\n" "Key" "Station ID" "Channel Name" "Call Sign" "Quality" "Country"
      echo "--------------------------------------------------------------------------------"
      
      local station_array=()
      local key_letters=("a" "b" "c" "d" "e" "f" "g" "h" "i" "j")
      local result_count=0
      
      # RESULT PROCESSING with FIXED selection highlighting
      while IFS=$'\t' read -r station_id name call_sign country; do
        [[ -z "$station_id" ]] && continue
        
        # Get additional station info for better display
        local quality=$(get_station_quality "$station_id")
        
        local key="${key_letters[$result_count]}"
        
        # TABLE ROW FORMATTING with CONSISTENT selection highlighting
        printf "${GREEN}%-3s${RESET} " "${key})"
        echo -n -e "${CYAN}${station_id}${RESET}"
        printf "%*s" $((12 - ${#station_id})) ""
        printf "%-30s %-10s %-8s " "${name:0:30}" "${call_sign:0:10}" "${quality:0:8}"
        echo -e "${GREEN}${country}${RESET}"
        
        # LOGO DISPLAY
        if [[ "$SHOW_LOGOS" == true ]]; then
          display_logo "$station_id"
        else
          echo "[logo previews disabled]"
        fi
        echo
        
        # Store for selection
        station_array+=("$station_id|$name|$call_sign|$country|$quality")
        ((result_count++))
      done <<< "$results"
    fi
    
    # Calculate pagination info
    local total_pages=$(( (total_results + 9) / 10 ))
    [[ $total_pages -eq 0 ]] && total_pages=1
    
    echo -e "${BOLD}Page $current_page of $total_pages${RESET}"
    echo
    
    # OPTIONS FOR SINGLE CHANNEL - Updated messaging
    echo -e "${BOLD}Options:${RESET}"
    [[ $result_count -gt 0 ]] && echo "a-j) Select a station from the results above"
    [[ $current_page -lt $total_pages ]] && echo "n) Next page"
    [[ $current_page -gt 1 ]] && echo "p) Previous page"
    echo "s) Search with different term"
    echo -e "${YELLOW}r) Return to channel selection${RESET} ${CYAN}(choose different channel)${RESET}"
    echo -e "${RED}q) Back to main menu${RESET}"
    echo
    
    read -p "Your choice: " choice < /dev/tty
    
    # OPTION HANDLING FOR SINGLE CHANNEL
    case "$choice" in
      a|A|b|B|c|C|d|D|e|E|f|F|g|G|h|H|i|I|j|J)
        if [[ $result_count -gt 0 ]]; then
          # Convert letter to array index
          local letter_lower=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
          local index=-1
          for ((idx=0; idx<10; idx++)); do
            if [[ "${key_letters[$idx]}" == "$letter_lower" ]]; then
              index=$idx
              break
            fi
          done
          
          if [[ $index -ge 0 ]] && [[ $index -lt $result_count ]]; then
            local selected="${station_array[$index]}"
            IFS='|' read -r sel_station_id sel_name sel_call sel_country sel_quality <<< "$selected"
            
            echo
            echo -e "${BOLD}Selected Station:${RESET}"
            echo "  Station ID: $sel_station_id"
            echo "  Name: $sel_name"
            echo "  Call Sign: $sel_call"
            echo "  Country: $sel_country"
            echo "  Quality: $sel_quality"
            echo
            
            read -p "Use this station for field updates? (y/n): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
              # Show field comparison and get user choices
              show_field_comparison_and_update_simplified "$channel_id" "$channel_name" "$current_tvg_id" "$current_tvc_stationid" "$sel_station_id" "$sel_name" "$sel_call"
              local update_result=$?
              
              case $update_result in
                0)
                  echo -e "${GREEN}Field updates applied successfully${RESET}"
                  ;;
                1)
                  echo -e "${RED}Failed to apply field updates${RESET}"
                  ;;
                2)
                  echo -e "${CYAN}No field updates were requested${RESET}"
                  ;;
              esac
              pause_for_user
              return 0  # Complete processing
            fi
          else
            echo -e "${RED}Invalid selection${RESET}"
            sleep 1
          fi
        else
          echo -e "${RED}No results to select from${RESET}"
          sleep 1
        fi
        ;;
      n|N)
        if [[ $current_page -lt $total_pages ]]; then
          ((current_page++))
        else
          echo -e "${YELLOW}Already on last page${RESET}"
          sleep 1
        fi
        ;;
      p|P)
        if [[ $current_page -gt 1 ]]; then
          ((current_page--))
        else
          echo -e "${YELLOW}Already on first page${RESET}"
          sleep 1
        fi
        ;;
      s|S)
        read -p "Enter new search term: " new_search < /dev/tty
        if [[ -n "$new_search" ]]; then
          search_term="$new_search"
          current_page=1
          # FIXED: Clear auto-detected filters when user enters manual search
          detected_country=""
          detected_resolution=""
          echo -e "${CYAN}💡 Auto-detected filters cleared for manual search${RESET}"
        fi
        ;;
      r|R)
        echo -e "${CYAN}Returning to channel selection...${RESET}"
        return 1  # Return to channel selection
        ;;
      q|Q)
        echo -e "${CYAN}Returning to main menu...${RESET}"
        return 2  # Return to main menu
        ;;
      *)
        echo -e "${RED}Invalid option${RESET}"
        sleep 1
        ;;
    esac
  done
}

automatic_complete_data_replacement() {
  local channels_data="$1"
  
  clear
  echo -e "${BOLD}${RED}=== ⚠️  AUTOMATIC COMPLETE DATA REPLACEMENT ⚠️  ===${RESET}\n"
  echo -e "${RED}${BOLD}WARNING: MASS DATA REPLACEMENT OPERATION${RESET}"
  echo -e "${YELLOW}This will automatically replace field data for ALL channels that have station IDs.${RESET}"
  echo -e "${YELLOW}This operation can potentially affect hundreds of channels with NO individual confirmation.${RESET}"
  echo
  
  # Analyze channels with station IDs - FIXED: Use consistent sorting
  echo -e "${CYAN}🔍 Analyzing channels with existing station IDs...${RESET}"
  local channels_with_stationids
  channels_with_stationids=$(echo "$channels_data" | jq -c '.[] | select(.tvc_guide_stationid != null and .tvc_guide_stationid != "")' | jq -s 'sort_by(.channel_number | tonumber)' | jq -c '.[]')
  
  if [[ -z "$channels_with_stationids" ]]; then
    echo -e "${YELLOW}⚠️  No channels found with existing station IDs${RESET}"
    echo -e "${CYAN}💡 Channels need station IDs before using automatic data replacement${RESET}"
    echo -e "${CYAN}💡 Use 'Interactive Station ID Matching' first to assign station IDs${RESET}"
    pause_for_user
    return 0
  fi
  
  mapfile -t stationid_channels < <(echo "$channels_with_stationids")
  local channels_count=${#stationid_channels[@]}
  
  echo -e "${GREEN}✅ Found $channels_count channels with station IDs${RESET}"
  echo
  
  # Show preview of what will be affected - FIXED: Already sorted from above
  echo -e "${BOLD}${BLUE}=== Channels That Will Be Processed ===${RESET}"
  printf "${BOLD}${YELLOW}%-8s %-6s %-25s %-12s %-20s %s${RESET}\n" "Ch ID" "Number" "Channel Name" "Station ID" "Current Name" "Current TVG"
  echo "--------------------------------------------------------------------------------"
  
  local preview_count=$((channels_count > 10 ? 10 : channels_count))
  for ((i = 0; i < preview_count; i++)); do
    local channel_data="${stationid_channels[$i]}"
    local channel_id=$(echo "$channel_data" | jq -r '.id')
    local channel_name=$(echo "$channel_data" | jq -r '.name // "Unnamed"')
    local channel_number=$(echo "$channel_data" | jq -r '.channel_number // "N/A"')
    local station_id=$(echo "$channel_data" | jq -r '.tvc_guide_stationid')
    local current_tvg=$(echo "$channel_data" | jq -r '.tvg_id // "Empty"')
    
    printf "%-8s %-6s %-25s %-12s %-20s %s\n" \
      "$channel_id" \
      "$channel_number" \
      "${channel_name:0:25}" \
      "$station_id" \
      "${channel_name:0:20}" \
      "${current_tvg:0:10}"
  done
  
  if [[ $channels_count -gt 10 ]]; then
    echo -e "${CYAN}... and $((channels_count - 10)) more channels${RESET}"
  fi
  echo
  
  # Field selection for mass replacement
  echo -e "${BOLD}${BLUE}=== Field Selection for Mass Replacement ===${RESET}"
  echo -e "${YELLOW}Select which fields to update for ALL $channels_count channels:${RESET}"
  echo
  echo -e "${GREEN}1)${RESET} Channel Name - Replace with official station names"
  echo -e "${GREEN}2)${RESET} TVG-ID - Replace with station call signs"
  echo -e "${GREEN}3)${RESET} Channel Logo - Upload and assign station logos"
  echo -e "${GREEN}4)${RESET} All Fields - Replace name, TVG-ID, and logo"
  echo -e "${GREEN}c)${RESET} Custom Selection - Choose specific field combinations"
  echo
  
  local update_name=false
  local update_tvg=false
  local update_logo=false
  
  read -p "Select fields to update: " field_choice
  
  case "$field_choice" in
    1)
      update_name=true
      echo -e "${GREEN}✅ Will update: Channel Names only${RESET}"
      ;;
    2)
      update_tvg=true
      echo -e "${GREEN}✅ Will update: TVG-IDs only${RESET}"
      ;;
    3)
      update_logo=true
      echo -e "${GREEN}✅ Will update: Channel Logos only${RESET}"
      ;;
    4)
      update_name=true
      update_tvg=true
      update_logo=true
      echo -e "${GREEN}✅ Will update: All fields (Name, TVG-ID, Logo)${RESET}"
      ;;
    c|C)
      echo -e "\n${BOLD}Custom Field Selection:${RESET}"
      if confirm_action "Update channel names?"; then
        update_name=true
      fi
      if confirm_action "Update TVG-IDs?"; then
        update_tvg=true
      fi
      if confirm_action "Update channel logos?"; then
        update_logo=true
      fi
      
      local selected_fields=""
      $update_name && selected_fields+="Name "
      $update_tvg && selected_fields+="TVG-ID "
      $update_logo && selected_fields+="Logo "
      
      if [[ -z "$selected_fields" ]]; then
        echo -e "${RED}❌ No fields selected for update${RESET}"
        pause_for_user
        return 0
      fi
      
      echo -e "${GREEN}✅ Will update: $selected_fields${RESET}"
      ;;
    *)
      echo -e "${RED}❌ Invalid selection${RESET}"
      pause_for_user
      return 0
      ;;
  esac
  
  echo
  
  # CRITICAL SAFETY CONFIRMATION
  echo -e "${BOLD}${RED}=== FINAL SAFETY CONFIRMATION ===${RESET}"
  echo -e "${RED}${BOLD}⚠️  CRITICAL WARNING ⚠️${RESET}"
  echo
  echo -e "${YELLOW}You are about to automatically replace field data for $channels_count channels.${RESET}"
  echo -e "${YELLOW}This operation will:${RESET}"
  
  local operations=""
  if $update_name; then
    echo -e "${YELLOW}• Replace channel names with official station names${RESET}"
    operations+="names "
  fi
  if $update_tvg; then
    echo -e "${YELLOW}• Replace TVG-IDs with station call signs${RESET}"
    operations+="TVG-IDs "
  fi
  if $update_logo; then
    echo -e "${YELLOW}• Upload and assign station logos${RESET}"
    operations+="logos "
  fi
  
  echo
  echo -e "${RED}${BOLD}This operation CANNOT be easily undone!${RESET}"
  echo -e "${RED}Existing field data will be OVERWRITTEN without individual confirmation!${RESET}"
  echo
  echo -e "${CYAN}💡 Consider backing up your Dispatcharr configuration before proceeding${RESET}"
  echo
  
  # REQUIRE TYPING "proceed" to continue
  echo -e "${BOLD}${RED}Type the word 'proceed' (without quotes) to confirm this mass replacement:${RESET}"
  read -p "Confirmation: " safety_confirmation
  
  if [[ "$safety_confirmation" != "proceed" ]]; then
    echo -e "${YELLOW}⚠️  Automatic data replacement cancelled${RESET}"
    echo -e "${CYAN}💡 Safety confirmation failed - operation aborted${RESET}"
    pause_for_user
    return 0
  fi
  
  echo -e "${GREEN}✅ Safety confirmation accepted${RESET}"
  echo

  prepare_for_batch_operations "automatic data replacement" $((channels_count * 5))

  # Execute mass replacement - FIXED: Use properly sorted array
  echo -e "${BOLD}${CYAN}=== Executing Automatic Data Replacement ===${RESET}"
  echo -e "${CYAN}🔄 Processing $channels_count channels automatically...${RESET}"
  echo
  
  local success_count=0
  local failure_count=0
  local processed_count=0
  
  for channel_data in "${stationid_channels[@]}"; do
    ((processed_count++))
    local percent=$((processed_count * 100 / channels_count))
    
    local channel_id=$(echo "$channel_data" | jq -r '.id')
    local channel_name=$(echo "$channel_data" | jq -r '.name // "Unnamed"')
    local station_id=$(echo "$channel_data" | jq -r '.tvc_guide_stationid')
    
    # Show progress
    printf "\r${CYAN}[%3d%%] (%d/%d) Processing: %-25s (Station ID: %s)${RESET}" \
      "$percent" "$processed_count" "$channels_count" "${channel_name:0:25}" "$station_id"
    
    # Auto-match using reverse station ID lookup
    if automatic_field_population "$channel_id" "$station_id" "$update_name" "$update_tvg" "$update_logo"; then
      ((success_count++))
      # Token management for successful updates
      smart_token_management "automatic_updates" "batch"
    else
      ((failure_count++))
    fi
  done
  
  # Clear progress line
  echo
  echo
  
  # Show comprehensive results
  echo -e "${BOLD}${GREEN}=== Automatic Data Replacement Results ===${RESET}"
  printf "${BOLD}${YELLOW}%-25s %s${RESET}\n" "Result Category" "Count"
  echo "-----------------------------------"
  printf "%-25s %s\n" "Successfully processed:" "${GREEN}$success_count channels${RESET}"
  
  if [[ $failure_count -gt 0 ]]; then
    printf "%-25s %s\n" "Failed to process:" "${RED}$failure_count channels${RESET}"
  fi
  
  printf "%-25s %s\n" "Total processed:" "${CYAN}$((success_count + failure_count)) of $channels_count${RESET}"
  
  if [[ $channels_count -gt 0 ]]; then
    local success_rate=$(( (success_count * 100) / channels_count ))
    printf "%-25s %s\n" "Success rate:" "${GREEN}${success_rate}%${RESET}"
  fi
  echo
  
  # Show what was updated
  echo -e "${BOLD}${CYAN}Fields Updated:${RESET}"
  $update_name && echo -e "${GREEN}✅ Channel Names: Updated for all successfully processed channels${RESET}"
  $update_tvg && echo -e "${GREEN}✅ TVG-IDs: Updated for all successfully processed channels${RESET}"
  $update_logo && echo -e "${GREEN}✅ Channel Logos: Updated for all successfully processed channels${RESET}"
  echo
  
  if [[ $success_count -gt 0 ]]; then
    echo -e "${BOLD}${CYAN}Next Steps:${RESET}"
    echo -e "• All changes are now active in Dispatcharr"
    echo -e "• $success_count channels have been enhanced with station data"
    echo -e "• Channel information is now synchronized with your station database"
    
    if [[ $failure_count -eq 0 ]]; then
      echo -e "${GREEN}💡 Perfect! All channels processed successfully${RESET}"
    else
      echo -e "${YELLOW}💡 $failure_count channels need manual attention${RESET}"
    fi
  else
    echo -e "${RED}❌ No channels were successfully processed${RESET}"
    echo -e "${CYAN}💡 Check Dispatcharr connection and station database${RESET}"
  fi
  
  pause_for_user
}

automatic_field_population() {
  local channel_id="$1"
  local station_id="$2"
  local update_name="$3"
  local update_tvg="$4"
  local update_logo="$5"
  
  # Get station data from local database using reverse lookup
  local stations_file
  stations_file=$(get_effective_stations_file)
  if [ $? -ne 0 ]; then
    return 1
  fi
  
  local station_data
  station_data=$(jq -r --arg id "$station_id" '.[] | select(.stationId == $id)' "$stations_file" 2>/dev/null)
  
  if [[ -z "$station_data" || "$station_data" == "null" ]]; then
    return 1  # Station not found in local database
  fi
  
  # Extract station information
  local station_name=$(echo "$station_data" | jq -r '.name // empty')
  local call_sign=$(echo "$station_data" | jq -r '.callSign // empty')
  local logo_url=$(echo "$station_data" | jq -r '.preferredImage.uri // empty')
  
  # Build update data
  local update_data="{}"
  local logo_id=""
  
  if [[ "$update_name" == "true" ]] && [[ -n "$station_name" && "$station_name" != "null" ]]; then
    update_data=$(echo "$update_data" | jq --arg name "$station_name" '. + {name: $name}')
  fi
  
  if [[ "$update_tvg" == "true" ]] && [[ -n "$call_sign" && "$call_sign" != "null" ]]; then
    update_data=$(echo "$update_data" | jq --arg tvg_id "$call_sign" '. + {tvg_id: $tvg_id}')
  fi
  
  if [[ "$update_logo" == "true" ]] && [[ -n "$logo_url" && "$logo_url" != "null" ]]; then
    logo_id=$(upload_station_logo_to_dispatcharr "$station_name" "$logo_url")
    if [[ -n "$logo_id" && "$logo_id" != "null" ]]; then
      update_data=$(echo "$update_data" | jq --argjson logo_id "$logo_id" '. + {logo_id: $logo_id}')
    fi
  fi
  
  # Apply updates to Dispatcharr
  if [[ "$update_data" != "{}" ]]; then
    local token_file="$CACHE_DIR/dispatcharr_tokens.json"
    local access_token
    if [[ -f "$token_file" ]]; then
      access_token=$(jq -r '.access // empty' "$token_file" 2>/dev/null)
    fi
    
    if [[ -n "$access_token" && "$access_token" != "null" ]]; then
      # Smart token management for automatic field updates
      smart_token_management "automatic_field_updates" "batch"
      
      local response
      response=$(curl -s -X PATCH \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        -d "$update_data" \
        "${DISPATCHARR_URL}/api/channels/channels/${channel_id}/" 2>/dev/null)
      
      if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        return 0
      fi
    fi
  fi
  
  return 1
}

show_field_comparison_and_update_simplified() {
  local channel_id="$1"
  local channel_name="$2"
  local current_tvg_id="$3"
  local current_tvc_stationid="$4"
  local station_id="$5"
  local station_name="$6"
  local call_sign="$7"
  
  # Get current channel info to see existing logo
  local token_file="$CACHE_DIR/dispatcharr_tokens.json"
  local access_token
  if [[ -f "$token_file" ]]; then
    access_token=$(jq -r '.access // empty' "$token_file" 2>/dev/null)
  fi
  
  local current_logo_id=""
  if [[ -n "$access_token" && "$access_token" != "null" ]]; then
    local channel_info
    channel_info=$(curl -s -H "Authorization: Bearer $access_token" \
      "${DISPATCHARR_URL}/api/channels/channels/${channel_id}/" 2>/dev/null)
    
    if echo "$channel_info" | jq empty 2>/dev/null; then
      current_logo_id=$(echo "$channel_info" | jq -r '.logo_id // empty')
    fi
  fi
  
  # Get logo URL from station database
  local logo_url=""
  local stations_file
  stations_file=$(get_effective_stations_file)
  if [[ $? -eq 0 ]]; then
    logo_url=$(jq -r --arg id "$station_id" \
      '.[] | select(.stationId == $id) | .preferredImage.uri // empty' \
      "$stations_file" 2>/dev/null | head -n 1)
  fi
  
  echo
  echo -e "${BOLD}${GREEN}=== Field Comparison & Update Options ===${RESET}\n"
  
  echo -e "${BOLD}Matched Station:${RESET}"
  echo -e "Name: ${GREEN}$station_name${RESET}"
  echo -e "Call Sign: ${GREEN}$call_sign${RESET}"
  echo -e "Station ID: ${GREEN}$station_id${RESET}"
  echo
  
  # LOGO COMPARISON SECTION
  echo -e "${BOLD}${CYAN}=== Logo Comparison ===${RESET}"
  echo
  
  # Show current Dispatcharr logo
  if [[ -n "$current_logo_id" && "$current_logo_id" != "null" ]]; then
    display_dispatcharr_logo "$current_logo_id" "Current Dispatcharr Logo"
  else
    echo "   Current Dispatcharr Logo: ${YELLOW}No logo set${RESET}"
  fi
  echo
  
  # Show potential replacement from station database
  if [[ -n "$logo_url" && "$logo_url" != "null" ]]; then
    display_station_logo_preview "$logo_url" "Potential Replacement"
  else
    echo "   Potential Replacement: ${YELLOW}No logo available${RESET}"
  fi
  echo
  
  # Field-by-field comparison - track if any changes are requested
  echo -e "${BOLD}${CYAN}=== Proposed Field Updates ===${RESET}"
  echo
  
  local changes_requested=false
  
  # 1. Channel Name
  echo -e "${BOLD}1. Channel Name:${RESET}"
  echo -e "   Current:  ${YELLOW}$channel_name${RESET}"
  echo -e "   Proposed: ${GREEN}$station_name${RESET}"
  local update_name="n"
  if [[ "$channel_name" != "$station_name" ]]; then
    read -p "   Update channel name? (y/n): " update_name
    if [[ "$update_name" =~ ^[Yy]$ ]]; then
      changes_requested=true
    fi
  else
    echo -e "   ${CYAN}(already matches)${RESET}"
  fi
  echo
  
  # 2. TVG-ID
  echo -e "${BOLD}2. TVG-ID:${RESET}"
  echo -e "   Current:  ${YELLOW}${current_tvg_id:-"(empty)"}${RESET}"
  echo -e "   Proposed: ${GREEN}$call_sign${RESET}"
  local update_tvg="n"
  if [[ "$current_tvg_id" != "$call_sign" ]]; then
    read -p "   Update TVG-ID? (y/n): " update_tvg
    if [[ "$update_tvg" =~ ^[Yy]$ ]]; then
      changes_requested=true
    fi
  else
    echo -e "   ${CYAN}(already matches)${RESET}"
  fi
  echo
  
  # 3. TVC Guide Station ID
  echo -e "${BOLD}3. TVC Guide Station ID:${RESET}"
  echo -e "   Current:  ${YELLOW}${current_tvc_stationid:-"(empty)"}${RESET}"
  echo -e "   Proposed: ${GREEN}$station_id${RESET}"
  local update_station_id="n"
  if [[ "$current_tvc_stationid" != "$station_id" ]]; then
    read -p "   Update TVC Guide Station ID? (y/n): " update_station_id
    if [[ "$update_station_id" =~ ^[Yy]$ ]]; then
      changes_requested=true
    fi
  else
    echo -e "   ${CYAN}(already matches)${RESET}"
  fi
  echo
  
  # 4. Logo
  echo -e "${BOLD}4. Channel Logo:${RESET}"
  local update_logo="n"
  local logo_id=""
  if [[ -n "$logo_url" && "$logo_url" != "null" ]]; then
    read -p "   Upload and set station logo? (y/n): " update_logo
    
    if [[ "$update_logo" =~ ^[Yy]$ ]]; then
      echo -e "   ${CYAN}Uploading logo to Dispatcharr...${RESET}"
      logo_id=$(upload_station_logo_to_dispatcharr "$station_name" "$logo_url")
      if [[ -n "$logo_id" && "$logo_id" != "null" ]]; then
        echo -e "   ${GREEN}✅ Logo uploaded successfully (ID: $logo_id)${RESET}"
        changes_requested=true
      else
        echo -e "   ${RED}❌ Logo upload failed${RESET}"
        update_logo="n"
      fi
    fi
  else
    echo -e "   Station Logo: ${YELLOW}Not available${RESET}"
  fi
  echo
  
  # Apply updates only if changes were requested
  if [[ "$changes_requested" == "true" ]]; then
    echo -e "${CYAN}Applying updates...${RESET}"
    
    if update_dispatcharr_channel_with_logo "$channel_id" "$update_name" "$station_name" "$update_tvg" "$call_sign" "$update_station_id" "$station_id" "$update_logo" "$logo_id"; then
      echo -e "${GREEN}✅ Successfully updated channel fields${RESET}"
      return 0  # Success - changes were applied
    else
      echo -e "${RED}❌ Failed to update some channel fields${RESET}"
      return 1  # Failure
    fi
  else
    echo -e "${CYAN}💡 No field updates requested - all fields already match or were skipped${RESET}"
    return 2  # No changes requested (different from failure)
  fi
}

update_dispatcharr_channel_with_logo() {
  local channel_id="$1"
  local update_name="$2"
  local new_name="$3"
  local update_tvg="$4"
  local new_tvg_id="$5"
  local update_station_id="$6"
  local new_station_id="$7"
  local update_logo="$8"
  local logo_id="$9"
  
  smart_token_management "field_updates" "interactive"
  
  local token_file="$CACHE_DIR/dispatcharr_tokens.json"
  
  # Ensure we have a valid connection/token
  if ! dispatcharr_test_connection >/dev/null 2>&1; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Failed to connect to Dispatcharr for channel ID $channel_id" >> "$DISPATCHARR_LOG"
    return 1
  fi
  
  # Get current access token
  local access_token
  if [[ -f "$token_file" ]]; then
    access_token=$(jq -r '.access // empty' "$token_file" 2>/dev/null)
  fi
  
  if [[ -z "$access_token" || "$access_token" == "null" ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - No valid access token for channel ID $channel_id" >> "$DISPATCHARR_LOG"
    return 1
  fi
  
  # Build update data JSON with logo support
  local update_data="{}"
  
  if [[ "$update_name" =~ ^[Yy]$ ]]; then
    update_data=$(echo "$update_data" | jq --arg name "$new_name" '. + {name: $name}')
  fi
  
  if [[ "$update_tvg" =~ ^[Yy]$ ]]; then
    update_data=$(echo "$update_data" | jq --arg tvg_id "$new_tvg_id" '. + {tvg_id: $tvg_id}')
  fi
  
  if [[ "$update_station_id" =~ ^[Yy]$ ]]; then
    update_data=$(echo "$update_data" | jq --arg station_id "$new_station_id" '. + {tvc_guide_stationid: $station_id}')
  fi
  
  # NEW: Add logo ID if provided (field name is "logo_id" not "logo")
  if [[ "$update_logo" =~ ^[Yy]$ ]] && [[ -n "$logo_id" && "$logo_id" != "null" ]]; then
    update_data=$(echo "$update_data" | jq --argjson logo_id "$logo_id" '. + {logo_id: $logo_id}')
  fi
  
  # Send PATCH request
  local response
  response=$(curl -s -X PATCH \
    -H "Authorization: Bearer $access_token" \
    -H "Content-Type: application/json" \
    -d "$update_data" \
    "${DISPATCHARR_URL}/api/channels/channels/${channel_id}/" 2>/dev/null)
  
  if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
    local log_msg="Updated channel ID $channel_id:"
    [[ "$update_name" =~ ^[Yy]$ ]] && log_msg+=" name=yes"
    [[ "$update_tvg" =~ ^[Yy]$ ]] && log_msg+=" tvg=yes"
    [[ "$update_station_id" =~ ^[Yy]$ ]] && log_msg+=" station=yes"
    [[ "$update_logo" =~ ^[Yy]$ ]] && log_msg+=" logo=$logo_id"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $log_msg" >> "$DISPATCHARR_LOG"
    return 0
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Failed to update channel ID $channel_id: $response" >> "$DISPATCHARR_LOG"
    return 1
  fi
}

upload_station_logo_to_dispatcharr() {
  local station_name="$1"
  local logo_url="$2"
  
  if [[ -z "$logo_url" || "$logo_url" == "null" ]]; then
    return 1
  fi
  
  # Check for existing logo first
  local existing_logo_id=$(check_existing_dispatcharr_logo "$logo_url")
  if [[ -n "$existing_logo_id" && "$existing_logo_id" != "null" ]]; then
    echo "$existing_logo_id"
    return 0
  fi
  
  # Upload new logo
  local response
  response=$(dispatcharr_upload_logo "$station_name" "$logo_url")
  
  if [[ $? -eq 0 ]]; then
    local logo_id=$(echo "$response" | jq -r '.id')
    cache_dispatcharr_logo_info "$logo_url" "$logo_id" "$station_name"
    echo "$logo_id"
    return 0
  else
    return 1
  fi
}

check_existing_dispatcharr_logo() {
  local logo_url="$1"
  
  # First check our local cache
  if [[ -f "$DISPATCHARR_LOGOS" ]]; then
    local cached_id=$(jq -r --arg url "$logo_url" '.[$url].id // empty' "$DISPATCHARR_LOGOS" 2>/dev/null)
    if [[ -n "$cached_id" && "$cached_id" != "null" ]]; then
      echo "$cached_id"
      return 0
    fi
  fi
  
  # If not in local cache, query Dispatcharr API
  local token_file="$CACHE_DIR/dispatcharr_tokens.json"
  local access_token
  if [[ -f "$token_file" ]]; then
    access_token=$(jq -r '.access // empty' "$token_file" 2>/dev/null)
  fi
  
  if [[ -n "$access_token" && "$access_token" != "null" ]]; then
    local response
    response=$(curl -s -H "Authorization: Bearer $access_token" \
      "${DISPATCHARR_URL}/api/channels/logos/" 2>/dev/null)
    
    if echo "$response" | jq empty 2>/dev/null; then
      local logo_id=$(echo "$response" | jq -r --arg url "$logo_url" \
        '.[] | select(.url == $url) | .id // empty' 2>/dev/null)
      
      if [[ -n "$logo_id" && "$logo_id" != "null" ]]; then
        # Cache this for future use
        local logo_name=$(echo "$response" | jq -r --arg url "$logo_url" \
          '.[] | select(.url == $url) | .name // empty' 2>/dev/null)
        cache_dispatcharr_logo_info "$logo_url" "$logo_id" "$logo_name"
        echo "$logo_id"
        return 0
      fi
    fi
  fi
  
  return 1
}

cache_dispatcharr_logo_info() {
  local logo_url="$1"
  local logo_id="$2"
  local logo_name="$3"
  
  # Initialize cache file if it doesn't exist
  if [[ ! -f "$DISPATCHARR_LOGOS" ]]; then
    echo '{}' > "$DISPATCHARR_LOGOS"
  fi
  
  # Add/update logo info in cache
  local temp_file="${DISPATCHARR_LOGOS}.tmp"
  jq --arg url "$logo_url" \
     --arg id "$logo_id" \
     --arg name "$logo_name" \
     --arg timestamp "$(date -Iseconds)" \
     '. + {($url): {id: $id, name: $name, cached: $timestamp}}' \
     "$DISPATCHARR_LOGOS" > "$temp_file" 2>/dev/null
  
  if [[ $? -eq 0 ]]; then
    mv "$temp_file" "$DISPATCHARR_LOGOS"
  else
    rm -f "$temp_file"
  fi
}

display_dispatcharr_logo() {
  local logo_id="$1"
  local label="$2"
  
  if [[ -z "$logo_id" || "$logo_id" == "null" ]]; then
    echo -e "   $label: ${YELLOW}No logo${RESET}"
    return 1
  fi
  
  if [[ "$SHOW_LOGOS" == "true" ]] && command -v viu >/dev/null 2>&1; then
    echo "   $label:"
    
    # Download logo to temp file
    local temp_logo="/tmp/dispatcharr_logo_${logo_id}_$(date +%s).png"
    
    if dispatcharr_download_logo_file "$logo_id" "$temp_logo"; then
      local mime_type=$(file --mime-type -b "$temp_logo" 2>/dev/null)
      if [[ "$mime_type" == image/* ]]; then
        viu -h 3 -w 20 "$temp_logo" 2>/dev/null || echo "   [logo display failed]"
      else
        echo "   [invalid image format]"
      fi
      rm -f "$temp_logo"
    else
      echo "   [failed to download logo]"
    fi
  else
    echo -e "   $label: ${GREEN}Logo ID $logo_id${RESET} [logo preview unavailable]"
  fi
}

display_station_logo_preview() {
  local logo_url="$1"
  local label="$2"
  
  if [[ -z "$logo_url" || "$logo_url" == "null" ]]; then
    echo "   $label: ${YELLOW}No logo available${RESET}"
    return 1
  fi
  
  if [[ "$SHOW_LOGOS" == "true" ]] && command -v viu >/dev/null 2>&1; then
    echo "   $label:"
    
    # Download logo to temp file
    local temp_logo="/tmp/station_logo_preview_$(date +%s).png"
    
    if curl -s "$logo_url" --output "$temp_logo" 2>/dev/null; then
      local mime_type=$(file --mime-type -b "$temp_logo" 2>/dev/null)
      if [[ "$mime_type" == image/* ]]; then
        viu -h 3 -w 20 "$temp_logo" 2>/dev/null || echo "   [logo preview failed]"
      else
        echo "   [invalid image format]"
      fi
      rm -f "$temp_logo"
    else
      echo "   [failed to download logo preview]"
    fi
  else
    echo -e "   $label: ${GREEN}Available${RESET} [logo preview unavailable]"
    echo -e "   URL: $logo_url"  # Removed ${CYAN} and ${RESET}
  fi
}

cleanup_dispatcharr_logo_cache() {
  if [[ -f "$DISPATCHARR_LOGOS" ]]; then
    # Remove entries older than 30 days
    local cutoff_date=$(date -d '30 days ago' -Iseconds 2>/dev/null || date -v-30d -Iseconds 2>/dev/null)
    if [[ -n "$cutoff_date" ]]; then
      local temp_file="${DISPATCHARR_LOGOS}.tmp"
      jq --arg cutoff "$cutoff_date" \
        'to_entries | map(select(.value.cached >= $cutoff)) | from_entries' \
        "$DISPATCHARR_LOGOS" > "$temp_file" 2>/dev/null
      
      if [[ $? -eq 0 ]]; then
        mv "$temp_file" "$DISPATCHARR_LOGOS"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Cleaned up old logo cache entries" >> "$DISPATCHARR_LOG"
      else
        rm -f "$temp_file"
      fi
    fi
  fi
}

view_dispatcharr_logs() {
  echo -e "\n${BOLD}Dispatcharr Integration Logs${RESET}"
  
  if [[ ! -f "$DISPATCHARR_LOG" ]]; then
    echo -e "${YELLOW}No logs found${RESET}"
    return 0
  fi
  
  echo
  echo -e "${BOLD}Recent Operations:${RESET}"
  tail -20 "$DISPATCHARR_LOG" | while IFS= read -r line; do
    if [[ "$line" == *"Updated"* ]]; then
      echo -e "${GREEN}$line${RESET}"
    elif [[ "$line" == *"Failed"* ]]; then
      echo -e "${RED}$line${RESET}"
    elif [[ "$line" == *"JWT tokens generated"* ]]; then
      echo -e "${CYAN}$line${RESET}"
    else
      echo "$line"
    fi
  done
  
  echo
  local total_operations
  total_operations=$(wc -l < "$DISPATCHARR_LOG" 2>/dev/null || echo "0")
  echo "Total operations logged: $total_operations"
  
  # Show token status if available
  local token_file="$CACHE_DIR/dispatcharr_tokens.json"
  if [[ -f "$token_file" ]]; then
    echo
    echo -e "${BOLD}Current Token Status:${RESET}"
    local access_token=$(jq -r '.access // empty' "$token_file" 2>/dev/null)
    if [[ -n "$access_token" && "$access_token" != "null" ]]; then
      echo -e "${GREEN}✅ Access token available${RESET}"
      # Try to decode JWT to show expiration (basic parsing)
      local exp_claim=$(echo "$access_token" | cut -d'.' -f2 | base64 -d 2>/dev/null | jq -r '.exp // empty' 2>/dev/null)
      if [[ -n "$exp_claim" && "$exp_claim" != "null" ]]; then
        local exp_date=$(date -d "@$exp_claim" 2>/dev/null || echo "Unknown")
        echo -e "   Expires: $exp_date"
      fi
    else
      echo -e "${RED}❌ No valid access token${RESET}"
    fi
    
    local refresh_token=$(jq -r '.refresh // empty' "$token_file" 2>/dev/null)
    if [[ -n "$refresh_token" && "$refresh_token" != "null" ]]; then
      echo -e "${GREEN}✅ Refresh token available${RESET}"
    else
      echo -e "${YELLOW}⚠️  No refresh token${RESET}"
    fi
  fi
  
  return 0
}

dispatcharr_integration_check() {
  if [[ "$DISPATCHARR_ENABLED" == "true" ]]; then
    run_dispatcharr_integration
  else
    echo -e "${YELLOW}Dispatcharr integration is disabled${RESET}"
    echo -e "${CYAN}Enable it in Settings > Dispatcharr Configuration${RESET}"
    pause_for_user
  fi
}

run_dispatcharr_integration() {
  # Always refresh tokens when entering Dispatcharr integration
  if [[ "$DISPATCHARR_ENABLED" == "true" ]]; then
    echo -e "${CYAN}🔄 Initializing Dispatcharr Integration...${RESET}"
    
    if ! authenticate_dispatcharr; then
      echo -e "${RED}❌ Cannot continue without valid authentication${RESET}"
      echo -e "${CYAN}💡 Please check your Dispatcharr connection settings${RESET}"
      pause_for_user
      return 1
    fi
    echo
  fi
  
  while true; do
    maintain_session_tokens
    
    show_dispatcharr_menu
    
    read -p "Select option: " choice < /dev/tty
    
    case $choice in
      a|A) 
        show_menu_transition "starting" "channel scan"
        scan_missing_stationids 
        ;;
      b|B) 
        show_menu_transition "starting" "interactive matching"
        interactive_stationid_matching 
        ;;
      c|C) 
        show_menu_transition "starting" "station ID changes processing"
        batch_update_stationids && pause_for_user 
        ;;
      d|D) 
        show_menu_transition "starting" "field population"
        populate_dispatcharr_fields 
        ;;
      e|E) 
        show_menu_transition "opening" "connection configuration"
        configure_dispatcharr_connection && pause_for_user 
        ;;
      f|F) 
        show_menu_transition "loading" "integration logs"
        view_dispatcharr_logs && pause_for_user 
        ;;
      g|G) 
        show_menu_transition "starting" "token refresh"
        authenticate_dispatcharr && pause_for_user 
        ;;
      q|Q|"") 
        show_menu_transition "returning" "main menu"
        break 
        ;;
      *) 
        show_invalid_menu_choice "Dispatcharr Integration" "$choice"
        ;;
    esac
  done
}

# ============================================================================
# MARKET MANAGEMENT FUNCTIONS
# ============================================================================

add_market() {
  clear
  echo -e "${BOLD}${CYAN}=== Add New Market ===${RESET}\n"
  echo -e "${BLUE}📍 Configure Geographic Market for Station Caching${RESET}"
  echo -e "${YELLOW}Markets determine which regions' stations will be cached for Local Database Search.${RESET}"
  echo
  
  # STANDARDIZED: Enhanced postal code guidance with regional examples
  echo -e "${BOLD}${BLUE}Postal Code Guidelines by Country:${RESET}"
  echo
  echo -e "${GREEN}🇺🇸 USA${RESET} - Use 5-digit ZIP codes:"
  echo -e "${CYAN}   Examples: 90210 (Beverly Hills), 10001 (New York), 60601 (Chicago)${RESET}"
  echo -e "${CYAN}   💡 Use the main ZIP code for the area, not ZIP+4 extensions${RESET}"
  echo
  echo -e "${GREEN}🇬🇧 United Kingdom${RESET} - Use district portion only:"
  echo -e "${CYAN}   Examples: SW1A (Westminster), M1 (Manchester), EH1 (Edinburgh)${RESET}"
  echo -e "${CYAN}   💡 Use the area/district code before the space, not full postcodes${RESET}"
  echo
  echo -e "${GREEN}🇨🇦 Canada${RESET} - Use forward sortation area:"
  echo -e "${CYAN}   Examples: M5V (Toronto), K1A (Ottawa), V6B (Vancouver)${RESET}"
  echo -e "${CYAN}   💡 Use the first 3 characters before the space${RESET}"
  echo
  echo -e "${CYAN}💡 If unsure, try the main area/district code first${RESET}"
  echo -e "${CYAN}💡 These formats work best with TV lineup APIs${RESET}"
  echo
  
  local country zip normalized_zip
  
  # STANDARDIZED: Country input with validation and guidance
  while true; do
    echo -e "${BOLD}Step 1: Country Selection${RESET}"
    echo -e "${CYAN}Enter the 3-letter ISO country code (e.g., USA, CAN, GBR):${RESET}"
    read -p "Country code: " country < /dev/tty
    
    if [[ -z "$country" ]]; then
      echo -e "${YELLOW}⚠️  Add Market: Operation cancelled${RESET}"
      return 1
    fi
    
    # FIXED: Normalize to uppercase IMMEDIATELY and consistently
    country=$(echo "$country" | tr '[:lower:]' '[:upper:]')
    
    # Debug output to confirm normalization
    echo -e "${CYAN}💡 Normalized country code: '$country'${RESET}"
    
    # Validate against known country codes
    if grep -Fxq "$country" "$VALID_CODES_FILE" 2>/dev/null; then
      echo -e "${GREEN}✅ Country code '$country' is valid${RESET}"
      break
    else
      echo -e "${RED}❌ Invalid country code: '$country'${RESET}"
      echo -e "${CYAN}💡 Must be a valid 3-letter ISO code (examples: USA, CAN, GBR, DEU, FRA)${RESET}"
      echo -e "${CYAN}💡 Check the country list or try common alternatives${RESET}"
      echo
    fi
  done
  
  echo
  
  # STANDARDIZED: ZIP/Postal code input with normalization guidance
  echo -e "${BOLD}Step 2: Postal Code Entry${RESET}"
  echo -e "${CYAN}Enter the ZIP/postal code for the area you want to cache:${RESET}"
  read -p "ZIP/Postal Code: " zip < /dev/tty
  
  if [[ -z "$zip" ]]; then
    echo -e "${YELLOW}⚠️  Add Market: Operation cancelled${RESET}"
    return 1
  fi
  
  # STANDARDIZED: Postal code normalization with user feedback
  echo -e "\n${CYAN}🔄 Processing postal code...${RESET}"
  
  # Normalize postal code - take only first segment if there's a space
  if [[ "$zip" == *" "* ]]; then
    normalized_zip=$(echo "$zip" | cut -d' ' -f1)
    echo -e "${YELLOW}⚠️  Postal code '$zip' normalized to '$normalized_zip'${RESET}"
    echo -e "${CYAN}💡 Using first segment only - this format works better with TV lineup APIs${RESET}"
    echo -e "${CYAN}💡 Full postcodes often don't match API expectations${RESET}"
  else
    normalized_zip="$zip"
    echo -e "${GREEN}✅ Postal code '$zip' accepted as-is${RESET}"
  fi
  
  # FIXED: Remove any remaining spaces and convert to uppercase for consistency
  normalized_zip=$(echo "$normalized_zip" | tr -d ' ' | tr '[:lower:]' '[:upper:]')
  
  if [[ "$normalized_zip" != "$zip" ]]; then
    echo -e "${CYAN}💡 Final format: '$normalized_zip' (uppercase, no spaces)${RESET}"
  fi
  
  echo
  
  # STANDARDIZED: Market validation and duplicate checking
  echo -e "${CYAN}🔍 Checking if market already exists...${RESET}"
  
  # Create CSV file with header if it doesn't exist
  if [ ! -f "$CSV_FILE" ]; then
    echo "Country,ZIP" > "$CSV_FILE"
    echo -e "${GREEN}✅ Created new markets configuration file${RESET}"
  fi
  
  # ENHANCED: Check for duplicates with clear messaging
  if grep -q "^$country,$normalized_zip$" "$CSV_FILE"; then
    echo -e "${RED}❌ Market Already Exists${RESET}"
    echo -e "${YELLOW}⚠️  The market $country/$normalized_zip is already in your configuration${RESET}"
    echo
    return 1
  else
    # STANDARDIZED: Successful addition with confirmation
    # FIXED: Use the normalized, uppercase country code in the CSV
    echo -e "${CYAN}💡 Writing to CSV: '$country,$normalized_zip'${RESET}"
    echo "$country,$normalized_zip" >> "$CSV_FILE"
    echo -e "${GREEN}✅ Market Added Successfully: ${BOLD}$country/$normalized_zip${RESET}"
    echo
    
    # Show current market count
    local total_markets=$(awk 'END {print NR-1}' "$CSV_FILE")
    echo -e "${CYAN}📊 Total configured markets: $total_markets${RESET}"
    echo
    
    # STANDARDIZED: Next steps guidance
    echo -e "${BOLD}${CYAN}Next Steps:${RESET}"
    echo -e "${GREEN}• Add more markets if needed (different regions expand station coverage)${RESET}"
    echo -e "${GREEN}• Use 'Run User Caching' to download stations from all configured markets${RESET}"
    echo -e "${GREEN}• Stations from all markets will be combined and deduplicated automatically${RESET}"
    echo
    
    return 0  # Don't call pause_for_user here - let the calling function handle it
  fi
}

remove_market() {
  clear
  echo -e "${BOLD}${CYAN}=== Remove Market ===${RESET}\n"
  echo -e "${BLUE}📍 Remove Geographic Market from Configuration${RESET}"
  echo -e "${YELLOW}This will remove the market from your configuration but won't affect already-cached stations.${RESET}"
  echo
  
  # STANDARDIZED: Check if markets exist before proceeding
  if [ ! -f "$CSV_FILE" ] || [ ! -s "$CSV_FILE" ]; then
    echo -e "${YELLOW}⚠️  No Markets Configured${RESET}"
    echo -e "${CYAN}💡 No markets found to remove${RESET}"
    echo -e "${CYAN}💡 Use 'Add Market' to configure markets first${RESET}"
    echo
    return 1
  fi
  
  # STANDARDIZED: Show current markets with professional table formatting
  local market_count=$(awk 'END {print NR-1}' "$CSV_FILE")
  echo -e "${BOLD}Current Markets (${market_count} total):${RESET}"
  echo
  
  # STANDARDIZED: Professional table pattern with consistent formatting
  printf "${BOLD}${YELLOW}%-15s %-15s %s${RESET}\n" "Country" "ZIP/Postal" "Status"
  echo "------------------------------------------------"
  
  tail -n +2 "$CSV_FILE" | while IFS=, read -r country zip; do
    # Check if market has been cached
    local status=""
    if is_market_cached "$country" "$zip"; then
      status="${GREEN}Cached${RESET}"
    else
      status="${YELLOW}Not cached${RESET}"
    fi
    printf "%-15s %-15s " "$country" "$zip"
    echo -e "$status"
  done
  echo
  
  # STANDARDIZED: Market selection with validation
  local country zip
  
  echo -e "${BOLD}Step 1: Select Market to Remove${RESET}"
  echo -e "${CYAN}Enter the country code and ZIP/postal code exactly as shown above:${RESET}"
  echo
  
  local country
  while true; do
    read -p "Country code to remove: " country < /dev/tty
    if [[ -z "$country" ]]; then
      echo -e "${YELLOW}⚠️  Remove Market: Operation cancelled${RESET}"
      return 1
    fi
    
    # Normalize country to uppercase
    country=$(echo "$country" | tr '[:lower:]' '[:upper:]')
    
    # Validate against known country codes
    if grep -Fxq "$country" "$VALID_CODES_FILE" 2>/dev/null; then
      echo -e "${GREEN}✅ Country code '$country' is valid${RESET}"
      break
    else
      echo -e "${RED}❌ Invalid country code: '$country'${RESET}"
      echo -e "${CYAN}💡 Must be a valid 3-letter ISO code from the table above${RESET}"
      echo -e "${CYAN}💡 Examples: USA, CAN, GBR, AUS, DEU, FRA${RESET}"
      echo
      echo -e "${YELLOW}Please try again or press Enter to cancel:${RESET}"
    fi
  done
  
  local zip
  read -p "ZIP/Postal code to remove: " zip < /dev/tty
  if [[ -z "$zip" ]]; then
    echo -e "${YELLOW}⚠️  Remove Market: Operation cancelled${RESET}"
    return 1
  fi
  
  # Normalize ZIP to uppercase and remove spaces
  zip=$(echo "$zip" | tr -d ' ' | tr '[:lower:]' '[:upper:]')
  
  echo
  
  # STANDARDIZED: Market existence validation
  echo -e "${CYAN}🔍 Checking if market exists in configuration...${RESET}"
  
  if grep -q "^$country,$zip$" "$CSV_FILE"; then
    echo -e "${GREEN}✅ Market found: $country/$zip${RESET}"
    echo
    
    # STANDARDIZED: Impact analysis and confirmation with table display
    echo -e "${BOLD}${BLUE}Removal Impact Analysis:${RESET}"
    
    # FIXED: Use echo -e instead of printf for colored text
    echo -e "${BOLD}${YELLOW}Impact Category          Details${RESET}"
    echo "----------------------------------------"
    
    # Check if market was cached and use echo -e for proper color rendering
    if is_market_cached "$country" "$zip"; then
      echo -e "Cached Status:           ${YELLOW}Market has been cached${RESET}"
      echo -e "Station Impact:          ${CYAN}Stations remain in database${RESET}"
      echo -e "Future Processing:       ${CYAN}Market will be skipped${RESET}"
    else
      echo -e "Cached Status:           ${GREEN}Market not cached yet${RESET}"
      echo -e "Station Impact:          ${CYAN}No impact on database${RESET}"
      echo -e "Future Processing:       ${CYAN}Market removed from queue${RESET}"
    fi
    echo -e "Configuration:           ${RED}Will be removed${RESET}"
    echo
    
    # STANDARDIZED: Confirmation with clear consequences
    echo -e "${BOLD}Confirm Market Removal:${RESET}"
    
    # FIXED: Use echo -e instead of printf for colored confirmation details
    echo -e "${BOLD}${YELLOW}Field               Value${RESET}"
    echo "--------------------------------"
    echo -e "Market:             ${YELLOW}$country/$zip${RESET}"
    echo -e "Action:             ${RED}Remove from configuration${RESET}"
    echo -e "Impact:             ${CYAN}Configuration only${RESET}"
    echo -e "Cached Data:        ${CYAN}Preserved${RESET}"
    echo
    
    if confirm_action "Remove market $country/$zip from configuration?"; then
      # STANDARDIZED: Perform removal with feedback
      echo -e "${CYAN}🔄 Removing market from configuration...${RESET}"
      
      # Create backup before modification
      local backup_file="${CSV_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
      if cp "$CSV_FILE" "$backup_file" 2>/dev/null; then
        echo -e "${CYAN}💡 Configuration backed up to: $(basename "$backup_file")${RESET}"
      fi
      
      # Remove the market entry
      sed -i'' "/^$country,$zip$/d" "$CSV_FILE"
      
      # Verify removal
      if ! grep -q "^$country,$zip$" "$CSV_FILE"; then
        echo -e "${GREEN}✅ Market Removed Successfully: $country/$zip${RESET}"
        
        # Show updated market count
        local new_market_count=$(awk 'END {print NR-1}' "$CSV_FILE")
        echo
        
        # FIXED: Use echo -e instead of printf for colored results summary
        echo -e "${BOLD}${YELLOW}Removal Results Summary${RESET}"
        echo "------------------------------------"
        echo -e "Market Removed:          ${GREEN}$country/$zip${RESET}"
        echo -e "Remaining Markets:       ${CYAN}$new_market_count${RESET}"
        echo -e "Backup Created:          ${GREEN}$(basename "$backup_file")${RESET}"
        echo
        
        # STANDARDIZED: Next steps guidance
        echo -e "${BOLD}${CYAN}Next Steps:${RESET}"
        if [ "$new_market_count" -gt 0 ]; then
          echo -e "${GREEN}• Your remaining markets are still configured for caching${RESET}"
          echo -e "${GREEN}• Cached stations from this market remain in your database${RESET}"
          echo -e "${GREEN}• Future caching will process only remaining markets${RESET}"
        else
          echo -e "${YELLOW}• No markets remain in configuration${RESET}"
          echo -e "${CYAN}• Add new markets to continue using User Cache Expansion${RESET}"
          echo -e "${CYAN}• Local Database Search still works with existing cached stations${RESET}"
        fi
        echo
        
        return 0
      else
        echo -e "${RED}❌ Market Removal Failed${RESET}"
        echo -e "${CYAN}💡 Market may not have been found or file may be read-only${RESET}"
        echo
        return 1
      fi
    else
      echo -e "${YELLOW}⚠️  Market removal cancelled${RESET}"
      echo -e "${CYAN}💡 Market configuration unchanged${RESET}"
      echo
      return 1
    fi
  else
    echo -e "${RED}❌ Market Not Found: $country/$zip${RESET}"
    echo
    
    # FIXED: Use echo -e instead of printf for colored troubleshooting table
    echo -e "${BOLD}${BLUE}Troubleshooting Analysis:${RESET}"
    echo -e "${BOLD}${YELLOW}Issue Category       Suggestion${RESET}"
    echo "--------------------------------------------"
    echo -e "Market Format:       ${CYAN}Check exact spelling and format${RESET}"
    echo -e "Case Sensitivity:    ${CYAN}Country codes are case-sensitive${RESET}"
    echo -e "ZIP Format:          ${CYAN}Check for spaces or formatting${RESET}"
    echo -e "Market List:         ${CYAN}Verify against table above${RESET}"
    echo
    
    echo -e "${CYAN}💡 This market is not in your current configuration${RESET}"
    echo -e "${CYAN}💡 Check the market list above for exact spelling and format${RESET}"
    echo
    return 1
  fi
}

import_markets() {
  echo -e "\n${BOLD}Import Markets from File${RESET}"
  read -p "Enter filename to import from: " filename
  
  if [[ -z "$filename" ]]; then
    echo -e "${YELLOW}Cancelled${RESET}"
    return 1
  fi
  
  if [ ! -f "$filename" ]; then
    echo -e "${RED}File not found: $filename${RESET}"
    return 1
  fi
  
  if confirm_action "Import markets from $filename? This will add to existing markets"; then
    cat "$filename" >> "$CSV_FILE"
    echo -e "${GREEN}Markets imported from $filename${RESET}"
    return 0
  else
    echo -e "${YELLOW}Import cancelled${RESET}"
    return 1
  fi
}

export_markets() {
  echo -e "\n${BOLD}Export Markets to File${RESET}"
  
  if [ ! -f "$CSV_FILE" ] || [ ! -s "$CSV_FILE" ]; then
    echo -e "${YELLOW}No markets to export${RESET}"
    return 1
  fi
  
  local export_file="data/exports/markets_export_$(date +%Y%m%d_%H%M%S).csv"
  read -p "Export filename [default: $export_file]: " filename
  filename=${filename:-$export_file}
  
  if cp "$CSV_FILE" "$filename"; then
    echo -e "${GREEN}Markets exported to: $filename${RESET}"
    return 0
  else
    echo -e "${RED}Failed to export markets${RESET}"
    return 1
  fi
}

cleanup_existing_postal_codes() {
  echo -e "\n${BOLD}Clean Up Existing Postal Codes${RESET}"
  
  if [ ! -f "$CSV_FILE" ] || [ ! -s "$CSV_FILE" ]; then
    echo -e "${YELLOW}No markets file to clean up${RESET}"
    return 1
  fi
  
  local temp_file="${CSV_FILE}.cleanup"
  local changes_made=0
  
  echo "Checking existing postal codes for normalization..."
  
  # Process the CSV file
  {
    # Keep header
    head -1 "$CSV_FILE"
    
    # Process data lines
    tail -n +2 "$CSV_FILE" | while IFS=, read -r country zip; do
      if [[ "$zip" == *" "* ]]; then
        local normalized_zip=$(echo "$zip" | cut -d' ' -f1 | tr -d ' ' | tr '[:lower:]' '[:upper:]')
        echo "$country,$normalized_zip"
        echo -e "${CYAN}Normalized: $country/$zip → $country/$normalized_zip${RESET}" >&2
        changes_made=1
      else
        # Convert to uppercase for consistency
        local clean_zip=$(echo "$zip" | tr '[:lower:]' '[:upper:]')
        echo "$country,$clean_zip"
        if [[ "$zip" != "$clean_zip" ]]; then
          echo -e "${CYAN}Uppercase: $country/$zip → $country/$clean_zip${RESET}" >&2
          changes_made=1
        fi
      fi
    done
  } > "$temp_file"
  
  if [[ $changes_made -eq 1 ]]; then
    mv "$temp_file" "$CSV_FILE"
    echo -e "${GREEN}Postal codes cleaned up successfully${RESET}"
  else
    rm -f "$temp_file"
    echo -e "${GREEN}All postal codes are already in correct format${RESET}"
  fi
  
  return 0
}

force_refresh_market() {
  echo -e "\n${BOLD}Force Refresh Market${RESET}"
  echo
  
  # Show available markets with their status
  if [ -f "$CSV_FILE" ] && [ -s "$CSV_FILE" ]; then
    echo -e "${BOLD}Configured Markets:${RESET}"
    tail -n +2 "$CSV_FILE" | while IFS=, read -r country zip; do
      local status=""
      if is_market_processed "$country" "$zip"; then
        status="${YELLOW}(exact market in base cache)${RESET}"
      elif is_market_cached "$country" "$zip"; then
        status="${GREEN}(processed in user cache)${RESET}"
      else
        status="${CYAN}(unprocessed)${RESET}"
      fi
      echo -e "   • $country / $zip $status"
    done
    echo
  fi
  
  # Country input with validation
  local country
  while true; do
    read -p "Enter country code to force refresh (3-letter, e.g., USA): " country
    
    if [[ -z "$country" ]]; then
      echo -e "${YELLOW}Operation cancelled${RESET}"
      return 1
    fi
    
    # Normalize to uppercase
    country=$(echo "$country" | tr '[:lower:]' '[:upper:]')
    
    # Validate format (3 letters)
    if [[ ! "$country" =~ ^[A-Z]{3}$ ]]; then
      echo -e "${RED}❌ Invalid format. Country code must be exactly 3 letters (e.g., USA, CAN, GBR)${RESET}"
      continue
    fi
    
    # Validate against known country codes if file exists
    if [[ -f "$VALID_CODES_FILE" ]] && ! grep -Fxq "$country" "$VALID_CODES_FILE" 2>/dev/null; then
      echo -e "${YELLOW}⚠️ '$country' is not a recognized country code, but will proceed anyway${RESET}"
    fi
    
    break
  done

  # ZIP input with validation
  local zip
  while true; do
    read -p "Enter ZIP/postal code to force refresh: " zip
    
    if [[ -z "$zip" ]]; then
      echo -e "${YELLOW}Operation cancelled${RESET}"
      return 1
    fi
    
    # Remove spaces and normalize to uppercase
    zip=$(echo "$zip" | tr -d ' ' | tr '[:lower:]' '[:upper:]')
    
    # Basic validation (alphanumeric, reasonable length)
    if [[ ! "$zip" =~ ^[A-Z0-9]{2,10}$ ]]; then
      echo -e "${RED}❌ Invalid format. ZIP/postal code should be 2-10 alphanumeric characters${RESET}"
      continue
    fi
    
    break
  done
  
  # Check if market exists in CSV
  if ! grep -q "^$country,$zip$" "$CSV_FILE" 2>/dev/null; then
    echo -e "${RED}Market $country/$zip not found in configured markets${RESET}"
    if confirm_action "Add this market to your configuration?"; then
      echo "$country,$zip" >> "$CSV_FILE"
      echo -e "${GREEN}Market added to configuration${RESET}"
    else
      return 1
    fi
  fi
  
  # Show what will happen
  if is_market_processed "$country" "$zip"; then
    echo -e "${CYAN}This exact market is in base cache but will be processed anyway${RESET}"
    echo -e "${CYAN}Any unique stations will be added to your user cache${RESET}"
  else
    echo -e "${CYAN}This market is not in base cache and will be fully processed${RESET}"
  fi
  
  if ! confirm_action "Force refresh market $country/$zip?"; then
    echo -e "${YELLOW}Force refresh cancelled${RESET}"
    return 1
  fi
  
  echo -e "${CYAN}Force refreshing market: $country/$zip${RESET}"
  
  # Remove from state tracking to force refresh
  if [ -f "$CACHED_MARKETS" ]; then
    grep -v "\"country\":\"$country\",\"zip\":\"$zip\"" "$CACHED_MARKETS" > "$CACHED_MARKETS.tmp" 2>/dev/null || true
    mv "$CACHED_MARKETS.tmp" "$CACHED_MARKETS"
  fi
  
  # Create temporary CSV with just this market and set force flag
  local temp_csv="$CACHE_DIR/temp_force_refresh_market.csv"
  {
    echo "Country,ZIP"
    echo "$country,$zip"
  } > "$temp_csv"
  
  # Set force refresh flag and temporarily swap CSV files
  export FORCE_REFRESH_ACTIVE=true
  local original_csv="$CSV_FILE"
  CSV_FILE="$temp_csv"
  
  # Use the consolidated function with force refresh
   perform_user_caching true
  
  # Restore original CSV and clear force flag
  CSV_FILE="$original_csv"
  unset FORCE_REFRESH_ACTIVE
  rm -f "$temp_csv"
  
  echo -e "${GREEN}✅ Market $country/$zip force refreshed${RESET}"
}

manage_markets() {
  while true; do
    show_markets_menu
    
    read -p "Select option: " choice < /dev/tty
    
    case $choice in
      a|A) 
        add_market && pause_for_user 
        ;;
      b|B) 
        remove_market && pause_for_user 
        ;;
      c|C) 
        import_markets && pause_for_user 
        ;;
      d|D) 
        export_markets && pause_for_user 
        ;;
      e|E) 
        cleanup_existing_postal_codes && pause_for_user 
        ;;
      f|F) 
        force_refresh_market && pause_for_user 
        ;;
      r|R)
        # Ready to cache validation and transition
        local market_count
        market_count=$(awk 'END {print NR-1}' "$CSV_FILE" 2>/dev/null || echo "0")
        
        if [[ "$market_count" -gt 0 ]]; then
          clear
          echo -e "${BOLD}${CYAN}=== Ready for User Cache Expansion ===${RESET}\n"
          echo -e "${GREEN}✅ Excellent! You have $market_count markets configured.${RESET}"
          echo
          
          if confirm_action "Proceed to User Cache Expansion?"; then
            show_menu_transition "starting" "User Cache Expansion"
            run_user_caching
          else
            echo -e "${YELLOW}⚠️  Staying in Market Management${RESET}"
            pause_for_user
          fi
        else
          echo -e "\n${RED}❌ No Markets Configured${RESET}"
          echo -e "${CYAN}💡 Please add at least one market before proceeding to caching${RESET}"
          
          if confirm_action "Add your first market now?"; then
            add_market
          fi
          pause_for_user
        fi
        ;;
      q|Q|"") 
        break 
        ;;
      *) 
        show_invalid_menu_choice "Market Management" "$choice"
        ;;
    esac
  done
}

# ============================================================================
# MENU-SPECIFIC LOCAL CACHE FUNCTIONS
# ============================================================================

run_user_caching() {
  local show_pause="${1:-true}"
  clear
  echo -e "${BOLD}${CYAN}=== User Cache Expansion ===${RESET}\n"
  
  echo -e "${BLUE}📊 Step 2 of 3: Build Local Station Database${RESET}"
  echo -e "${YELLOW}This process will:${RESET}"
  echo -e "• Query configured markets for available stations"
  echo -e "• Skip markets already processed or covered by base cache"
  echo -e "• Add only new stations to your user cache (incremental)"
  echo -e "• Enable full-featured local search with filtering"
  echo
  
  if [ ! -f "$CSV_FILE" ] || [ ! -s "$CSV_FILE" ]; then
    echo -e "${RED}❌ No markets configured. Please add markets first.${RESET}"
    echo
    echo -e "${CYAN}Would you like to configure markets now?${RESET}"
    if confirm_action "Go to Market Management"; then
      manage_markets
      return 1
    else
      return 1
    fi
  fi
  
  local market_count
  market_count=$(awk 'END {print NR-1}' "$CSV_FILE")
  echo -e "${GREEN}✅ Markets configured: $market_count${RESET}"
  
  # Show current cache status
  local breakdown=$(get_stations_breakdown)
  local base_count=$(echo "$breakdown" | cut -d' ' -f1)
  local user_count=$(echo "$breakdown" | cut -d' ' -f2)
  local total_count=$(get_total_stations_count)
  
  echo
  echo -e "${BOLD}Current Cache Status:${RESET}"
  if [ "$base_count" -gt 0 ]; then
    echo -e "${GREEN}✅ Base stations: $base_count${RESET}"
  else
    echo -e "${YELLOW}⚠️  Base stations: 0 (no distributed cache)${RESET}"
  fi
  
  if [ "$user_count" -gt 0 ]; then
    echo -e "${GREEN}✅ User stations: $user_count${RESET}"
    echo -e "${CYAN}   New stations will be added to your existing collection${RESET}"
  else
    echo -e "${YELLOW}⚠️  User stations: 0 (this will be your first user cache)${RESET}"
  fi
  
  echo -e "${CYAN}📊 Total currently available: $total_count${RESET}"
  
  # Show what will be processed
  echo -e "\n${BOLD}Processing Strategy:${RESET}"
  echo -e "${CYAN}✅ Smart Processing: Only unprocessed markets will be cached${RESET}"
  echo -e "${CYAN}✅ Base Cache Aware: Markets in base cache will be skipped${RESET}"
  echo -e "${CYAN}✅ Incremental: New stations append to existing cache${RESET}"
  echo -e "${CYAN}✅ State Tracking: Progress is saved and resumable${RESET}"
  echo
  
  echo -e "${CYAN}💡 Processing time varies based on how many new markets need caching${RESET}"
  echo
  
  if ! confirm_action "Continue with smart incremental caching?"; then
    echo -e "${YELLOW}User caching cancelled${RESET}"
    return 1
  fi
  
   perform_user_caching false

  if [[ "$show_pause" == "true" ]]; then
  echo
  echo -e "${CYAN}💡 User caching process completed - press any key to continue...${RESET}"
  pause_for_user
fi
}

run_incremental_update() {
  echo -e "\n${BOLD}Incremental Cache Update${RESET}"
  echo -e "${CYAN}This will process only markets that haven't been cached yet.${RESET}"
  echo -e "${YELLOW}Markets with exact matches in base cache will be automatically skipped.${RESET}"
  echo
  
  if ! confirm_action "Run incremental cache update?"; then
    echo -e "${YELLOW}Incremental update cancelled${RESET}"
    return 1
  fi
  
  # The new function handles all the incremental logic
   perform_user_caching false
}

run_full_user_refresh() {
  echo -e "\n${BOLD}Full User Cache Refresh${RESET}"
  echo -e "${YELLOW}This will reprocess ALL configured markets and rebuild your user cache.${RESET}"
  echo -e "${RED}Your existing user cache will be backed up and replaced.${RESET}"
  echo
  
  local user_count=$(echo "$(get_stations_breakdown)" | cut -d' ' -f2)
  if [ "$user_count" -gt 0 ]; then
    echo -e "${YELLOW}Current user cache: $user_count stations${RESET}"
    echo -e "${CYAN}This will be backed up before refresh${RESET}"
    echo
  fi
  
  if confirm_action "Perform full user cache refresh?"; then
    # Clear state tracking to force full refresh
    echo -e "${CYAN}Clearing cache state to force full refresh...${RESET}"
    > "$CACHED_MARKETS"
    > "$CACHED_LINEUPS"
    echo '{}' > "$LINEUP_TO_MARKET"
    
    # Backup current user cache
    if [ -f "$USER_STATIONS_JSON" ] && [ -s "$USER_STATIONS_JSON" ]; then
      backup_existing_data
    fi
    
    # Clear user cache
    echo '[]' > "$USER_STATIONS_JSON"
    
    echo -e "${CYAN}Starting full refresh...${RESET}"
    # Use force refresh mode to reprocess everything
     perform_user_caching true
    
    echo -e "${GREEN}✅ Full user cache refresh complete${RESET}"
  else
    echo -e "${YELLOW}Full refresh cancelled${RESET}"
  fi
}

clear_all_cache() {
  if confirm_action "Clear ALL cache data? This will require re-downloading everything"; then
    cleanup_cache
    echo -e "${GREEN}All cache cleared${RESET}"
    return 0
  else
    echo -e "${YELLOW}Operation cancelled${RESET}"
    return 1
  fi
}

clear_station_cache() {
  if confirm_action "Clear station cache?"; then
    # Remove station cache files and any legacy master JSON files
    rm -f "$STATION_CACHE_DIR"/*.json 2>/dev/null || true
    rm -f "$CACHE_DIR"/all_stations_master.json* 2>/dev/null || true
    rm -f "$CACHE_DIR"/working_stations.json* 2>/dev/null || true
    rm -f "$CACHE_DIR"/temp_stations_*.json 2>/dev/null || true
    echo -e "${GREEN}Station cache cleared${RESET}"
    return 0
  else
    echo -e "${YELLOW}Operation cancelled${RESET}"
    return 1
  fi
}

clear_temp_files() {
  if confirm_action "Clear temporary files?"; then
    rm -f "$CACHE_DIR"/*.tmp "$CACHE_DIR"/last_raw_*.json
    echo -e "${GREEN}Temporary files cleared${RESET}"
    return 0
  else
    echo -e "${YELLOW}Operation cancelled${RESET}"
    return 1
  fi
}

clear_logo_cache() {
  if confirm_action "Clear logo cache?"; then
    rm -f "$LOGO_DIR"/*.png 2>/dev/null || true
    echo -e "${GREEN}Logo cache cleared${RESET}"
    return 0
  else
    echo -e "${YELLOW}Operation cancelled${RESET}"
    return 1
  fi
}

clear_user_cache() {
  echo -e "\n${BOLD}Clear User Cache${RESET}"
  
  local user_count=$(echo "$(get_stations_breakdown)" | cut -d' ' -f2)
  if [ "$user_count" -eq 0 ]; then
    echo -e "${YELLOW}User cache is already empty${RESET}"
    return 0
  fi
  
  echo -e "${YELLOW}This will remove $user_count stations from your user cache.${RESET}"
  echo -e "${GREEN}Base cache and state tracking will be preserved.${RESET}"
  echo -e "${CYAN}You can rebuild the user cache anytime using 'Run User Caching'.${RESET}"
  echo
  
  if confirm_action "Clear user cache ($user_count stations)?"; then
    # Backup before clearing
    backup_existing_data
    
    # Clear user cache
    echo '[]' > "$USER_STATIONS_JSON"
    
    # Clear state tracking
    > "$CACHED_MARKETS"
    > "$CACHED_LINEUPS"
    echo '{}' > "$LINEUP_TO_MARKET"
    
    echo -e "${GREEN}✅ User cache cleared${RESET}"
    echo -e "${CYAN}💡 State tracking reset - next caching will process all markets${RESET}"
  else
    echo -e "${YELLOW}Clear operation cancelled${RESET}"
  fi
}

refresh_specific_market() {
  echo -e "\n${BOLD}Refresh Specific Market${RESET}"
  echo -e "${CYAN}This will re-process a single market (country/ZIP combination).${RESET}"
  echo
  
  # Show available markets
  if [ -f "$CSV_FILE" ] && [ -s "$CSV_FILE" ]; then
    echo -e "${BOLD}Configured Markets:${RESET}"
    tail -n +2 "$CSV_FILE" | while IFS=, read -r country zip; do
      if is_market_processed "$country" "$zip"; then
        echo -e "   • $country / $zip ${YELLOW}(exact market in base cache)${RESET}"
      else
        echo -e "   • $country / $zip ${GREEN}(will be processed normally)${RESET}"
      fi
    done
    echo
  fi
  
  read -p "Enter country code (e.g., USA): " country
  read -p "Enter ZIP code (e.g., 10001): " zip
  
  if [[ -z "$country" || -z "$zip" ]]; then
    echo -e "${YELLOW}Operation cancelled${RESET}"
    return 1
  fi
  
  # Check if market exists in CSV
  if ! grep -q "^$country,$zip$" "$CSV_FILE" 2>/dev/null; then
    echo -e "${RED}Market $country/$zip not found in configured markets${RESET}"
    if confirm_action "Add this market to your configuration?"; then
      echo "$country,$zip" >> "$CSV_FILE"
      echo -e "${GREEN}Market added to configuration${RESET}"
    else
      return 1
    fi
  fi
  
  # Check if exact market is in base cache and inform user
  if is_market_processed "$country" "$zip"; then
    echo -e "${YELLOW}⚠️  Exact market $country/$zip is in base cache${RESET}"
    echo -e "${CYAN}This refresh will process it anyway and add any unique stations${RESET}"
    if ! confirm_action "Continue with refresh anyway?"; then
      echo -e "${YELLOW}Refresh cancelled${RESET}"
      return 1
    fi
    # Set force refresh flag to bypass base cache checking
    export FORCE_REFRESH_ACTIVE=true
  fi
  
  echo -e "${CYAN}Refreshing market: $country/$zip${RESET}"
  
  # Remove from state tracking to force refresh
  if [ -f "$CACHED_MARKETS" ]; then
    grep -v "\"country\":\"$country\",\"zip\":\"$zip\"" "$CACHED_MARKETS" > "$CACHED_MARKETS.tmp" 2>/dev/null || true
    mv "$CACHED_MARKETS.tmp" "$CACHED_MARKETS"
  fi
  
  # Create temporary CSV with just this market
  local temp_csv="$CACHE_DIR/temp_single_market.csv"
  {
    echo "Country,ZIP"
    echo "$country,$zip"
  } > "$temp_csv"
  
  # Temporarily swap CSV files
  local original_csv="$CSV_FILE"
  CSV_FILE="$temp_csv"
  
   perform_user_caching false
  
  # Restore original CSV and clear force flag
  CSV_FILE="$original_csv"
  unset FORCE_REFRESH_ACTIVE
  rm -f "$temp_csv"
  
  echo -e "${GREEN}✅ Market $country/$zip refreshed${RESET}"
}

reset_state_tracking() {
  echo -e "\n${BOLD}Reset State Tracking${RESET}"
  echo -e "${YELLOW}This will clear all state tracking data.${RESET}"
  echo -e "${CYAN}Next caching operation will process all markets as if first time.${RESET}"
  echo -e "${GREEN}User cache and base cache will not be affected.${RESET}"
  echo
  
  if confirm_action "Reset all state tracking?"; then
    > "$CACHED_MARKETS"
    > "$CACHED_LINEUPS"
    echo '{}' > "$LINEUP_TO_MARKET"
    > "$CACHE_STATE_LOG"
    
    echo -e "${GREEN}✅ State tracking reset${RESET}"
    echo -e "${CYAN}💡 Next caching will process all configured markets${RESET}"
  else
    echo -e "${YELLOW}Reset cancelled${RESET}"
  fi
}

show_incremental_caching_summary() {
  local processed_markets="$1"
  local already_cached="$2"
  local base_cache_skipped="$3"
  local new_stations="$4"
  local dup_stations_removed="$5"
  local human_duration="$6"
  local enhanced_from_api="${7:-0}"
  local lineups_skipped_base="${8:-0}"    # NEW
  local lineups_skipped_user="${9:-0}"    # NEW
  
  # Get final counts
  local breakdown=$(get_stations_breakdown)
  local base_count=$(echo "$breakdown" | cut -d' ' -f1)
  local user_count=$(echo "$breakdown" | cut -d' ' -f2)
  local total_count=$(get_total_stations_count)

  echo
  echo -e "${BOLD}${GREEN}=== Incremental Caching Summary ===${RESET}"
  echo "Markets Processed:          $processed_markets"
  echo "Markets Already Cached:     $already_cached"
  echo "Markets Skipped (Base):     $base_cache_skipped"
  echo "Lineups Skipped (Base):     $lineups_skipped_base"     # NEW
  echo "Lineups Skipped (User):     $lineups_skipped_user"     # NEW
  echo "New Stations Added:         $new_stations"
  echo "Duplicate Stations Removed: $dup_stations_removed"
  
  # Show efficiency gains
  local total_skipped=$((lineups_skipped_base + lineups_skipped_user))
  if [ "$total_skipped" -gt 0 ]; then
    echo "API Calls Saved:            $total_skipped (efficiency gain)"
  fi
  
  # Rest of existing summary...
}

show_user_caching_summary() {
  local dup_lineups_removed="$1"
  local dup_stations_removed="$2"
  local human_duration="$3"
  local enhanced_from_api="${4:-0}"
  
  local num_countries=$(awk -F, 'NR>1 {print $1}' "$CSV_FILE" | sort -u | awk 'END {print NR}')
  local num_markets=$(awk 'END {print NR-1}' "$CSV_FILE")
  local num_lineups=$(awk 'END {print NR}' cache/unique_lineups.txt 2>/dev/null || echo "0")
  
  # Get final counts
  local breakdown=$(get_stations_breakdown)
  local base_count=$(echo "$breakdown" | cut -d' ' -f1)
  local user_count=$(echo "$breakdown" | cut -d' ' -f2)
  local total_count=$(get_total_stations_count)

  echo
  echo -e "${BOLD}${GREEN}=== User Caching Summary ===${RESET}"
  echo "Total Countries:            $num_countries"
  echo "Total Markets:              $num_markets"
  echo "Total Lineups:              $num_lineups"
  echo "Duplicate Lineups Removed:  $dup_lineups_removed"
  echo "Duplicate Stations Removed: $dup_stations_removed"
  
  # Only show API enhancement statistics (no cache enhancement)
  if [[ $enhanced_from_api -gt 0 ]]; then
    echo "Stations Enhanced via API:  $enhanced_from_api"
  fi
  
  echo "Time to Complete:           $human_duration"
  echo
  echo -e "${BOLD}${CYAN}=== Final Database Status ===${RESET}"
  if [ "$base_count" -gt 0 ]; then
    echo "Base Stations:              $base_count"
  fi
  echo "User Stations:              $user_count"
  echo "Total Available:            $total_count"
  echo
  echo -e "${GREEN}✅ User caching completed successfully!${RESET}"
  echo -e "${CYAN}💡 Your stations are now available for local search${RESET}"
}

refresh_specific_lineup() {
  echo -e "\n${BOLD}Refresh Specific Lineup${RESET}"
  echo -e "${YELLOW}This feature will be implemented in a future update.${RESET}"
  echo -e "${CYAN}For now, use 'Refresh Specific Market' instead.${RESET}"
}

rebuild_base_from_user() {
  echo -e "\n${BOLD}Rebuild Base Cache from User Cache${RESET}"
  echo -e "${YELLOW}This feature is reserved for script distribution management.${RESET}"
  echo -e "${CYAN}Contact the script maintainer if you need this functionality.${RESET}"
}

view_raw_cache_files() {
  echo -e "\n${BOLD}Raw Cache Files${RESET}"
  echo -e "${CYAN}Cache directory: $CACHE_DIR${RESET}"
  echo
  
  if [ -f "$BASE_STATIONS_JSON" ]; then
    echo "Base cache: $(ls -lh "$BASE_STATIONS_JSON" | awk '{print $5}') (script directory)"
  else
    echo "Base cache: Not found (should be $(basename "$BASE_STATIONS_JSON") in script directory)"
  fi
  
  if [ -f "$USER_STATIONS_JSON" ]; then
    echo "User cache: $(ls -lh "$USER_STATIONS_JSON" | awk '{print $5}')"
  fi
  
  if [ -f "$CACHED_MARKETS" ]; then
    echo "Market tracking: $(wc -l < "$CACHED_MARKETS") entries"
  fi
  
  if [ -f "$CACHED_LINEUPS" ]; then
    echo "Lineup tracking: $(wc -l < "$CACHED_LINEUPS") entries"
  fi
  
  echo
  echo -e "${CYAN}💡 Advanced users can inspect these files with: jq . filename${RESET}"
}

validate_cache_integrity() {
  echo -e "\n${BOLD}Cache Integrity Validation${RESET}"
  echo "Checking cache file integrity..."
  
  local errors=0
  
  # Check JSON validity
  for file in "$BASE_STATIONS_JSON" "$USER_STATIONS_JSON" "$LINEUP_TO_MARKET"; do
    if [ -f "$file" ]; then
      if ! jq empty "$file" 2>/dev/null; then
        echo -e "${RED}❌ Invalid JSON: $file${RESET}"
        ((errors++))
      else
        echo -e "${GREEN}✅ Valid JSON: $(basename "$file")${RESET}"
      fi
    fi
  done
  
  # Check for duplicate station IDs within files
  if [ -f "$USER_STATIONS_JSON" ]; then
    local duplicates=$(jq -r '.[] | .stationId' "$USER_STATIONS_JSON" | sort | uniq -d | wc -l)
    if [ "$duplicates" -gt 0 ]; then
      echo -e "${YELLOW}⚠️  Found $duplicates duplicate station IDs in user cache${RESET}"
    else
      echo -e "${GREEN}✅ No duplicate station IDs in user cache${RESET}"
    fi
  fi
  
  if [ "$errors" -eq 0 ]; then
    echo -e "\n${GREEN}✅ Cache integrity check passed${RESET}"
  else
    echo -e "\n${RED}❌ Found $errors integrity issues${RESET}"
  fi
}

advanced_cache_operations() {
  while true; do
    # Define advanced cache menu options
    local advanced_options=(
      "1|Refresh Specific Market (ZIP code)"
      "2|Refresh Specific Lineup"
      "3|Reset State Tracking"
      "4|Force Rebuild Combined Cache"          # NEW OPTION
      "5|Rebuild Base Cache from User Cache"
      "6|View Raw Cache Files"
      "7|Validate Cache Integrity"
      "q|Back to Cache Management"
    )
    
    # Use standardized menu display
    show_menu_header "Advanced Cache Operations"
    show_menu_options "${advanced_options[@]}"
    echo
    
    read -p "Select option: " choice
    
    case $choice in
      1) refresh_specific_market && pause_for_user ;;
      2) refresh_specific_lineup && pause_for_user ;;
      3) reset_state_tracking && pause_for_user ;;
      4) force_rebuild_combined_cache && pause_for_user ;;  # NEW CASE
      5) rebuild_base_from_user && pause_for_user ;;
      6) view_raw_cache_files && pause_for_user ;;
      7) validate_cache_integrity && pause_for_user ;;
      q|Q|"") break ;;
      *) show_invalid_menu_choice "Advanced Cache Operations" "$choice" ;;
    esac
  done
}

cache_management_main_menu() {
  while true; do
    show_cache_management_menu
    
    read -p "Select option: " choice
    
    case "$choice" in
      a|A) 
        show_menu_transition "starting" "incremental cache update"
        run_incremental_update && pause_for_user 
        ;;
      b|B) 
        show_menu_transition "starting" "full user cache refresh"
        run_full_user_refresh && pause_for_user 
        ;;
      c|C) 
        show_menu_transition "loading" "detailed cache statistics"
        show_unified_cache_stats "detailed" && pause_for_user 
        ;;
      d|D) 
        show_menu_transition "starting" "database export"
        export_stations_to_csv && pause_for_user 
        ;;
      e|E) 
        show_menu_transition "opening" "user cache management"
        clear_user_cache && pause_for_user 
        ;;
      f|F) 
        show_menu_transition "starting" "temporary file cleanup"
        clear_temp_files && pause_for_user 
        ;;
      g|G) 
        show_menu_transition "opening" "advanced cache operations"
        advanced_cache_operations 
        ;;
      h|H) 
        show_menu_transition "starting" "Dispatcharr logo cache cleanup"
        cleanup_dispatcharr_logo_cache && echo -e "${GREEN}✅ Dispatcharr logo cache cleaned successfully${RESET}" && pause_for_user 
        ;;
      q|Q|"") 
        show_menu_transition "returning" "main menu"
        break 
        ;;
      *) 
        show_invalid_menu_choice "Cache Management" "$choice"
        ;;
    esac
  done
}

# ============================================================================
# SETTINGS MANAGEMENT FUNCTIONS
# ============================================================================

change_server_settings() {
    clear
    echo -e "${BOLD}${CYAN}=== Channels DVR Server Configuration ===${RESET}\n"
    
    show_setting_status "CHANNELS_URL" "$CHANNELS_URL" "Channels DVR Server" "configured"
    echo
    
    if configure_setting "network" "CHANNELS_URL" "$CHANNELS_URL"; then
        save_setting "CHANNELS_URL" "$CHANNELS_URL"
        # Reload config to get the updated CHANNELS_URL
        source "$CONFIG_FILE" 2>/dev/null
    fi
    
    echo -e "\n${GREEN}✅ Server settings updated${RESET}"
}

toggle_logo_display() {
    clear
    echo -e "${BOLD}${CYAN}=== Logo Display Configuration ===${RESET}\n"
    
    # Check viu dependency
    if ! command -v viu &> /dev/null; then
        echo -e "${RED}❌ Logo display requires 'viu' terminal image viewer${RESET}"
        echo -e "${CYAN}💡 Install with: cargo install viu${RESET}"
        pause_for_user
        return 1
    fi
    
    show_setting_status "SHOW_LOGOS" "$SHOW_LOGOS" "Logo Display" \
        "$([ "$SHOW_LOGOS" = "true" ] && echo "enabled" || echo "disabled")"
    echo
    
    if configure_setting "boolean" "Logo Display" "$SHOW_LOGOS"; then
        # UPDATE THE ACTUAL VARIABLE
        SHOW_LOGOS=true
    else
        # UPDATE THE ACTUAL VARIABLE  
        SHOW_LOGOS=false
    fi
    
    save_setting "SHOW_LOGOS" "$SHOW_LOGOS"
    
    echo -e "\n${GREEN}✅ Logo display configuration saved${RESET}"
}

configure_resolution_filter() {
    clear
    echo -e "${BOLD}${CYAN}=== Resolution Filter Configuration ===${RESET}\n"
    
    show_setting_status "FILTER_BY_RESOLUTION" "$FILTER_BY_RESOLUTION" "Resolution Filtering" \
        "$([ "$FILTER_BY_RESOLUTION" = "true" ] && echo "enabled" || echo "disabled")"
    echo
    
    echo -e "${BOLD}${BLUE}Video Quality Levels:${RESET}"
    echo -e "${GREEN}SDTV${RESET} - Standard Definition (480i/480p)"
    echo -e "${GREEN}HDTV${RESET} - High Definition (720p/1080i/1080p)" 
    echo -e "${GREEN}UHDTV${RESET} - Ultra High Definition (4K/2160p)"
    echo
    
    # Show current selection if filter is enabled
    if [ "$FILTER_BY_RESOLUTION" = "true" ] && [ -n "$ENABLED_RESOLUTIONS" ]; then
        echo -e "${CYAN}💡 Currently showing only: ${YELLOW}$ENABLED_RESOLUTIONS${RESET} quality stations"
        echo
    fi
    
    echo -e "${BOLD}${BLUE}Resolution Filter Options:${RESET}"
    echo -e "${GREEN}1)${RESET} Turn Off Resolution Filter ${CYAN}(show all quality levels)${RESET}"
    echo -e "${GREEN}2)${RESET} Turn On Resolution Filter ${CYAN}(select specific quality levels)${RESET}"
    echo
    
    local choice
    while true; do
        read -p "Select option (1-2): " choice
        
        case "$choice" in
            1)
                # Turn OFF resolution filter
                echo -e "\n${CYAN}🔄 Turning off resolution filter...${RESET}"
                FILTER_BY_RESOLUTION=false
                ENABLED_RESOLUTIONS="SDTV,HDTV,UHDTV"  # Reset to default (all)
                
                # Save settings
                save_setting "FILTER_BY_RESOLUTION" "$FILTER_BY_RESOLUTION"
                save_setting "ENABLED_RESOLUTIONS" "$ENABLED_RESOLUTIONS"
                
                echo -e "${GREEN}✅ Resolution filter disabled${RESET}"
                echo -e "${CYAN}💡 Search results will now show stations of all quality levels${RESET}"
                break
                ;;
            2)
                # Turn ON resolution filter and proceed to selection
                echo -e "\n${CYAN}🔄 Enabling resolution filter...${RESET}"
                FILTER_BY_RESOLUTION=true
                
                echo -e "${CYAN}Select which resolution levels to show in search results:${RESET}"
                echo
                
                # Call multi_choice configuration with explicit resolution options
                configure_setting "multi_choice" "Resolution Levels" "$ENABLED_RESOLUTIONS" "SDTV" "HDTV" "UHDTV"
                
                # Verify selection was made
                if [ -z "$ENABLED_RESOLUTIONS" ]; then
                    echo -e "${RED}❌ No resolutions selected - disabling resolution filter${RESET}"
                    FILTER_BY_RESOLUTION=false
                    ENABLED_RESOLUTIONS="SDTV,HDTV,UHDTV"
                else
                    echo -e "${GREEN}✅ Resolution filter enabled: $ENABLED_RESOLUTIONS${RESET}"
                fi
                
                # Save settings
                save_setting "FILTER_BY_RESOLUTION" "$FILTER_BY_RESOLUTION"
                save_setting "ENABLED_RESOLUTIONS" "$ENABLED_RESOLUTIONS"
                break
                ;;
            "")
                echo -e "${YELLOW}⚠️  Configuration cancelled${RESET}"
                return 1
                ;;
            *)
                echo -e "${RED}❌ Invalid option. Please enter 1 or 2${RESET}"
                ;;
        esac
    done
    
    echo
    echo -e "${BOLD}${GREEN}=== Configuration Complete ===${RESET}"
    echo -e "Resolution Filtering: $([ "$FILTER_BY_RESOLUTION" = "true" ] && echo "${GREEN}Enabled${RESET}" || echo "${YELLOW}Disabled${RESET}")"
    if [ "$FILTER_BY_RESOLUTION" = "true" ] && [ -n "$ENABLED_RESOLUTIONS" ]; then
        echo -e "Selected Resolutions: ${GREEN}$ENABLED_RESOLUTIONS${RESET}"
        echo -e "${CYAN}💡 Search results will be filtered to show only: $ENABLED_RESOLUTIONS quality stations${RESET}"
    else
        echo -e "${CYAN}💡 Search results will show stations of all quality levels${RESET}"
    fi
}

configure_country_filter() {
    clear
    echo -e "${BOLD}${CYAN}=== Country Filter Configuration ===${RESET}\n"
    
    show_setting_status "FILTER_BY_COUNTRY" "$FILTER_BY_COUNTRY" "Country Filtering" \
        "$([ "$FILTER_BY_COUNTRY" = "true" ] && echo "enabled" || echo "disabled")"
    echo
    
    # Show current selection if filter is enabled
    if [ "$FILTER_BY_COUNTRY" = "true" ] && [ -n "$ENABLED_COUNTRIES" ]; then
        echo -e "${CYAN}💡 Currently showing only: ${YELLOW}$ENABLED_COUNTRIES${RESET} stations"
        echo
    fi
    
    echo -e "${BOLD}${BLUE}Country Filter Options:${RESET}"
    echo -e "${GREEN}1)${RESET} Turn Off Country Filter ${CYAN}(show stations from all countries)${RESET}"
    echo -e "${GREEN}2)${RESET} Turn On Country Filter ${CYAN}(select specific countries)${RESET}"
    echo
    
    local choice
    while true; do
        read -p "Select option (1-2): " choice
        
        case "$choice" in
            1)
                # Turn OFF country filter
                echo -e "\n${CYAN}🔄 Turning off country filter...${RESET}"
                FILTER_BY_COUNTRY=false
                ENABLED_COUNTRIES=""  # Clear country selection
                
                # Save settings
                save_setting "FILTER_BY_COUNTRY" "$FILTER_BY_COUNTRY"
                save_setting "ENABLED_COUNTRIES" "$ENABLED_COUNTRIES"
                
                echo -e "${GREEN}✅ Country filter disabled${RESET}"
                echo -e "${CYAN}💡 Search results will now show stations from all available countries${RESET}"
                break
                ;;
            2)
                # Turn ON country filter and proceed to selection
                echo -e "\n${CYAN}🔄 Enabling country filter...${RESET}"
                echo -e "${CYAN}🔍 Detecting countries from station database...${RESET}"
                
                # Get available countries from station database
                local available_countries
                available_countries=$(get_available_countries)
                
                if [ -z "$available_countries" ]; then
                    echo -e "${RED}❌ No countries found in station database${RESET}"
                    echo
                    
                    # Show helpful diagnostics
                    local breakdown=$(get_stations_breakdown)
                    local base_count=$(echo "$breakdown" | cut -d' ' -f1)
                    local user_count=$(echo "$breakdown" | cut -d' ' -f2)
                    local total_count=$((base_count + user_count))
                    
                    echo -e "${BOLD}${BLUE}Database Status:${RESET}"
                    echo -e "  Total stations: $total_count"
                    echo -e "  Base stations: $base_count"
                    echo -e "  User stations: $user_count"
                    echo
                    
                    if [ "$total_count" -eq 0 ]; then
                        echo -e "${CYAN}💡 No station database found. Build it first:${RESET}"
                        echo -e "${CYAN}   1. Use 'Manage Television Markets' to configure markets${RESET}"
                        echo -e "${CYAN}   2. Use 'Run User Caching' to build station database${RESET}"
                    else
                        echo -e "${CYAN}💡 Station database exists but no country data found${RESET}"
                        echo -e "${CYAN}   This may indicate a data quality issue${RESET}"
                    fi
                    echo
                    echo -e "${YELLOW}⚠️  Country filter cannot be enabled without country data${RESET}"
                    pause_for_user
                    return 1
                fi
                
                echo -e "${GREEN}✅ Found countries: ${YELLOW}$available_countries${RESET}"
                echo
                
                FILTER_BY_COUNTRY=true
                
                echo -e "${CYAN}Select which countries to show in search results:${RESET}"
                echo
                
                # Convert comma-separated to array for multi-choice
                IFS=',' read -ra COUNTRIES_ARRAY <<< "$available_countries"
                
                # Call the multi-choice setting configuration
                configure_setting "multi_choice" "Countries" "$ENABLED_COUNTRIES" "${COUNTRIES_ARRAY[@]}"
                
                # Verify selection was made
                if [ -z "$ENABLED_COUNTRIES" ]; then
                    echo -e "${RED}❌ No countries selected - disabling country filter${RESET}"
                    FILTER_BY_COUNTRY=false
                    ENABLED_COUNTRIES=""
                else
                    echo -e "${GREEN}✅ Country filter enabled: $ENABLED_COUNTRIES${RESET}"
                fi
                
                # Save settings
                save_setting "FILTER_BY_COUNTRY" "$FILTER_BY_COUNTRY"
                save_setting "ENABLED_COUNTRIES" "$ENABLED_COUNTRIES"
                break
                ;;
            "")
                echo -e "${YELLOW}⚠️  Configuration cancelled${RESET}"
                return 1
                ;;
            *)
                echo -e "${RED}❌ Invalid option. Please enter 1 or 2${RESET}"
                ;;
        esac
    done
    
    echo
    echo -e "${BOLD}${GREEN}=== Configuration Complete ===${RESET}"
    echo -e "Country Filtering: $([ "$FILTER_BY_COUNTRY" = "true" ] && echo "${GREEN}Enabled${RESET}" || echo "${YELLOW}Disabled${RESET}")"
    if [ "$FILTER_BY_COUNTRY" = "true" ] && [ -n "$ENABLED_COUNTRIES" ]; then
        echo -e "Selected Countries: ${GREEN}$ENABLED_COUNTRIES${RESET}"
        echo -e "${CYAN}💡 Search results will be filtered to show only: $ENABLED_COUNTRIES stations${RESET}"
    else
        echo -e "${CYAN}💡 Search results will show stations from all available countries${RESET}"
    fi
}

reset_all_settings() {
  echo -e "${RED}This will reset ALL settings to defaults and clear configuration${RESET}"
  if confirm_action "Are you sure?"; then
    rm -f "$CONFIG_FILE"
    SHOW_LOGOS=false
    FILTER_BY_RESOLUTION=false
    ENABLED_RESOLUTIONS="SDTV,HDTV,UHDTV"
    FILTER_BY_COUNTRY=false
    ENABLED_COUNTRIES=""
    echo -e "${GREEN}Settings reset. Restart the script to reconfigure.${RESET}"
    return 0
  else
    echo -e "${YELLOW}Reset cancelled${RESET}"
    return 1
  fi
}

export_settings() {
  local settings_file="globalstationsearch_settings_$(date +%Y%m%d_%H%M%S).txt"
  
  {
    echo "Global Station Search Settings Export"
    echo "Generated: $(date)"
    echo "Script Version: $VERSION"
    echo "Last Modified: 2025/06/01"
    echo
    echo "=== Configuration ==="
    echo "Server: $CHANNELS_URL"
    echo "Logo Display: $SHOW_LOGOS"
    echo "Resolution Filter: $FILTER_BY_RESOLUTION"
    echo "Enabled Resolutions: $ENABLED_RESOLUTIONS"
    echo "Country Filter: $FILTER_BY_COUNTRY"
    echo "Enabled Countries: $ENABLED_COUNTRIES"
    echo "Dispatcharr Enabled: $DISPATCHARR_ENABLED"
    echo "Dispatcharr URL: $DISPATCHARR_URL"
    echo
    echo "=== Markets ==="
    [ -f "$CSV_FILE" ] && cat "$CSV_FILE"
  } > "$settings_file"
  
  echo -e "${GREEN}Settings exported to: $settings_file${RESET}"
  return 0
}

export_stations_to_csv() {
  echo -e "\n${BOLD}Export Station Database to CSV${RESET}"
  
  # Get effective stations file
  local stations_file
  stations_file=$(get_effective_stations_file)
  if [ $? -ne 0 ]; then
    echo -e "${RED}No station database found.${RESET}"
    echo -e "${CYAN}Expected: Base cache file ($(basename "$BASE_STATIONS_JSON")) in script directory${RESET}"
    echo -e "${CYAN}Alternative: Build user cache via 'Manage Television Markets' → 'Run User Caching'${RESET}"
    return 1
  fi
  
  local total_count=$(get_total_stations_count)
  echo "Station database contains: $total_count stations"
  
  # Show source breakdown
  local breakdown=$(get_stations_breakdown)
  local base_count=$(echo "$breakdown" | cut -d' ' -f1)
  local user_count=$(echo "$breakdown" | cut -d' ' -f2)

  # Show source breakdown
  if [ "$base_count" -gt 0 ]; then
    echo "  Base stations: $base_count"
  fi
  if [ "$user_count" -gt 0 ]; then
    echo "  User stations: $user_count"
  fi
  
  # Generate filename with timestamp
  local csv_file="data/exports/stations_export_$(date +%Y%m%d_%H%M%S).csv"
  read -p "Export filename [default: $csv_file]: " filename
  filename=${filename:-$csv_file}
  
  echo "Exporting combined station database to CSV..."
  
  # Create CSV with comprehensive station data
  {
    # CSV Header (added Source column)
    echo "Station_ID,Name,Call_Sign,Country,Video_Quality,Network,Genre,Language,Logo_URL,Description,Source"
    
    # Export station data with source indication
    jq -r '
      .[] | [
        .stationId // "",
        .name // "",
        .callSign // "",
        .country // "",
        .videoQuality.videoType // "",
        .network // "",
        (.genre // [] | join("; ")),
        .language // "",
        .preferredImage.uri // "",
        .description // "",
        (.source // "Combined")
      ] | @csv
    ' "$stations_file"
  } > "$filename"
  
  if [ $? -eq 0 ]; then
    local exported_count=$(tail -n +2 "$filename" | wc -l)
    echo -e "${GREEN}✅ Successfully exported $exported_count stations to: $filename${RESET}"
    
    # Show file info
    local file_size
    file_size=$(ls -lh "$filename" 2>/dev/null | awk '{print $5}')
    echo -e "${CYAN}📄 File size: $file_size${RESET}"
    
    # Show sample of exported data
    echo -e "\n${BOLD}Sample of exported data:${RESET}"
    head -3 "$filename" | while IFS= read -r line; do
      echo "  $line"
    done | cut -c1-100  # Truncate long lines
    
    echo -e "\n${CYAN}💡 This CSV includes stations from all available cache sources${RESET}"
    echo -e "${CYAN}💡 Can be opened in Excel, LibreOffice, or imported into databases${RESET}"
  else
    echo -e "${RED}❌ Failed to export stations to CSV${RESET}"
    return 1
  fi
  
  # Clean up any temporary combined files
  cleanup_combined_cache
  
  return 0
}

settings_menu() {
while true; do
    maintain_session_tokens
    
    show_settings_menu
    
    read -p "Select option: " choice
    
    case $choice in
        a|A) change_server_settings && pause_for_user ;;
        b|B) toggle_logo_display && pause_for_user ;;
        c|C) configure_resolution_filter && pause_for_user ;;
        d|D) configure_country_filter && pause_for_user ;;
        e|E) show_unified_cache_stats "detailed" && pause_for_user ;;
        f|F) reset_all_settings && pause_for_user ;;
        g|G) export_settings && pause_for_user ;;
        h|H) export_stations_to_csv && pause_for_user ;;
        i|I) configure_dispatcharr_connection && pause_for_user ;;
        j|J) 
          show_menu_transition "configuring" "Emby integration"
          configure_emby_connection && pause_for_user 
          ;;
        k|K) developer_information && pause_for_user ;;
        l|L) show_update_management_menu ;;
        m|M) show_backup_management_menu ;;
        q|Q|"") break ;; 
      *) show_invalid_menu_choice "Settings" "$choice" ;;
    esac
  done
}

# ============================================================================
# DEVELOPER INFORMATION FUNCTIONS
# ============================================================================

show_cache_state_details() {
  echo -e "\n${BOLD}${BLUE}=== Cache State Tracking Details ===${RESET}"
  echo -e "${CYAN}Technical details about cache state management:${RESET}"
  echo
  
  echo -e "${BOLD}State Files Purpose:${RESET}"
  echo "  $CACHED_MARKETS - JSONL file tracking processed markets"
  echo "  $CACHED_LINEUPS - JSONL file tracking processed lineups"
  echo "  $LINEUP_TO_MARKET - JSON mapping lineups to source markets"
  echo "  $CACHE_STATE_LOG - Human-readable processing log"
  echo
  
  echo -e "${BOLD}Current State:${RESET}"
  
  # Markets state
  if [ -f "$CACHED_MARKETS" ] && [ -s "$CACHED_MARKETS" ]; then
    local market_entries=$(jq -s 'length' "$CACHED_MARKETS" 2>/dev/null || echo "0")
    echo "  Cached Markets: $market_entries entries"
    
    # Show last few markets processed
    echo "  Recent Markets:"
    tail -3 "$CACHED_MARKETS" 2>/dev/null | jq -r '"    " + .country + "/" + .zip + " (" + .timestamp + ")"' 2>/dev/null || echo "    (unable to parse recent entries)"
  else
    echo "  Cached Markets: No data"
  fi
  echo
  
  # Lineups state
  if [ -f "$CACHED_LINEUPS" ] && [ -s "$CACHED_LINEUPS" ]; then
    local lineup_entries=$(jq -s 'length' "$CACHED_LINEUPS" 2>/dev/null || echo "0")
    echo "  Cached Lineups: $lineup_entries entries"
    
    # Show total stations tracked
    local total_stations=$(jq -s '.[] | .stations_found' "$CACHED_LINEUPS" 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
    echo "  Total Stations (pre-dedup): $total_stations"
  else
    echo "  Cached Lineups: No data"
  fi
  echo
  
  # Mapping state
  if [ -f "$LINEUP_TO_MARKET" ] && [ -s "$LINEUP_TO_MARKET" ]; then
    local mapping_count=$(jq 'length' "$LINEUP_TO_MARKET" 2>/dev/null || echo "0")
    echo "  Lineup-to-Market Mappings: $mapping_count"
  else
    echo "  Lineup-to-Market Mappings: No data"
  fi
  echo
  
  # Log state
  if [ -f "$CACHE_STATE_LOG" ] && [ -s "$CACHE_STATE_LOG" ]; then
    local log_lines=$(wc -l < "$CACHE_STATE_LOG" 2>/dev/null || echo "0")
    local last_entry=$(tail -1 "$CACHE_STATE_LOG" 2>/dev/null | cut -d' ' -f1-2)
    echo "  State Log: $log_lines entries"
    echo "  Last Activity: $last_entry"
  else
    echo "  State Log: No data"
  fi
  echo
  
  echo -e "${BOLD}Functions Using State:${RESET}"
  echo "  record_market_processed() - Adds market entries"
  echo "  record_lineup_processed() - Adds lineup entries"
  echo "  is_market_cached() - Checks if market already processed"
  echo "  is_lineup_cached() - Checks if lineup already processed"
  echo "  get_unprocessed_markets() - Gets markets needing processing"
}

show_raw_cache_debug() {
  echo -e "\n${BOLD}${BLUE}=== Debug: Raw Cache Files ===${RESET}"
  echo -e "${YELLOW}⚠️  This shows technical file contents for debugging purposes${RESET}"
  echo
  
  echo -e "${BOLD}Cache Directory Contents:${RESET}"
  if [ -d "$CACHE_DIR" ]; then
    echo "Directory: $CACHE_DIR"
    ls -la "$CACHE_DIR" 2>/dev/null | head -20
    local total_files=$(find "$CACHE_DIR" -type f 2>/dev/null | wc -l)
    echo "Total files: $total_files"
    echo
  else
    echo "Cache directory not found: $CACHE_DIR"
    return 1
  fi
  
  echo -e "${BOLD}State File Samples:${RESET}"
  
  if [ -f "$CACHED_MARKETS" ] && [ -s "$CACHED_MARKETS" ]; then
    echo "Recent market entries (last 3):"
    tail -3 "$CACHED_MARKETS" | jq . 2>/dev/null || tail -3 "$CACHED_MARKETS"
    echo
  fi
  
  if [ -f "$CACHED_LINEUPS" ] && [ -s "$CACHED_LINEUPS" ]; then
    echo "Recent lineup entries (last 2):"
    tail -2 "$CACHED_LINEUPS" | jq . 2>/dev/null || tail -2 "$CACHED_LINEUPS"
    echo
  fi
  
  if [ -f "$LINEUP_TO_MARKET" ] && [ -s "$LINEUP_TO_MARKET" ]; then
    echo "Lineup mapping sample (first 3 entries):"
    jq 'to_entries | .[0:3]' "$LINEUP_TO_MARKET" 2>/dev/null || echo "Unable to parse mapping file"
    echo
  fi
  
  echo -e "${BOLD}Temporary Files:${RESET}"
  local temp_count=$(find "$CACHE_DIR" -name "last_raw_*.json" 2>/dev/null | wc -l)
  echo "Temporary API response files: $temp_count"
  if [ "$temp_count" -gt 0 ] && [ "$temp_count" -lt 10 ]; then
    echo "Recent temp files:"
    find "$CACHE_DIR" -name "last_raw_*.json" -exec basename {} \; | head -5
  elif [ "$temp_count" -ge 10 ]; then
    echo "Many temp files found - consider cleanup"
  fi
  echo
  
  echo -e "${BOLD}Cache Integrity Check:${RESET}"
  local issues=0
  
  # Check JSON validity of key files
  for file in "$USER_STATIONS_JSON" "$LINEUP_TO_MARKET"; do
    if [ -f "$file" ]; then
      if jq empty "$file" 2>/dev/null; then
        echo -e "${GREEN}✅ Valid JSON: $(basename "$file")${RESET}"
      else
        echo -e "${RED}❌ Invalid JSON: $(basename "$file")${RESET}"
        ((issues++))
      fi
    fi
  done
  
  if [ "$issues" -eq 0 ]; then
    echo -e "${GREEN}✅ No JSON integrity issues found${RESET}"
  else
    echo -e "${RED}❌ Found $issues JSON integrity issues${RESET}"
  fi
}

developer_information() {
  while true; do
    # Define developer menu options
  local dev_options=(
    "a|Cache State Tracking Details"
    "b|Debug: Raw Cache Files"
    "q|Back to Settings"
)
    
    # Use standardized menu display with clear warning
    show_menu_header "Developer Information" "Technical details for script developers and maintainers"
    echo -e "${YELLOW}This section contains technical details for script developers and maintainers.${RESET}"
    echo -e "${CYAN}End users typically don't need this information.${RESET}"
    echo
    
    show_menu_options "${dev_options[@]}"
    echo
    
    read -p "Select option: " dev_choice
    
    case $dev_choice in
      a|A) show_cache_state_details && pause_for_user ;;
      b|B) show_raw_cache_debug && pause_for_user ;;
      q|Q|"") break ;;
      *) show_invalid_menu_choice "Developer Information" "$dev_choice" ;;
    esac
  done
}

# ============================================================================
# MAIN APPLICATION ENTRY POINT
# ============================================================================

# Handle command line arguments before main execution
check_version_flags "$@"

detect_cache_format() {
    local cache_file="$1"
    local cache_name="$2"
    
    if [[ ! -f "$cache_file" ]] || [[ ! -s "$cache_file" ]]; then
        echo "missing"
        return 0
    fi
    
    local new_format_count=$(jq '[.[] | select(.availableIn)] | length' "$cache_file" 2>/dev/null || echo "0")
    local total_count=$(jq 'length' "$cache_file" 2>/dev/null || echo "0")
    
    if [[ "$total_count" -eq 0 ]]; then
        echo "empty"
    elif [[ "$new_format_count" -eq "$total_count" ]]; then
        echo "clean"
    elif [[ "$new_format_count" -gt 0 ]]; then
        echo "mixed"
    else
        echo "legacy"
    fi
}

validate_cache_formats_on_startup() {
    echo -e "${CYAN}🔍 Validating cache file formats...${RESET}"
    
    local base_format=$(detect_cache_format "$BASE_STATIONS_JSON" "base")
    local user_format=$(detect_cache_format "$USER_STATIONS_JSON" "user")
    local critical_issues=false
    
    echo -e "${CYAN}📊 Cache Format Analysis:${RESET}"
    echo -e "  Base cache: $base_format"
    echo -e "  User cache: $user_format"
    
    # FORCE FUNCTION: Check for any problematic formats
    if [[ "$base_format" == "legacy" ]] || [[ "$base_format" == "mixed" ]]; then
        echo -e "\n${RED}❌ CRITICAL: Base Cache Format Issue Detected${RESET}"
        echo -e "${RED}❌ Base cache uses legacy format and CANNOT be used${RESET}"
        echo -e "${CYAN}💡 You need an updated base cache file with clean multi-country format${RESET}"
        echo -e "${CYAN}💡 Contact script distributor for updated base cache${RESET}"
        echo -e "${CYAN}💡 Or use Base Cache Distribution Builder to convert existing cache${RESET}"
        critical_issues=true
    fi
    
    if [[ "$user_format" == "legacy" ]] || [[ "$user_format" == "mixed" ]]; then
        echo -e "\n${RED}❌ CRITICAL: User Cache Format Issue Detected${RESET}"
        echo -e "${RED}❌ User cache uses legacy format and CANNOT be used${RESET}"
        echo -e "${YELLOW}⚠️  Script will delete legacy user cache to prevent data corruption${RESET}"
        
        if confirm_action "Delete legacy user cache and allow script to continue?"; then
            echo -e "${CYAN}🔄 Deleting legacy user cache...${RESET}"
            rm -f "$USER_STATIONS_JSON"
            echo '[]' > "$USER_STATIONS_JSON"
            echo -e "${GREEN}✅ Legacy user cache deleted - you can rebuild with clean format${RESET}"
            echo -e "${CYAN}💡 Use 'Manage Television Markets' → 'Run User Caching' to rebuild${RESET}"
        else
            echo -e "${RED}❌ Cannot continue with legacy user cache${RESET}"
            critical_issues=true
        fi
    fi
    
    # FORCE FUNCTION: Prevent script operation if critical issues found
    if [[ "$critical_issues" == "true" ]]; then
        echo -e "\n${RED}❌ SCRIPT CANNOT CONTINUE WITH LEGACY FORMAT DATA${RESET}"
        echo -e "${CYAN}💡 Fix the format issues above and restart the script${RESET}"
        echo -e "${CYAN}💡 Use Base Cache Distribution Builder for cache conversion${RESET}"
        echo -e "${CYAN}💡 Or contact script distributor for updated files${RESET}"
        echo
        echo -e "${YELLOW}Press any key to exit...${RESET}"
        read -n 1 -s
        exit 1
    fi
    
    # Clear combined cache aggressively if any format issues were resolved
    if [[ "$user_format" == "legacy" ]] || [[ "$user_format" == "mixed" ]]; then
        cleanup_combined_cache
        echo -e "${CYAN}💡 Combined cache cleared - will rebuild when needed${RESET}"
    fi
    
    if [[ "$base_format" == "clean" ]] && [[ "$user_format" == "clean" || "$user_format" == "missing" || "$user_format" == "empty" ]]; then
        echo -e "${GREEN}✅ All cache formats are compatible${RESET}"
    fi
}

main_menu() {
  while true; do
    maintain_session_tokens
    
    show_main_menu
    
    read -p "Select option: " choice
    
    case $choice in
      1) search_local_database ;;
      2) dispatcharr_integration_check ;;
      3) scan_emby_missing_listingsids ;;
      4) manage_markets ;;
      5) run_user_caching "false" && pause_for_user ;;
      6) run_direct_api_search ;;
      7) reverse_station_id_lookup_menu ;;
      8) cache_management_main_menu ;;
      9) settings_menu ;;
      q|Q|"") echo -e "${GREEN}Goodbye!${RESET}"; exit 0 ;;
      *) show_invalid_menu_choice "Main Menu" "$choice" ;;
    esac
  done
}

# ============================================================================
# APPLICATION INITIALIZATION AND STARTUP
# ============================================================================

# Initialize directories first
setup_directories

# Load essential modules (utils and config only)
load_essential_modules

# Now we can safely call setup_config since config.sh is loaded
setup_config
check_dependencies

# Load all remaining modules (they can now safely use config variables)
load_remaining_modules

# Validate cache formats before proceeding
validate_cache_formats_on_startup

# Initialize cache optimization system
init_combined_cache_startup

# Initialize and perform startup update check
if command -v perform_startup_update_check >/dev/null 2>&1; then
    perform_startup_update_check
fi

# Wait for user to allow review of status messages
pause_for_user

# Start main application
main_menu