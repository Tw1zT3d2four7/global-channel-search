#!/bin/bash
# lib/core/cache.sh - Cache Management Module
# Extracted from Global Station Search v1.4.0
# Core cache operations, station management, and data processing

# ============================================================================
# CACHE INITIALIZATION AND SETUP
# ============================================================================

init_combined_cache_startup() {
  # Build combined cache if both base and user caches exist
  if [ -f "$BASE_STATIONS_JSON" ] && [ -s "$BASE_STATIONS_JSON" ] && 
     [ -f "$USER_STATIONS_JSON" ] && [ -s "$USER_STATIONS_JSON" ]; then
    
    local user_count=$(jq 'length' "$USER_STATIONS_JSON" 2>/dev/null || echo "0")
    local base_count=$(jq 'length' "$BASE_STATIONS_JSON" 2>/dev/null || echo "0")
    
    # Check if we can skip the rebuild using persistent state
    if check_combined_cache_freshness; then
      echo -e "${GREEN}✅ Station database ready (using cached version)${RESET}"
    else
      echo -e "${CYAN}🔄 Building combined station database...${RESET}"
      echo -e "${CYAN}💡 Merging $base_count base stations + $user_count user stations${RESET}"
      echo -e "${CYAN}💡 This may take a moment for large datasets...${RESET}"
      build_combined_cache_with_progress # Show the progress output
    fi
  elif [ -f "$BASE_STATIONS_JSON" ] && [ -s "$BASE_STATIONS_JSON" ]; then
    # Only base cache exists
    echo -e "${GREEN}✅ Station database ready (base cache only)${RESET}"
  elif [ -f "$USER_STATIONS_JSON" ] && [ -s "$USER_STATIONS_JSON" ]; then
    # Only user cache exists
    local user_count=$(jq 'length' "$USER_STATIONS_JSON" 2>/dev/null || echo "0")
    echo -e "${GREEN}✅ Station database ready ($user_count user stations)${RESET}"
  fi
}

init_user_cache() {
  if [ ! -f "$USER_STATIONS_JSON" ]; then
    echo '[]' > "$USER_STATIONS_JSON"
    echo -e "${YELLOW}Initialized empty user stations cache${RESET}" >&2
  fi
}

setup_optimized_cache() {
  # Initialize cache validity checking
  COMBINED_CACHE_VALID=false
  COMBINED_CACHE_TIMESTAMP=0
  
  # Pre-build combined cache if it will be needed and is significant
  init_combined_cache_startup
}

# ============================================================================
# CACHE CLEANUP AND MAINTENANCE
# ============================================================================

