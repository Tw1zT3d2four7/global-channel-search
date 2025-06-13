# Global Station Search

A comprehensive television station search tool that (optionally) integrates with Channels DVR and Dispatcharr to provide enhanced station discovery and automated Dispatcharr field population.

## Version 2.1.0
**Patch (2.1.0)**
- Improved User Caching (resume from interruption, more efficient, fewer API calls)
- Significantly improved dispatcharr authentication and token management
- Continue process of code cleaning and reorganization
- New complete USA, CAN, GBR base databse

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
```bash
./run-global-channel-search.sh
```
### Make sure that when your ready to exit the terminal/console that you select "Q" to quit prior to closing the terminal/console window.
### So that it restarts when you want to use the container again and stays presist over re-starts.




Select **"Search Local Database"** - works immediately with thousands of pre-loaded stations!

### Option 3: Command Line Help
```bash
./globalstationsearch.sh --help           # Usage help
./globalstationsearch.sh --version        # Version number
./globalstationsearch.sh --version-info   # Detailed version info
```

## Contributing

This script is designed to be self-contained and user-friendly. For issues or suggestions find me on the Dispatcharr Discord.

## Version History
- **2.0.4** - Fix to Emby API calls and other bugfixes
- **2.0.0** - BREAKING RELEASE all data must be deleted, no longer backward compatible, added
multicountry, lineup tracing. Emby integration
- **1.4.5** - Enhanced authentication, API consolidation, improved channel selection, auto-update system
- **1.4.2** - Channel parsing fixes and stability improvements
- **1.4.0** - Major modular architecture overhaul, enhanced stability, improved workflows
- **1.3.2** - Dispatcharr token refresh fixes, resume support
- **1.3.1** - Enhanced Dispatcharr workflows, improved parsing, better navigation
- **1.3.0** - Enhanced Dispatcharr integration, logo workflow, menu consistency
- **1.2.0** - Major base cache overhaul, better user cache handling  
- **1.1.0** - Added comprehensive local base cache
- **1.0.0** - Initial release with Dispatcharr integration
