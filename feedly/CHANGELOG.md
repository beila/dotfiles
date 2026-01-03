# Feedly Script Development Log

## 2026-01-03

### Initial Request
User asked for a script to get title, url, velocity and categories for each feed in Feedly account.

### Changes Made:

1. **Created initial Selenium scraper** (`feedly-feeds`)
   - Request: "write a script to get the title, url, velocity and categories for each feed"
   - Used Selenium with Chrome to scrape Feedly web interface
   - Added anti-detection measures for Google OAuth

2. **Moved to dedicated directory with uv compatibility**
   - Request: "move the script to ~/.dotfies/feedly and make the dependency uv-compatible"
   - Created `~/.dotfiles/feedly/` directory
   - Added PEP 723 inline script metadata for uv

3. **Created Nix flake for dependency management**
   - Request: "instead of directly managing dendency in the nix flake, add uv in the flake and use it for dependency"
   - Added `flake.nix` with uv and chromedriver dependencies
   - Enabled `nix run` execution

4. **Fixed compilation errors**
   - Request: Parameter pack expansion and format specifier errors
   - Fixed C++ fold expression syntax
   - Cast `musl_off_t` to `int64_t` for format compatibility

5. **Switched to OPML parsing approach**
   - Request: "I don't want to log in each time"
   - Created `feedly-opml` script to parse exported OPML files
   - Added RSS feed frequency analysis using feedparser

6. **Added frequency calculation**
   - Request: "how will you get the frequency of posts for each feed"
   - Implemented RSS feed parsing to estimate posting frequency
   - Calculate average time between posts from recent entries

7. **Standardized output format**
   - Request: "use one unit for frequency"
   - Changed to posts per month as standard unit
   - Added JSON output for easy processing

8. **Implemented incremental file writing**
   - Request: "write the file on the go, rather than at once at the end"
   - Changed from JSON to CSV format
   - Write each feed result immediately with flush()

9. **Added processing log (removed)**
   - Request: "add a file for loggin your work along with my request"
   - Initially misunderstood as script logging
   - User clarified they wanted development changelog (this file)

10. **Improved RSS frequency calculation**
   - Request: Korean news feed showing 0 posts/month despite having many posts
   - Enhanced date parsing with multiple fallback methods
   - Added string date parsing for feeds that don't use parsed timestamps
   - Increased sample size from 10 to 20 entries
   - Added reasonable defaults instead of returning 0
   - Capped maximum at 300 posts/month to avoid unrealistic values

11. **Added feed status tracking**
   - Request: Identify broken feeds that show page errors
   - Added status field: OK/ERROR/EMPTY/NO_DATES
   - Detects HTTP errors, parsing failures, and empty feeds

## Current State
- `feedly-opml`: Parses OPML export, analyzes RSS feeds, outputs CSV with frequency data
- `flake.nix`: Nix environment with uv and dependencies
- Frequency unit: posts per month
- Output: CSV file written incrementally