cleanup_cache() {
  echo -e "${YELLOW}Cleaning up cached station files...${RESET}"
  
  # IMPORTANT: Create backup before cleanup if user cache exists
  if [[ -f "$USER_STATIONS_JSON" ]] && [[ -s "$USER_STATIONS_JSON" ]]; then
    backup_existing_data
    echo "  ✓ User cache backed up before cleanup"
  fi
  
  # Remove station cache files
  if [ -d "$STATION_CACHE_DIR" ]; then
    rm -f "$STATION_CACHE_DIR"/*.json 2>/dev/null || true
    echo "  ✓ Station cache files removed"
  fi
  
  # Remove raw API response files
  rm -f "$CACHE_DIR"/last_raw_*.json 2>/dev/null || true
  echo "  ✓ Raw API response files removed"
  
  # Remove temporary files
  rm -f "$CACHE_DIR"/*.tmp 2>/dev/null || true
  echo "  ✓ Temporary files removed"

  # Remove API search results
  rm -f "$API_SEARCH_RESULTS" 2>/dev/null || true
  echo "  ✓ API search results removed"
  
  # Remove combined cache files
  cleanup_combined_cache
  echo "  ✓ Combined cache files removed"
  
  # Remove legacy master JSON files (all variants)
  rm -f "$CACHE_DIR"/all_stations_master.json* 2>/dev/null || true
  rm -f "$CACHE_DIR"/working_stations.json* 2>/dev/null || true
  echo "  ✓ Legacy cache files removed"
  
  # Remove lineup cache (will be rebuilt)
  rm -f "$LINEUP_CACHE" 2>/dev/null || true
  echo "  ✓ Lineup cache removed"
  
  # CRITICAL: PRESERVE these important files:
  # - $BASE_STATIONS_JSON (distributed base cache)
  # - $USER_STATIONS_JSON (user's personal cache) - BACKED UP ABOVE
  # - Station metadata provides all coverage information
  # - $CACHED_MARKETS (state tracking)
  # - $CACHED_LINEUPS (state tracking)
  # - $LINEUP_TO_MARKET (state tracking)
  # - $CACHE_STATE_LOG (state tracking)
  # - $DISPATCHARR_* files (Dispatcharr integration)
  
  echo "  ✓ User cache, base cache, and state tracking files preserved"
  echo -e "${GREEN}Cache cleanup completed (important files preserved and backed up)${RESET}"
}

invalidate_combined_cache() {
  COMBINED_CACHE_VALID=false
  cleanup_combined_cache
  
  # Remove saved state from config file
  if [ -f "$CONFIG_FILE" ]; then
    local temp_config="${CONFIG_FILE}.tmp"
    grep -v -E '^COMBINED_CACHE_TIMESTAMP=|^COMBINED_CACHE_BASE_TIME=|^COMBINED_CACHE_USER_TIME=' "$CONFIG_FILE" > "$temp_config" 2>/dev/null
    mv "$temp_config" "$CONFIG_FILE"
  fi
}

mark_user_cache_updated() {
  invalidate_combined_cache
  echo -e "${CYAN}💡 Station database will be refreshed on next search${RESET}"
}

# ============================================================================
# COMBINED CACHE MANAGEMENT
# ============================================================================

build_combined_cache_with_progress() {
  echo -e "${CYAN}🔄 Building station database (3 steps)...${RESET}" >&2
  
  # Step 1: Basic validation
  echo -e "${CYAN}🔍 [1/3] Validating cache files...${RESET}" >&2
  
  if [[ -f "$BASE_STATIONS_JSON" ]] && [[ -s "$BASE_STATIONS_JSON" ]]; then
    if ! jq empty "$BASE_STATIONS_JSON" 2>/dev/null; then
      echo -e "${RED}❌ Base cache is invalid JSON${RESET}" >&2
      return 1
    fi
  fi
  
  if [[ -f "$USER_STATIONS_JSON" ]] && [[ -s "$USER_STATIONS_JSON" ]]; then
    if ! jq empty "$USER_STATIONS_JSON" 2>/dev/null; then
      echo -e "${RED}❌ User cache is invalid JSON${RESET}" >&2
      return 1
    fi
  fi
  
  echo -e "${GREEN}✅ [1/3] Cache files are valid${RESET}" >&2
  
  # Step 2: Analyze
  echo -e "${CYAN}📊 [2/3] Analyzing source databases...${RESET}" >&2
  local base_count=$([ -f "$BASE_STATIONS_JSON" ] && jq 'length' "$BASE_STATIONS_JSON" 2>/dev/null || echo "0")
  local user_count=$([ -f "$USER_STATIONS_JSON" ] && jq 'length' "$USER_STATIONS_JSON" 2>/dev/null || echo "0")
  echo -e "${CYAN}   Base: $base_count stations, User: $user_count stations${RESET}" >&2
  
  if [[ "$base_count" -eq 0 && "$user_count" -eq 0 ]]; then
    echo -e "${RED}❌ No station data found${RESET}" >&2
    return 1
  fi
  
  # Step 3: Merge with proper deduplication
  echo -e "${CYAN}🔄 [3/3] Merging and deduplicating...${RESET}" >&2

  if [[ "$base_count" -eq 0 ]]; then
    cp "$USER_STATIONS_JSON" "$COMBINED_STATIONS_JSON"
  elif [[ "$user_count" -eq 0 ]]; then
    cp "$BASE_STATIONS_JSON" "$COMBINED_STATIONS_JSON"
  else
    # Use the working merge strategy
    jq -s 'flatten | unique_by(.stationId) | sort_by(.name // "")' \
      "$BASE_STATIONS_JSON" "$USER_STATIONS_JSON" > "$COMBINED_STATIONS_JSON"
  fi

  local final_count=$(jq 'length' "$COMBINED_STATIONS_JSON" 2>/dev/null || echo "0")
  echo -e "${GREEN}✅ Database ready: $final_count total stations${RESET}" >&2
  
  # Save state
  save_combined_cache_state "$(date +%s)" \
    "$(stat -c %Y "$BASE_STATIONS_JSON" 2>/dev/null || echo "0")" \
    "$(stat -c %Y "$USER_STATIONS_JSON" 2>/dev/null || echo "0")"
  
  COMBINED_CACHE_VALID=true
  return 0
}

force_rebuild_combined_cache() {
  echo -e "\n${BOLD}Force Rebuild Combined Cache${RESET}"
  echo -e "${YELLOW}This will rebuild the combined station database from base and user caches.${RESET}"
  echo -e "${CYAN}Use this if you suspect the combined cache is corrupted or outdated.${RESET}"
  echo
  
  # Show current cache status
  local breakdown=$(get_stations_breakdown)
  local base_count=$(echo "$breakdown" | cut -d' ' -f1)
  local user_count=$(echo "$breakdown" | cut -d' ' -f2)
  
  echo -e "${BOLD}Current Cache Status:${RESET}"
  echo -e "Base stations: $base_count"
  echo -e "User stations: $user_count"
  
  if [ -f "$COMBINED_STATIONS_JSON" ]; then
    local combined_count=$(jq 'length' "$COMBINED_STATIONS_JSON" 2>/dev/null || echo "0")
    local file_size=$(ls -lh "$COMBINED_STATIONS_JSON" 2>/dev/null | awk '{print $5}')
    echo -e "Combined cache: $combined_count stations ($file_size)"
  else
    echo -e "Combined cache: Not found"
  fi
  echo
  
  # Check if rebuild is actually needed
  if [ "$base_count" -eq 0 ] && [ "$user_count" -eq 0 ]; then
    echo -e "${RED}❌ No source caches available to rebuild from${RESET}"
    echo -e "${CYAN}💡 You need either a base cache or user cache to rebuild${RESET}"
    return 1
  fi
  
  if ! confirm_action "Force rebuild combined cache from source files?"; then
    echo -e "${YELLOW}⚠️  Rebuild cancelled${RESET}"
    return 1
  fi
  
  echo -e "${CYAN}🔄 Force rebuilding combined cache...${RESET}"
  
  # Force invalidate current cache
  invalidate_combined_cache
  
  # Backup existing combined cache if it exists
  if [ -f "$COMBINED_STATIONS_JSON" ]; then
    local backup_file="${COMBINED_STATIONS_JSON}.backup.$(date +%Y%m%d_%H%M%S)"
    if cp "$COMBINED_STATIONS_JSON" "$backup_file" 2>/dev/null; then
      echo -e "${CYAN}💾 Backed up existing cache to: $(basename "$backup_file")${RESET}"
    fi
  fi
  
  # Force rebuild
  if build_combined_cache_with_progress; then
    local new_count=$(jq 'length' "$COMBINED_STATIONS_JSON" 2>/dev/null || echo "0")
    echo -e "${GREEN}✅ Combined cache rebuilt successfully${RESET}"
    echo -e "${CYAN}📊 New combined cache: $new_count stations${RESET}"
    
    # Verify the rebuild worked
    if [ "$new_count" -gt 0 ]; then
      echo -e "${GREEN}✅ Rebuild verification passed${RESET}"
    else
      echo -e "${RED}❌ Rebuild verification failed - cache appears empty${RESET}"
      return 1
    fi
  else
    echo -e "${RED}❌ Failed to rebuild combined cache${RESET}"
    echo -e "${CYAN}💡 Check disk space and file permissions${RESET}"
    return 1
  fi
  
  return 0
}

get_effective_stations_file() {
  # Simple, clean logic without excessive validation
  
  # If no user stations, use base
  if [ ! -f "$USER_STATIONS_JSON" ] || [ ! -s "$USER_STATIONS_JSON" ]; then
    if [ -f "$BASE_STATIONS_JSON" ] && [ -s "$BASE_STATIONS_JSON" ]; then
      echo "$BASE_STATIONS_JSON"
      return 0
    else
      return 1
    fi
  fi
  
  # If no base stations, use user
  if [ ! -f "$BASE_STATIONS_JSON" ] || [ ! -s "$BASE_STATIONS_JSON" ]; then
    echo "$USER_STATIONS_JSON"
    return 0
  fi
  
  # Both exist - use combined
  if check_combined_cache_freshness; then
    echo "$COMBINED_STATIONS_JSON"
    return 0
  else
    if build_combined_cache_with_progress; then
      echo "$COMBINED_STATIONS_JSON"
      return 0
    else
      # Fallback to base cache if combine fails
      echo "$BASE_STATIONS_JSON"
      return 0
    fi
  fi
}

# ============================================================================
# USER CACHE MANAGEMENT
# ============================================================================

add_stations_to_user_cache() {
  local new_stations_file="$1"
  
  echo -e "${CYAN}🔄 Starting user cache integration process...${RESET}"
  
  # File validation with detailed feedback
  if [ ! -f "$new_stations_file" ]; then
    echo -e "${RED}❌ File Validation: New stations file not found${RESET}"
    echo -e "${CYAN}💡 Expected file: $new_stations_file${RESET}"
    echo -e "${CYAN}💡 Check if caching process completed successfully${RESET}"
    return 1
  fi
  
  echo -e "${CYAN}🔍 Validating new stations file format...${RESET}"
  if ! jq empty "$new_stations_file" 2>/dev/null; then
    echo -e "${RED}❌ File Validation: New stations file contains invalid JSON${RESET}"
    echo -e "${CYAN}💡 File: $new_stations_file${RESET}"
    echo -e "${CYAN}💡 File may be corrupted or incomplete${RESET}"
    echo -e "${CYAN}💡 Try running User Cache Expansion again${RESET}"
    return 1
  fi
  echo -e "${GREEN}✅ New stations file validation passed${RESET}"

  # FORCE FUNCTION: Validate clean format - reject legacy completely
  echo -e "${CYAN}🔍 Validating format compatibility (clean format required)...${RESET}"

  # Check new stations file for legacy format
  local new_legacy_count=$(jq '[.[] | select(.country and (.availableIn | not))] | length' "$new_stations_file" 2>/dev/null || echo "0")
  if [[ "$new_legacy_count" -gt 0 ]]; then
    echo -e "${RED}❌ Format Validation: New stations file contains $new_legacy_count legacy format stations${RESET}"
    echo -e "${RED}❌ FORCE FUNCTION: Legacy data cannot be processed${RESET}"
    echo -e "${CYAN}💡 Solution: Rebuild user cache with clean format${RESET}"
    echo -e "${CYAN}💡 Action: Delete user cache and run User Cache Expansion again${RESET}"
    return 1
  fi

  # Check existing user cache for legacy format
  if [[ -f "$USER_STATIONS_JSON" ]] && [[ -s "$USER_STATIONS_JSON" ]]; then
    local user_legacy_count=$(jq '[.[] | select(.country and (.availableIn | not))] | length' "$USER_STATIONS_JSON" 2>/dev/null || echo "0")
    if [[ "$user_legacy_count" -gt 0 ]]; then
      echo -e "${RED}❌ Format Validation: Existing user cache contains $user_legacy_count legacy format stations${RESET}"
      echo -e "${RED}❌ FORCE FUNCTION: Legacy data cannot be processed${RESET}"
      echo -e "${CYAN}💡 Solution: Delete existing user cache and rebuild with clean format${RESET}"
      
      if confirm_action "Delete legacy user cache and start fresh?"; then
        echo -e "${CYAN}🔄 Deleting legacy user cache...${RESET}"
        echo '[]' > "$USER_STATIONS_JSON" || {
          echo -e "${RED}❌ Cannot create fresh user cache${RESET}"
          return 1
        }
        echo -e "${GREEN}✅ Legacy user cache deleted - starting fresh${RESET}"
      else
        echo -e "${YELLOW}⚠️  User cache integration cancelled${RESET}"
        return 1
      fi
    fi
  fi

  echo -e "${GREEN}✅ Format validation passed - all data uses clean format${RESET}"
  
  # Initialize user cache with feedback
  echo -e "${CYAN}🔄 Initializing user cache environment...${RESET}"
  init_user_cache
  
  # Validate user cache file with comprehensive error handling
  if [ -f "$USER_STATIONS_JSON" ]; then
    echo -e "${CYAN}🔍 Validating existing user cache...${RESET}"
    if ! jq empty "$USER_STATIONS_JSON" 2>/dev/null; then
      echo -e "${RED}❌ User Cache Validation: Existing cache file is corrupted${RESET}"
      echo -e "${CYAN}💡 File: $USER_STATIONS_JSON${RESET}"
      echo -e "${CYAN}💡 Backing up corrupted file and creating fresh cache${RESET}"
      
      # Backup corrupted file with feedback
      local backup_file="${USER_STATIONS_JSON}.corrupted.$(date +%Y%m%d_%H%M%S)"
      echo -e "${CYAN}💾 Creating backup of corrupted cache...${RESET}"
      if mv "$USER_STATIONS_JSON" "$backup_file" 2>/dev/null; then
        echo -e "${GREEN}✅ Corrupted file backed up to: $(basename "$backup_file")${RESET}"
      else
        echo -e "${RED}❌ Backup Operation: Cannot backup corrupted cache file${RESET}"
        echo -e "${CYAN}💡 Check file permissions in cache directory${RESET}"
        return 1
      fi
      
      # Initialize fresh cache with feedback
      echo -e "${CYAN}🔄 Creating fresh user cache...${RESET}"
      echo '[]' > "$USER_STATIONS_JSON" || {
        echo -e "${RED}❌ Cache Creation: Cannot create new user cache file${RESET}"
        echo -e "${CYAN}💡 Check disk space and file permissions${RESET}"
        echo -e "${CYAN}💡 Directory: $(dirname "$USER_STATIONS_JSON")${RESET}"
        return 1
      }
      echo -e "${GREEN}✅ Fresh user cache created successfully${RESET}"
    else
      echo -e "${GREEN}✅ Existing user cache validation passed${RESET}"
    fi
  else
    echo -e "${YELLOW}⚠️  No existing user cache found - will create new one${RESET}"
  fi
  
  echo -e "${CYAN}📊 Preparing to merge new stations with user cache...${RESET}"
  
  # Create temporary file with feedback
  local temp_file="$USER_STATIONS_JSON.tmp.$(date +%s)"
  
  # Check disk space with detailed feedback
  echo -e "${CYAN}🔍 Checking available disk space...${RESET}"
  local new_stations_size=$(stat -c%s "$new_stations_file" 2>/dev/null || stat -f%z "$new_stations_file" 2>/dev/null || echo "0")
  local user_cache_size=$(stat -c%s "$USER_STATIONS_JSON" 2>/dev/null || stat -f%z "$USER_STATIONS_JSON" 2>/dev/null || echo "0")
  local estimated_size=$((new_stations_size + user_cache_size + 1048576))  # Add 1MB buffer
  
  # Check available disk space (rough estimate)
  local available_space=$(df "$(dirname "$USER_STATIONS_JSON")" 2>/dev/null | awk 'NR==2 {print $4 * 1024}' || echo "999999999999")
  
  # Convert scientific notation to integer if needed
  if [[ "$available_space" == *"e+"* ]] || [[ "$available_space" == *"E+"* ]]; then
    # Use printf to convert scientific notation to integer
    available_space=$(printf "%.0f" "$available_space" 2>/dev/null || echo "999999999999")
  fi
  
  # Ensure we have a valid integer
  if ! [[ "$available_space" =~ ^[0-9]+$ ]]; then
    available_space="999999999999"  # Default to large number if parsing fails
  fi
  
  if [[ $estimated_size -gt $available_space ]]; then
    echo -e "${RED}❌ Disk Space Check: Insufficient disk space for merge operation${RESET}"
    echo -e "${CYAN}💡 Estimated space needed: $(( estimated_size / 1048576 )) MB${RESET}"
    echo -e "${CYAN}💡 Available space: $(( available_space / 1048576 )) MB${RESET}"
    echo -e "${CYAN}💡 Free up disk space and try again${RESET}"
    return 1
  fi
  echo -e "${GREEN}✅ Sufficient disk space available for merge${RESET}"
  
  # Perform merge with detailed progress
  echo -e "${CYAN}🔄 Merging station data (deduplication and sorting)...${RESET}"
  echo -e "${CYAN}💡 This may take a moment for large datasets${RESET}"
  
  if ! jq -s '
    flatten | 
    group_by(.stationId) | 
    map(
      if length == 1 then
        .[0]
      else
        # Merge multiple entries - keep first one, merge countries
        .[0] + {
          availableIn: ([.[] | .availableIn[]?] | flatten | unique | sort),
          multiCountry: ([.[] | .availableIn[]?] | flatten | unique | length > 1),
          lineupTracing: (
            [.[] | .lineupTracing[]?] | 
            unique_by(.country) |
            to_entries |
            map(.value + {
              discoveredOrder: (.key + 1),
              isPrimary: (.key == 0)
            })
          )
        }
      end
    ) |
    sort_by(.name // "")
  ' "$USER_STATIONS_JSON" "$new_stations_file" > "$temp_file" 2>/dev/null; then

    echo -e "${RED}❌ Merge Operation: Failed to merge station data${RESET}"
    echo -e "${CYAN}💡 This could be due to:${RESET}"
    echo -e "${CYAN}  • Insufficient memory for large datasets${RESET}"
    echo -e "${CYAN}  • Disk I/O errors or corruption${RESET}"
    echo -e "${CYAN}  • Invalid JSON data in source files${RESET}"
    echo -e "${CYAN}💡 Try running User Cache Expansion with fewer markets${RESET}"
    
    # Clean up temp file
    rm -f "$temp_file" 2>/dev/null
    return 1
  fi
  echo -e "${GREEN}✅ Station data merge completed successfully${RESET}"
  
  # Validate merged result with feedback
  echo -e "${CYAN}🔍 Validating merged station data...${RESET}"
  if ! jq empty "$temp_file" 2>/dev/null; then
    echo -e "${RED}❌ Merge Validation: Merge produced invalid JSON${RESET}"
    echo -e "${CYAN}💡 Merge operation failed - keeping original cache${RESET}"
    rm -f "$temp_file" 2>/dev/null
    return 1
  fi
  echo -e "${GREEN}✅ Merged data validation passed${RESET}"
  
  # Backup original cache with feedback
  if [ -s "$USER_STATIONS_JSON" ]; then
    echo -e "${CYAN}💾 Creating backup of current user cache...${RESET}"
    local backup_file="${USER_STATIONS_JSON}.backup.$(date +%Y%m%d_%H%M%S)"
    if ! cp "$USER_STATIONS_JSON" "$backup_file" 2>/dev/null; then
      echo -e "${YELLOW}⚠️  Backup Warning: Could not create safety backup${RESET}"
      echo -e "${CYAN}💡 Continuing without backup (original cache will be overwritten)${RESET}"
      
      if ! confirm_action "Continue without backup?"; then
        echo -e "${YELLOW}⚠️  User cache merge cancelled by user${RESET}"
        rm -f "$temp_file" 2>/dev/null
        return 1
      fi
    else
      echo -e "${GREEN}✅ Safety backup created: $(basename "$backup_file")${RESET}"
    fi
  fi
  
  # Replace original with merged data
  echo -e "${CYAN}💾 Finalizing user cache update...${RESET}"
  if ! mv "$temp_file" "$USER_STATIONS_JSON" 2>/dev/null; then
    echo -e "${RED}❌ Cache Update: Cannot finalize user cache file${RESET}"
    echo -e "${CYAN}💡 Check file permissions: $USER_STATIONS_JSON${RESET}"
    echo -e "${CYAN}💡 Check disk space and try again${RESET}"
    
    # Try to restore from backup if it exists
    local latest_backup=$(ls -t "${USER_STATIONS_JSON}.backup."* 2>/dev/null | head -1)
    if [[ -n "$latest_backup" ]]; then
      echo -e "${CYAN}🔄 Attempting to restore from backup...${RESET}"
      if cp "$latest_backup" "$USER_STATIONS_JSON" 2>/dev/null; then
        echo -e "${GREEN}✅ User cache restored from backup${RESET}"
      fi
    fi
    
    rm -f "$temp_file" 2>/dev/null
    return 1
  fi
  
  # Success validation and reporting
  echo -e "${CYAN}🔍 Validating final user cache...${RESET}"
  local new_count
  if new_count=$(jq 'length' "$USER_STATIONS_JSON" 2>/dev/null); then
    echo -e "${GREEN}✅ User cache integration completed successfully${RESET}"
    echo -e "${CYAN}📊 Total stations in user cache: $new_count${RESET}"
    
    # Cleanup old backups with feedback
    echo -e "${CYAN}🧹 Cleaning up old backup files...${RESET}"
    local backup_pattern="${USER_STATIONS_JSON}.backup.*"
    local backup_count=$(ls -1 $backup_pattern 2>/dev/null | wc -l)
    if [[ $backup_count -gt 5 ]]; then
      ls -t $backup_pattern 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null
      echo -e "${GREEN}✅ Cleaned up old backup files (kept 5 most recent)${RESET}"
    else
      echo -e "${CYAN}💡 Backup file count within limits ($backup_count kept)${RESET}"
    fi
    
    mark_user_cache_updated

    # Immediately rebuild combined cache
    echo -e "${CYAN}🔄 Rebuilding combined cache with new stations...${RESET}"
    if build_combined_cache_with_progress >/dev/null 2>&1; then
      echo -e "${GREEN}✅ Combined cache rebuilt and ready${RESET}"
    else
      echo -e "${YELLOW}⚠️  Combined cache will rebuild on next access${RESET}"
    fi
      
    return 0
  fi
}

# ============================================================================
# MARKET AND LINEUP COVERAGE FUNCTIONS
# ============================================================================

# MARKET FUNCTIONS
is_market_in_base_cache() {
  local country="$1"
  local zip="$2"
  grep -Fxq "$country,$zip" "$BASE_MARKETS_CSV" 2>/dev/null
}

is_market_in_user_cache() {
  local country="$1" 
  local zip="$2"
  # Check user's state tracking file
  is_market_cached "$country" "$zip"  # This function already exists
}

is_market_processed() {
  local country="$1"
  local zip="$2"
  # Check if market is covered by EITHER base or user cache
  is_market_in_base_cache "$country" "$zip" || is_market_in_user_cache "$country" "$zip"
}

# LINEUP FUNCTIONS  
is_lineup_in_base_cache() {
  local lineup_id="$1"
  if [ ! -f "$BASE_STATIONS_JSON" ] || [ ! -s "$BASE_STATIONS_JSON" ]; then
    return 1
  fi
  jq -e --arg lineup "$lineup_id" \
    '[.[] | select(.lineupTracing[]? | .lineupId == $lineup)] | length > 0' \
    "$BASE_STATIONS_JSON" >/dev/null 2>&1
}

# WRAPPER FOR COMPATIBILITY REMOVE IN FUTURE VERSION)
check_lineup_in_base_cache() {
  local lineup_id="$1"
  
  if [[ -z "$lineup_id" ]]; then
    return 1
  fi
  
  # Use the existing is_lineup_in_base_cache function
  is_lineup_in_base_cache "$lineup_id"
}

# WRAPPER FOR COMPATIBILITY REMOVE IN FUTURE VERSION)
is_lineup_in_user_cache() {
  local lineup_id="$1"
  # Use existing function that checks user cache state
  is_lineup_cached "$lineup_id"  # This function already exists
}

is_lineup_processed() {
  local lineup_id="$1"
  # Check if lineup is covered by EITHER base or user cache
  is_lineup_in_base_cache "$lineup_id" || is_lineup_in_user_cache "$lineup_id"
}

# COUNTRY FUNCTIONS
get_base_cache_countries() {
  if [ ! -f "$BASE_STATIONS_JSON" ] || [ ! -s "$BASE_STATIONS_JSON" ]; then
    echo ""
    return 1
  fi
  jq -r '[.[] | .availableIn[]?] | unique | join(",")' \
    "$BASE_STATIONS_JSON" 2>/dev/null || echo ""
}

get_user_cache_countries() {
  if [ ! -f "$USER_STATIONS_JSON" ] || [ ! -s "$USER_STATIONS_JSON" ]; then
    echo ""
    return 1
  fi
  jq -r '[.[] | .availableIn[]?] | unique | join(",")' \
    "$USER_STATIONS_JSON" 2>/dev/null || echo ""
}

get_all_cache_countries() {
  # Get countries from both base and user caches, combined and deduplicated
  local base_countries=$(get_base_cache_countries)
  local user_countries=$(get_user_cache_countries)
  
  # Combine and deduplicate
  echo "$base_countries,$user_countries" | tr ',' '\n' | grep -v '^$' | sort -u | tr '\n' ',' | sed 's/,$//'
}

# ============================================================================
# USER CACHING - COMPONENT FUNCTIONS
# ============================================================================

validate_caching_prerequisites() {
  local force_refresh="${1:-false}"
  
  # Check if server is configured for API operations - REQUIRED for user caching
  if [[ -z "${CHANNELS_URL:-}" ]]; then
    echo -e "${RED}❌ Channels DVR Integration: Server not configured${RESET}"
    echo -e "${CYAN}💡 User Cache Expansion requires a Channels DVR server to function${RESET}"
    return 1
  fi

  echo -e "${GREEN}✅ Channels DVR server configured: $CHANNELS_URL${RESET}"
  echo -e "${CYAN}🔗 Testing server connection...${RESET}"
  
  # Test server connection before starting caching process
  if ! curl -s --connect-timeout $QUICK_TIMEOUT "$CHANNELS_URL" >/dev/null 2>&1; then
    echo -e "${RED}❌ Channels DVR Integration: Cannot connect to server${RESET}"
    echo -e "${CYAN}💡 Server: $CHANNELS_URL${RESET}"
    if ! confirm_action "Continue anyway? (caching will likely fail)"; then
      echo -e "${YELLOW}⚠️  User Cache Expansion cancelled${RESET}"
      return 1
    fi
  else
    echo -e "${GREEN}✅ Server connection confirmed${RESET}"
  fi

  # Initialize user cache and state tracking
  init_user_cache
  init_cache_state_tracking
  
  return 0
}

analyze_markets_for_processing() {
  local force_refresh="$1"
  
  # Initialize counters and arrays
  local markets_to_process=()
  local total_configured=0
  local already_cached=0
  local base_cache_skipped=0
  local will_process=0
  
  # Read through CSV and categorize each market - STATUS MESSAGES TO STDERR
  while IFS=, read -r country zip; do
    [[ "$country" == "Country" ]] && continue
    ((total_configured++))
    
    # Check various conditions to determine if we should process this market
    if [[ "$force_refresh" == "true" ]]; then
      # Force refresh mode - process everything
      markets_to_process+=("$country,$zip")
      ((will_process++))
      echo -e "${CYAN}🔄 Will force refresh: $country/$zip${RESET}" >&2
    elif is_market_cached "$country" "$zip"; then
      # Market already processed in user cache
      ((already_cached++))
      echo -e "${GREEN}✅ Already cached: $country/$zip${RESET}" >&2
    elif [[ "$FORCE_REFRESH_ACTIVE" != "true" ]] && check_market_in_base_cache "$country" "$zip"; then
      # Market exactly covered by base cache
      ((base_cache_skipped++))
      echo -e "${YELLOW}⏭️  Skipping (in base cache): $country/$zip${RESET}" >&2
      # Record as processed since it's covered by base cache
      record_market_processed "$country" "$zip" 0
    else
      # Market needs processing
      markets_to_process+=("$country,$zip")
      ((will_process++))
      echo -e "${BLUE}📋 Will process: $country/$zip${RESET}" >&2
    fi
  done < "$CSV_FILE"
  
  # Show processing summary - ALL TO STDERR
  echo -e "\n${BOLD}${BLUE}=== Market Analysis Results ===${RESET}" >&2
  echo -e "${CYAN}📊 Total configured markets: $total_configured${RESET}" >&2
  echo -e "${GREEN}📊 Already cached: $already_cached${RESET}" >&2
  echo -e "${YELLOW}📊 Skipped (base cache): $base_cache_skipped${RESET}" >&2
  echo -e "${BLUE}📊 Will process: $will_process${RESET}" >&2
  
  # Early exit if nothing to process
  if [ "$will_process" -eq 0 ]; then
    echo -e "\n${GREEN}✅ All markets are already processed!${RESET}" >&2
    echo -e "${CYAN}💡 No new stations to add to user cache${RESET}" >&2
    echo -e "${CYAN}💡 Add new markets or use force refresh to reprocess existing ones${RESET}" >&2
    return 1  # Signal no processing needed
  fi
  
  echo -e "\n${CYAN}🔄 Starting incremental caching for $will_process markets...${RESET}" >&2
  
  # Export markets array for use by calling function - ONLY DATA TO STDOUT
  # Convert array to newline-separated string and echo to stdout
  printf '%s\n' "${markets_to_process[@]}"
  
  return 0
}

setup_caching_environment() {
  # Clean up temporary files (but preserve user and base caches)
  echo -e "${CYAN}🧹 Preparing cache environment...${RESET}" >&2
  rm -f "$LINEUP_CACHE" cache/unique_lineups.txt "$STATION_CACHE_DIR"/*.json cache/enhanced_stations.log >&2 2>/dev/null
  rm -f "$CACHE_DIR"/all_stations_master.json* "$CACHE_DIR"/working_stations.json* >&2 2>/dev/null || true
  
  local start_time=$(date +%s.%N)
  mkdir -p "cache" "$STATION_CACHE_DIR" >&2 2>/dev/null
  > "$LINEUP_CACHE"
  
  # Return ONLY start time for duration calculations - NO OTHER OUTPUT
  echo "$start_time"
}

process_markets_for_lineups() {
  local markets_to_process=("$@")
  local will_process=${#markets_to_process[@]}
  local start_time=$(date +%s.%N)
  
  echo -e "${CYAN}📊 Fetching TV lineups from unprocessed markets...${RESET}"
  local markets_processed=0
  local markets_failed=0
  
  for market in "${markets_to_process[@]}"; do
    IFS=, read -r COUNTRY ZIP <<< "$market"
    ((markets_processed++))
    
    echo -e "${CYAN}📡 [$markets_processed/$will_process] Querying lineups for $COUNTRY/$ZIP${RESET}"
    
    # API call with enhanced error handling
    local api_url="$CHANNELS_URL/tms/lineups/$COUNTRY/$ZIP"
    
    local response
    response=$(curl -s --connect-timeout $STANDARD_TIMEOUT --max-time $MAX_OPERATION_TIME "$api_url" 2>/dev/null)
    local curl_exit_code=$?
    
    # Handle API errors during caching
    if [[ $curl_exit_code -ne 0 ]]; then
      echo -e "${RED}❌ API Error for $COUNTRY/$ZIP: Curl failed with code $curl_exit_code${RESET}"
      ((markets_failed++))
      record_market_processed "$COUNTRY" "$ZIP" 0
      continue
    fi
    
    echo "$response" > "cache/last_raw_${COUNTRY}_${ZIP}.json"
    
    if echo "$response" | jq -e . > /dev/null 2>&1; then
      # Count lineups found for this market
      local lineups_found=$(echo "$response" | jq 'length')
      
      # Record that this market was processed
      record_market_processed "$COUNTRY" "$ZIP" "$lineups_found"
      
      # Add lineups to cache
      echo "$response" | jq -c '.[]' >> "$LINEUP_CACHE"
      echo -e "${GREEN}✅ Found $lineups_found lineups for $COUNTRY/$ZIP${RESET}"
    else
      echo -e "${RED}❌ Invalid JSON response for $COUNTRY/$ZIP${RESET}"
      ((markets_failed++))
      record_market_processed "$COUNTRY" "$ZIP" 0
    fi
  done
  
  # Show market processing summary
  echo -e "\n${BOLD}${GREEN}✅ Market Processing Summary:${RESET}"
  echo -e "${GREEN}Markets processed: $markets_processed${RESET}"
  if [[ $markets_failed -gt 0 ]]; then
    echo -e "${RED}Markets failed: $markets_failed${RESET}"
  fi

  # Return success/failure indication
  if [[ ! -f "$LINEUP_CACHE" ]] || [[ ! -s "$LINEUP_CACHE" ]]; then
    echo -e "\n${YELLOW}⚠️  No lineups collected from processed markets${RESET}"
    echo -e "${CYAN}💡 This may be normal if markets failed or returned no lineups${RESET}"
    return 1
  fi
  
  return 0
}

process_and_deduplicate_lineups() {
  echo -e "${CYAN}📊 Processing and deduplicating TV lineups...${RESET}" >&2
  local pre_dedup_lineups=$(wc -l < "$LINEUP_CACHE")

  # Process lineups more safely to avoid jq indexing errors
  sort -u "$LINEUP_CACHE" 2>/dev/null | while IFS= read -r line; do
    echo "$line" | jq -r '.lineupId // empty' 2>/dev/null
  done | grep -v '^$' | sort -u > cache/unique_lineups.txt

  local post_dedup_lineups=$(wc -l < cache/unique_lineups.txt)
  local dup_lineups_removed=$((pre_dedup_lineups - post_dedup_lineups))
  
  echo -e "${CYAN}📋 Lineups before dedup: $pre_dedup_lineups${RESET}" >&2
  echo -e "${CYAN}📋 Lineups after dedup: $post_dedup_lineups${RESET}" >&2
  echo -e "${GREEN}✅ Duplicate lineups removed: $dup_lineups_removed${RESET}" >&2
  
  # Return deduplication stats as space-separated values - STDOUT ONLY
  echo "$dup_lineups_removed $post_dedup_lineups"
}

fetch_stations_from_lineups() {
  local force_refresh="$1"
  local markets_to_process=("${@:2}")  # Remaining arguments are markets array
  
  echo -e "${CYAN}📡 Processing lineups with base cache and user cache awareness...${RESET}" >&2
  local lineups_processed=0
  local lineups_failed=0
  local lineups_skipped_base=0
  local lineups_skipped_user=0
  local total_lineups=$(wc -l < cache/unique_lineups.txt)

  while read LINEUP; do
    # Skip empty lines
    [[ -z "$LINEUP" ]] && continue
    
    # SMART SKIPPING LOGIC
    local skip_reason=""
    local should_skip=false
    
    # Check 1: Is this lineup covered by base cache stations?
    if [[ "$force_refresh" != "true" ]] && check_lineup_in_base_cache "$LINEUP"; then
      skip_reason="base cache"
      should_skip=true
      ((lineups_skipped_base++))
    # Check 2: Have we already cached this lineup in user cache?
    elif [[ "$force_refresh" != "true" ]] && is_lineup_cached "$LINEUP"; then
      skip_reason="user cache"
      should_skip=true
      ((lineups_skipped_user++))
    fi
    
    if [ "$should_skip" = true ]; then
      echo -e "${YELLOW}⏭️  Skipping lineup $LINEUP (covered by $skip_reason)${RESET}" >&2
      continue
    fi
    
    # Process this lineup (existing logic)
    ((lineups_processed++))
    local station_file="$STATION_CACHE_DIR/${LINEUP}.json"
    
    echo -e "${CYAN}📡 [$lineups_processed/$total_lineups] Processing lineup $LINEUP${RESET}" >&2
    
    # API call with enhanced error handling (existing code)
    local station_api_url="$CHANNELS_URL/dvr/guide/stations/$LINEUP"
    
    local curl_response
    curl_response=$(curl -s --connect-timeout $STANDARD_TIMEOUT --max-time $MAX_OPERATION_TIME "$station_api_url" 2>/dev/null)
    local curl_exit_code=$?
    
    if [[ $curl_exit_code -ne 0 ]]; then
      echo -e "${RED}❌ API Error for lineup $LINEUP: Curl failed with code $curl_exit_code${RESET}" >&2
      ((lineups_failed++))
      record_lineup_processed "$LINEUP" "UNK" "UNK" 0
      continue
    fi
    
    echo "$curl_response" > "$station_file"
    
    # Find which market this lineup belongs to for state tracking
    local country_code=""
    local source_zip=""
    for market in "${markets_to_process[@]}"; do
      IFS=, read -r COUNTRY ZIP <<< "$market"
      if grep -q "\"lineupId\":\"$LINEUP\"" "cache/last_raw_${COUNTRY}_${ZIP}.json" 2>/dev/null; then
        country_code="$COUNTRY"
        source_zip="$ZIP"
        break
      fi
    done
    
    # Count stations and record lineup processing
    local stations_found=0
    if [ -f "$station_file" ] && echo "$curl_response" | jq empty 2>/dev/null; then
      stations_found=$(jq 'length' "$station_file" 2>/dev/null || echo "0")
      echo -e "${GREEN}✅ Found $stations_found stations${RESET}" >&2
    else
      echo -e "${RED}❌ Invalid JSON response for lineup $LINEUP${RESET}" >&2
      ((lineups_failed++))
    fi
    
    record_lineup_processed "$LINEUP" "$country_code" "$source_zip" "$stations_found"
    
  done < cache/unique_lineups.txt

  # Show enhanced lineup processing summary - ALL TO STDERR
  echo -e "\n${BOLD}${GREEN}✅ Smart Lineup Processing Summary:${RESET}" >&2
  echo -e "${GREEN}Lineups processed: $lineups_processed${RESET}" >&2
  echo -e "${YELLOW}Lineups skipped (base cache): $lineups_skipped_base${RESET}" >&2
  echo -e "${YELLOW}Lineups skipped (user cache): $lineups_skipped_user${RESET}" >&2
  if [[ $lineups_failed -gt 0 ]]; then
    echo -e "${RED}Lineups failed: $lineups_failed${RESET}" >&2
  fi
  echo -e "${CYAN}Total efficiency gain: $((lineups_skipped_base + lineups_skipped_user)) fewer API calls${RESET}" >&2

  # Early exit if no stations were collected
  if [ "$lineups_processed" -eq 0 ]; then
    echo -e "\n${YELLOW}⚠️  No new lineups processed${RESET}" >&2
    echo -e "${CYAN}💡 All lineups may have been previously cached${RESET}" >&2
    return 1
  fi
  
  # Return stats as space-separated values - STDOUT ONLY: processed failed skipped_base skipped_user
  echo "$lineups_processed $lineups_failed $lineups_skipped_base $lineups_skipped_user"
  return 0
}

inject_metadata_and_process_stations() {
  local markets_to_process=("$@")
  
  echo -e "${CYAN}🔄 Processing stations and injecting country codes...${RESET}" >&2
  local pre_dedup_stations=0
  local temp_stations_file="$CACHE_DIR/temp_incremental_stations_$(date +%s).json"
  > "$temp_stations_file.tmp"

  # Process each lineup file individually to inject lineup tracing
  while read LINEUP; do
    local station_file="$STATION_CACHE_DIR/${LINEUP}.json"
    if [ -f "$station_file" ]; then
      # Determine country code from lineup ID or market lookup
      local country_code=""
      
      # First try to find country by checking processed markets
      for market in "${markets_to_process[@]}"; do
        IFS=, read -r COUNTRY ZIP <<< "$market"
        if grep -q "\"lineupId\":\"$LINEUP\"" "cache/last_raw_${COUNTRY}_${ZIP}.json" 2>/dev/null; then
          country_code="$COUNTRY"
          break
        fi
      done
      
      # Fallback: extract from lineup ID pattern
      if [[ -z "$country_code" ]]; then
        case "$LINEUP" in
          *USA*|*US-*) country_code="USA" ;;
          *CAN*|*CA-*) country_code="CAN" ;;
          *GBR*|*GB-*|*UK-*) country_code="GBR" ;;
          *DEU*|*DE-*) country_code="DEU" ;;
          *FRA*|*FR-*) country_code="FRA" ;;
          *) country_code="UNK" ;;
        esac
      fi
      
      # Count stations before processing
      if jq empty "$station_file" 2>/dev/null; then
        local lineup_count=$(jq 'length' "$station_file" 2>/dev/null || echo "0")
        pre_dedup_stations=$((pre_dedup_stations + lineup_count))
        
        # Extract lineup metadata directly from raw files
        local lineup_name=""
        local lineup_location=""
        local lineup_type=""
        
        # Find the raw file that contains this lineup
        for raw_file in cache/last_raw_*.json; do
          if [[ -f "$raw_file" ]] && grep -q "\"$LINEUP\"" "$raw_file" 2>/dev/null; then
            lineup_name=$(jq -r --arg id "$LINEUP" '.[] | select(.lineupId == $id) | .name // ""' "$raw_file" 2>/dev/null | head -1)
            lineup_location=$(jq -r --arg id "$LINEUP" '.[] | select(.lineupId == $id) | .location // ""' "$raw_file" 2>/dev/null | head -1)
            lineup_type=$(jq -r --arg id "$LINEUP" '.[] | select(.lineupId == $id) | .type // ""' "$raw_file" 2>/dev/null | head -1)
            break
          fi
        done
        
        echo -e "${CYAN}📋 Processing lineup $LINEUP (${lineup_name:-"Unknown"})${RESET}" >&2
        
        # Inject rich lineup data into each station
        jq --arg country "$country_code" \
           --arg source "user" \
           --arg lineup_id "$LINEUP" \
           --arg lineup_name "$lineup_name" \
           --arg lineup_location "$lineup_location" \
           --arg lineup_type "$lineup_type" \
           -c 'map(. + {
             country: $country,
             source: $source,
             originLineupId: $lineup_id,
             originLineupName: $lineup_name,
             originLocation: $lineup_location,
             originType: $lineup_type
           })[]' "$station_file" >> "$temp_stations_file.tmp"
      fi
    fi
  done < cache/unique_lineups.txt

  # Deduplicate and organize clean format stations with rich lineup metadata
  if [ -s "$temp_stations_file.tmp" ]; then
    jq -s '
      group_by(.stationId) | 
      map(
        .[0] as $first |
        if length == 1 then
          # Single station - convert to clean format with rich metadata
          $first + {
            availableIn: [$first.country],
            multiCountry: false,
            lineupTracing: [{
              lineupId: $first.originLineupId,
              lineupName: ($first.originLineupName // ""),
              country: $first.country,
              location: ($first.originLocation // ""),
              type: ($first.originType // ""),
              discoveredOrder: 1,
              isPrimary: true
            }]
          } | del(.country, .originLineupId, .originLineupName, .originLocation, .originType)
        else
          # Multiple stations - merge countries and rich lineup tracing
          $first + {
            availableIn: ([.[] | .country] | unique | sort),
            multiCountry: ([.[] | .country] | unique | length > 1),
            lineupTracing: (
              [.[] | {
                lineupId: .originLineupId,
                lineupName: (.originLineupName // ""),
                country: .country,
                location: (.originLocation // ""),
                type: (.originType // ""),
                discoveredOrder: 0,
                isPrimary: false
              }] |
              unique_by(.country) |
              to_entries |
              map(.value + {
                discoveredOrder: (.key + 1),
                isPrimary: (.key == 0)
              })
            )
          } | del(.country, .originLineupId, .originLineupName, .originLocation, .originType)
        end
      ) |
      sort_by(.name // "")
    ' "$temp_stations_file.tmp" > "$temp_stations_file"
    
    local post_dedup_stations=$(jq 'length' "$temp_stations_file" 2>/dev/null || echo "0")
  else
    echo '[]' > "$temp_stations_file"
    local post_dedup_stations=0
  fi

  # Clean up intermediate temp file
  rm -f "$temp_stations_file.tmp"

  local dup_stations_removed=$((pre_dedup_stations - post_dedup_stations))
  
  echo -e "${CYAN}📋 New stations before dedup: $pre_dedup_stations${RESET}" >&2
  echo -e "${CYAN}📋 New stations after dedup: $post_dedup_stations${RESET}" >&2
  echo -e "${GREEN}✅ Duplicate stations removed: $dup_stations_removed${RESET}" >&2

  # Early exit if no new stations to add
  if [ "$post_dedup_stations" -eq 0 ]; then
    echo -e "\n${YELLOW}⚠️  No new stations to add to cache${RESET}" >&2
    echo -e "${CYAN}💡 Processed markets may have contained duplicate stations${RESET}" >&2
    rm -f "$temp_stations_file"
    return 1
  fi
  
  # Return temp file path and stats - STDOUT ONLY: filepath pre_dedup post_dedup dup_removed
  echo "$temp_stations_file $pre_dedup_stations $post_dedup_stations $dup_stations_removed"
  return 0
}

enhance_stations() {
  local start_time="$1"
  local stations_file="$2"  # The file to enhance (passed as parameter)
  
  echo -e "${CYAN}🔄 Starting station data enhancement process...${RESET}" >&2
  local tmp_json="$CACHE_DIR/enhancement_tmp_$(date +%s).json"
  > "$tmp_json"

  # Check if stations file exists and has content
  if [ ! -f "$stations_file" ]; then
    echo -e "${RED}❌ Stations file not found: $stations_file${RESET}" >&2
    echo "0"  # Return 0 enhanced stations
    return 1
  fi

  local total_stations
  total_stations=$(jq 'length' "$stations_file" 2>/dev/null)
  if [ -z "$total_stations" ] || [ "$total_stations" -eq 0 ]; then
    echo -e "${YELLOW}⚠️  No stations found in file: $stations_file${RESET}" >&2
    echo -e "${CYAN}💡 This suggests the station collection process didn't work properly${RESET}" >&2
    echo "0"  # Return 0 enhanced stations
    return 0
  fi

  mapfile -t stations < <(jq -c '.[]' "$stations_file")
  local actual_stations=${#stations[@]}
  local enhanced_from_api=0

  echo -e "${CYAN}📊 Processing $actual_stations stations for enhancement...${RESET}" >&2
  
  for ((i = 0; i < actual_stations; i++)); do
    local station="${stations[$i]}"
    local current=$((i + 1))
    local percent=$((current * 100 / actual_stations))
    
    # Show progress bar BEFORE processing (only if more than 10 stations)
    if [ "$actual_stations" -gt 10 ]; then
      show_progress_bar "$current" "$actual_stations" "$percent" "$start_time"
    fi

    local callSign=$(echo "$station" | jq -r '.callSign // empty')
    local name=$(echo "$station" | jq -r '.name // empty')
    
    # Only enhance if station has callsign but missing name AND server is configured
    if [[ -n "$callSign" && "$callSign" != "null" && ( -z "$name" || "$name" == "null" ) && -n "${CHANNELS_URL:-}" ]]; then
      local api_response=$(curl -s --connect-timeout $QUICK_TIMEOUT "$CHANNELS_URL/tms/stations/$callSign" 2>/dev/null)
      local current_station_id=$(echo "$station" | jq -r '.stationId')
      local station_info=$(echo "$api_response" | jq -c --arg id "$current_station_id" '.[] | select(.stationId == $id) // empty' 2>/dev/null)
      
      if [[ -n "$station_info" && "$station_info" != "null" && "$station_info" != "{}" ]]; then
        if echo "$station_info" | jq empty 2>/dev/null; then
          # Selectively merge only specific fields to avoid type conflicts
          local enhanced_name=$(echo "$station_info" | jq -r '.name // ""')
          if [[ -n "$enhanced_name" && "$enhanced_name" != "null" ]]; then
            station=$(echo "$station" | jq --arg new_name "$enhanced_name" '. + {name: $new_name}')
            ((enhanced_from_api++))
          fi
        fi
      fi
    fi

    echo "$station" >> "$tmp_json"
  done
  
  # Clear progress line only if it was shown
  if [ "$actual_stations" -gt 10 ]; then
    echo >&2
  fi
  
  echo -e "${GREEN}✅ Station enhancement completed successfully${RESET}" >&2
  echo -e "${CYAN}📊 Enhanced $enhanced_from_api stations via API lookup${RESET}" >&2
  
  # File operation feedback
  echo -e "${CYAN}💾 Finalizing enhanced station data...${RESET}" >&2
  mv "$tmp_json" "$stations_file"
  
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✅ Enhanced station data saved successfully${RESET}" >&2
  else
    echo -e "${RED}❌ Station Enhancement: Failed to save enhanced data${RESET}" >&2
    echo -e "${CYAN}💡 Check disk space and file permissions${RESET}" >&2
  fi

  # Return only the API enhancement count (clean number only)
  echo "$enhanced_from_api"
}

finalize_user_cache_update() {
  local temp_stations_file="$1"
  local start_time="$2"
  local post_dedup_stations="$3"
  local dup_stations_removed="$4"
  local will_process="$5"
  local already_cached="$6"
  local base_cache_skipped="$7"
  local enhanced_count="$8"
  local lineups_skipped_base="$9"
  local lineups_skipped_user="${10}"
  
  # APPEND to existing USER cache
  echo -e "\n${BOLD}${BLUE}Phase 7: Incremental User Cache Integration${RESET}"
  echo -e "${CYAN}💾 Appending new stations to existing user cache...${RESET}"
  
  if add_stations_to_user_cache "$temp_stations_file"; then
    echo -e "${GREEN}✅ User cache updated successfully${RESET}"
    echo -e "${CYAN}📊 Added $post_dedup_stations new stations to user cache${RESET}"
  else
    echo -e "${RED}❌ Failed to update user cache${RESET}"
    rm -f "$temp_stations_file"
    return 1
  fi

  # Calculate duration and show summary
  local end_time=$(date +%s)
  local duration=$((end_time - ${start_time%%.*}))
  local human_duration=$(printf '%02dh %02dm %02ds' $((duration/3600)) $((duration%3600/60)) $((duration%60)))

  # Show incremental summary
  show_incremental_caching_summary "$will_process" "$already_cached" "$base_cache_skipped" "$post_dedup_stations" "$dup_stations_removed" "$human_duration" "$enhanced_count" "$lineups_skipped_base" "$lineups_skipped_user"
  
  # Rebuild combined cache as final step
  if [ "$post_dedup_stations" -gt 0 ]; then
    echo -e "\n${BOLD}${BLUE}Final Step: Rebuilding Combined Cache${RESET}"
    echo -e "${CYAN}🔄 Updating combined cache with new stations...${RESET}"
    
    # Force invalidate and rebuild
    invalidate_combined_cache
    
    if build_combined_cache_with_progress >/dev/null 2>&1; then
      echo -e "${GREEN}✅ Combined cache rebuilt successfully${RESET}"
    else
      echo -e "${YELLOW}⚠️  Combined cache rebuild failed - will rebuild on next search${RESET}"
    fi
  else
    echo -e "\n${CYAN}💡 No new stations added - combined cache unchanged${RESET}"
  fi

  # Clean up temporary files
  rm -f "$temp_stations_file"
  
  return 0
}

# ============================================================================
# USER CACHING - ORCHESTRATOR FUNCTION
# ============================================================================

perform_user_caching() {
  local force_refresh="${1:-false}"  # Optional parameter: false=incremental, true=complete refresh
  
  # PHASE 0: VALIDATE PREREQUISITES AND INITIALIZE CACHING ENVIRONMENT
  if ! validate_caching_prerequisites "$force_refresh"; then
    return 1
  fi
  
  # PHASE 1: ANALYZE WHICH MARKETS NNEED PROCESSING
  echo -e "\n${CYAN}🔍 Analyzing markets for processing...${RESET}"
  local markets_to_process_output
  markets_to_process_output=$(analyze_markets_for_processing "$force_refresh")
  local analysis_result=$?
  
  # Early exit if no processing needed
  if [[ $analysis_result -ne 0 ]]; then
    return 0
  fi
  
  # Convert output back to array
  local markets_to_process=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && markets_to_process+=("$line")
  done <<< "$markets_to_process_output"
  
  local will_process=${#markets_to_process[@]}
  
  # Setup caching environment and get start time
  local start_time
  start_time=$(setup_caching_environment)

  # PHASE 2: MARKET LINEUP DISCOVERY
  echo -e "\n${BOLD}${BLUE}Phase 1: Market Lineup Discovery${RESET}"
  if ! process_markets_for_lineups "${markets_to_process[@]}"; then
    return 0  # No lineups collected, but not an error
  fi

  # PHASE 3: LINEUP PROCESSING & DEDUPLICATION
  echo -e "\n${BOLD}${BLUE}Phase 2: Lineup Processing & Deduplication${RESET}"
  local dedup_stats
  dedup_stats=$(process_and_deduplicate_lineups)
  local dup_lineups_removed=$(echo "$dedup_stats" | cut -d' ' -f1)
  local post_dedup_lineups=$(echo "$dedup_stats" | cut -d' ' -f2)

  # PHASE 4: SMART LINEUP PROCESSING
  echo -e "\n${BOLD}${BLUE}Phase 3: Smart Lineup Processing${RESET}"
  local lineup_stats
  lineup_stats=$(fetch_stations_from_lineups "$force_refresh" "${markets_to_process[@]}")
  local fetch_result=$?
  
  if [[ $fetch_result -ne 0 ]]; then
    return 0  # No new lineups processed, but not an error
  fi
  
  # Parse lineup processing stats
  local lineups_processed=$(echo "$lineup_stats" | cut -d' ' -f1)
  local lineups_failed=$(echo "$lineup_stats" | cut -d' ' -f2)
  local lineups_skipped_base=$(echo "$lineup_stats" | cut -d' ' -f3)
  local lineups_skipped_user=$(echo "$lineup_stats" | cut -d' ' -f4)

  # PHASE 5: STATION PROCESSING AND METADATA INJECTION
  echo -e "\n${BOLD}${BLUE}Phase 4: Station Processing & Country Assignment${RESET}"
  local station_stats
  station_stats=$(inject_metadata_and_process_stations "${markets_to_process[@]}")
  local inject_result=$?
  
  if [[ $inject_result -ne 0 ]]; then
    return 0  # No new stations to add, but not an error
  fi
  
  # Parse station processing stats
  local temp_stations_file=$(echo "$station_stats" | cut -d' ' -f1)
  local pre_dedup_stations=$(echo "$station_stats" | cut -d' ' -f2)
  local post_dedup_stations=$(echo "$station_stats" | cut -d' ' -f3)
  local dup_stations_removed=$(echo "$station_stats" | cut -d' ' -f4)

  # PHASE 6: STATION DATA ENHANCEMENT (NAME INJECTION FROM API)
  echo -e "\n${BOLD}${BLUE}Phase 6: Station Data Enhancement${RESET}"
  echo -e "${CYAN}🔄 Enhancing station information...${RESET}"
  local enhanced_count
  enhanced_count=$(enhance_stations "$(date +%s.%N)" "$temp_stations_file")

  # Get analysis stats for summary (these were calculated earlier but need to be preserved)
  local already_cached=0
  local base_cache_skipped=0
  
  # Re-analyze to get exact counts for summary (quick pass)
  while IFS=, read -r country zip; do
    [[ "$country" == "Country" ]] && continue
    if [[ "$force_refresh" != "true" ]]; then
      if is_market_cached "$country" "$zip"; then
        ((already_cached++))
      elif check_market_in_base_cache "$country" "$zip"; then
        ((base_cache_skipped++))
      fi
    fi
  done < "$CSV_FILE"

  # PHASE 7: FINALIZE USER CACHE UPDATE
  finalize_user_cache_update "$temp_stations_file" "$start_time" "$post_dedup_stations" "$dup_stations_removed" "$will_process" "$already_cached" "$base_cache_skipped" "$enhanced_count" "$lineups_skipped_base" "$lineups_skipped_user"
}