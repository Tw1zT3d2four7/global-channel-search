# Global Station Search

A comprehensive television station search tool that (optionally) integrates with Channels DVR and Dispatcharr to provide enhanced station discovery and automated Dispatcharr field population.

## Version 2.0.3
**Patch (2.0.3)**
- Definitive fix for Emby integration

**Patch (2.0.1)**
- Fixed Emby API calls
- Fixed module loading order/dependency chain 

**MAJOR RELEASE (2.0.0)**
- All data from any previous version must be deleted as it is no longer backward compatible
- Added multi-country filtering support and lineup tracing when caching is performed
- Emby integration to populate necessary lineupIds for all channels in m3u playlist
- Significant enhacnements to codebase

**Previous Release (1.4.5) - 2025-06-04**
- **Enhanced Authentication** - Moved all Dispatcharr auth functions to `lib/core/auth.sh` for background token refresh without user interaction
- **API Consolidation** - Centralized all API calls in `lib/core/api.sh`
- **Improved Channel Selection** - Added option to select specific channels from station ID scan results
- **Auto-Update System** - New `lib/features/update.sh` module with startup update checks and user-configurable intervals

**Previous Patch (1.4.2) - 2025-06-03**
- Removed unused channel parsing fields (language, confidence) that were breaking core functionality

**MAJOR RELEASE (1.4.0) - 2025-06-02**
- **New Modular Framework** - Complete architecture overhaul with lib/ directory structure
- **Major Code Reduction** - Eliminated 1000+ lines of duplicate code
- Fixed broken Channels DVR API search functionality
- Resolved critical user cache building issues
- More consistent UI/UX patterns across all menus
- Advanced channel name regex parsing

**Previous Release (1.3.2):**
- Fixed broken Dispatcharr token refresh logic
- Added resume state handling to Dispatcharr all channels workflow
- Users can now resume from last processed channel, start fresh, or pick specific channel number
- Resume state persists between script runs via configuration file

**1.3.1:**
- **Enhanced Dispatcharr Workflows** - Significantly improved efficiency and user experience
- **Streamlined Channel Processing** - Removed disruptive prompts for smoother batch operations
- **Improved Channel Name Parsing** - Enhanced regex logic with helper functions for better auto-matching
- **Consistent Channel Sorting** - Fixed sorting across all Dispatcharr workflows (lowest to highest channel number)

## Features

### No Setup Required
- **Comprehensive Base Cache** - Thousands of pre-loaded stations from USA, Canada, and UK, including streaming channels
- **Search immediately**
- **Optional Expansion** - Add custom markets only if you need additional coverage

### 🔍 **Powerful Search**
- **Local Database Search** - Searching happens locally, without API calls
- **Direct API Search** - Real-time queries to Channels DVR server (requires Channels DVR integration)
- **Smart Filtering** - Filter by resolution (SDTV, HDTV, UHDTV) and country
- **Logo Display** - Visual station logos (requires viu and a compatible terminal)
- **Advanced Channel Name Parsing** - Intelligent channel name analysis with auto-detection of country, resolution, and language
- **Reverse Station ID Lookup**

### 🔧 **Dispatcharr Integration**
- **Automated Station ID Matching** - Interactive matching for channels missing station IDs
- **Complete Field Population** - Automatically populate channel name, TVG-ID, station ID, and logos
- **Visual Comparison** - See current vs. proposed logos side-by-side
- **Batch Processing Modes** - Choose immediate apply or queue for review
- **Automatic Data Replacement** - Mass update all channels with station IDs
- **Resume Support** - Continue processing from where you left off
- **Enhanced Authentication** - Background token management without workflow interruption

### 🌍 **Market Management**
- **Granular Control** - Add specific ZIP codes/postal codes for any country
- **Smart Caching** - Incremental updates only process new markets
- **Base Cache Awareness** - Automatically skips markets already covered
- **Force Refresh** - Override base cache when you need specific market processing
- **Enhanced Validation** - Country and postal code normalization and validation

### 🔄 **Auto-Update System**
- **Startup Checks** - Optional update checking when script starts
- **Configurable Intervals** - Set update check frequency
- **In-Script Management** - Update directly from within the application
- **Background Processing** - Non-intrusive update notifications

## Requirements

### Required
- **jq** - JSON processing
- **curl** - HTTP requests
- **bash 4.0+** - Shell environment

### Optional
- **viu** - Logo previews and display
- **bc** - Progress calculations during caching
- **Channels DVR server** - For Direct API Search and adding channels using user cache
- **Dispatcharr** - For automated channel field population

## Installation

1. **Download the script:**
```bash
git clone https://github.com/Tw1zT3d2four7/global-channel-search.git
cd global-channel-search
```

2. **Make executable:**
```bash
chmod +x globalstationsearch.sh
```

3. **Install dependencies:**
```bash
# Ubuntu/Debian
sudo apt-get install jq curl

# macOS
brew install jq curl

# Optional: Logo preview support
# Install viu - https://github.com/atanunq/viu
```

## Quick Start

### Option 1: Immediate Use (Recommended)
```bash
./globalstationsearch.sh
```
### Option 2: For the inital install of the Docker Version & re-starting the Docker Container once you have exited the terminal/console.
``` ./run-global-channel-search.sh ```
### Make sure that when your ready to exit the terminal/console that you select "Q" to quit prior to closing the terminal/console window.
### So that it restarts when you want to use the container again.

Select **"Search Local Database"** - works immediately with thousands of pre-loaded stations!

### Option 2: Command Line Help
```bash
./globalstationsearch.sh --help           # Usage help
./globalstationsearch.sh --version        # Version number
./globalstationsearch.sh --version-info   # Detailed version info
```

## Contributing

This script is designed to be self-contained and user-friendly. For issues or suggestions find me on the Dispatcharr Discord.

## Version History

- **1.4.5** - Enhanced authentication, API consolidation, improved channel selection, auto-update system
- **1.4.2** - Channel parsing fixes and stability improvements
- **1.4.0** - Major modular architecture overhaul, enhanced stability, improved workflows
- **1.3.2** - Dispatcharr token refresh fixes, resume support
- **1.3.1** - Enhanced Dispatcharr workflows, improved parsing, better navigation
- **1.3.0** - Enhanced Dispatcharr integration, logo workflow, menu consistency
- **1.2.0** - Major base cache overhaul, better user cache handling  
- **1.1.0** - Added comprehensive local base cache
- **1.0.0** - Initial release with Dispatcharr integration
