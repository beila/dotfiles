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

12. **Changed to posts per year with recent data only**
   - Request: Fix feeds with high frequency based on old posts
   - Changed frequency to posts per year (more meaningful)
   - Only count posts from last 365 days
   - Added last_updated date field
   - Skip feeds processed within last week
   - Added "OLD" status for feeds with no recent posts

13. **Switched from CSV to JSON for better updates**
   - Request: CSV not ideal for in-place updates
   - Changed output format to JSON
   - Added processed_date field to track when each feed was last checked
   - Enables selective updates of individual feeds

14. **Switched to JSONL for 1000+ feeds**
   - Request: JSON not good for incremental updates with 1000+ feeds
   - Changed to JSONL (JSON Lines) format - one JSON object per line
   - Enables true incremental updates by appending new entries
   - Properly implemented week-based skipping logic
   - Much more memory efficient for large datasets

15. **Fixed Korean encoding issues**
   - Request: Korean text broken in output file
   - Added explicit UTF-8 encoding for file operations
   - Used ensure_ascii=False in JSON dumps to preserve Korean characters

16. **Fixed multiple categories support**
   - Request: Feeds can be in multiple categories, not just one
   - Updated OPML parsing to walk up the tree and collect all parent categories
   - Changed from single 'category' field to 'categories' array
   - Categories are ordered from top-level to most specific

17. **Added retry failed feeds option**
   - Request: Add option to retry feeds with non-OK status
   - Added --retry-failed flag to only process ERROR/EMPTY/OLD feeds
   - Skips week-based filtering when retrying failed feeds
   - Loads failed feeds from existing JSONL output

18. **Fixed duplicate entries on retry**
   - Request: Replace feeds instead of duplicating when retrying
   - Changed from append mode to update-in-place
   - Loads all existing data, updates entries, rewrites entire file
   - Prevents duplicate entries when using --retry-failed

19. **Added parallel processing**
   - Request: Parallelize network access for faster processing
   - Added ThreadPoolExecutor with 10 concurrent workers
   - Thread-safe file updates with locking
   - Significantly faster processing of large feed lists

20. **Added retry all feeds option**
   - Request: Add option to retry all feeds regardless of status
   - Added --retry-all flag to reprocess all feeds
   - Ignores week-based filtering when using --retry-all
   - Useful for refreshing all frequency data

21. **Improved frequency calculation algorithm**
   - Request: "The Independent" showing 100 posts/year vs Feedly's 2338 posts/week
   - **MAJOR CHANGE**: Switched from counting RSS entries to interval-based estimation
   - Algorithm: Calculate average time between posts, extrapolate to annual frequency
   - Formula: `posts_per_year = (24 / avg_interval_hours) * 365`
   - Much more accurate for low-to-medium frequency feeds
   - Added --test-feed option for debugging individual feeds

22. **Created OPML categorization script**
   - Request: Convert JSONL to categorized OPML with working feeds only
   - Created `jsonl-to-opml` script following categorise-feeds.md rules
   - Groups feeds into categories with ~6 posts/day each
   - Caps high-frequency feeds at 2 posts/day for calculation
   - Categories named for sorting: `{number:02d}-feeds-{min_frequency}py`

23. **Added category exclusion feature**
   - Request: Exclude feeds from "다읽기" and "뉴스레터" categories
   - Modified jsonl-to-opml to filter out specified categories
   - Excluded 130 feeds, resulting in 400 working feeds
   - Shows exclusion count in output for transparency

24. **Implemented two-phase processing architecture**
   - Request: Separate OPML parsing from feed fetching for better reliability
   - Added --populate-only flag to feedly-opml for OPML parsing phase
   - Added --fetch-only flag for frequency data collection phase
   - Enables debugging and partial processing of large feed lists
   - Improved error handling by separating concerns

25. **Fixed category parsing bugs**
   - Request: Missing feeds from "다읽기" category (66 feeds missing)
   - Fixed parent-child relationship traversal in OPML parsing
   - Proper exclusion of feeds (xmlUrl check) from category names
   - Restored missing feeds, now showing correct counts (176 feeds in "다읽기")

26. **Increased parallel processing workers**
   - Request: Speed up processing for large feed collections
   - Increased concurrent workers from 10 to 20
   - Improved throughput for 763 feed processing
   - Maintained thread-safe file operations

27. **Fixed jsonl-to-opml to preserve all original categories**
   - Request: Categorized OPML should have 1,263 original + new category feeds
   - **MAJOR FIX**: Script was only preserving "다읽기" and "뉴스레터" categories
   - Modified to preserve ALL 77 original categories from OPML (1,263 feeds total)
   - Final output: 1,825 feeds (360 working + 202 unprocessed + 1,263 original)
   - Maintains complete feed collection while adding frequency-based organization

28. **Added JSONL cleanup functionality**
   - Request: Remove feeds from JSONL that are no longer in OPML
   - Enhanced --populate-only to sync JSONL with current OPML structure
   - Removes orphaned feeds no longer in OPML
   - Updates categories for feeds moved between OPML categories
   - Preserves frequency analysis data while maintaining OPML synchronization

## Current State
- `feedly-opml`: Parses OPML export, analyzes RSS feeds with improved interval-based frequency calculation, supports --retry-failed/--retry-all/--test-feed/--populate-only/--fetch-only options, includes JSONL cleanup
- `jsonl-to-opml`: Converts JSONL to categorized OPML preserving ALL original categories plus new frequency-based categories
- `flake.nix`: Nix environment with uv and dependencies
- Frequency calculation: Interval-based estimation using average time between posts (posts per year)
- Output: JSONL format with thread-safe parallel processing (20 workers)
- Categorization: 40 frequency-based + 77 original categories, 1,825 total feeds preserving complete collection
- Processing: Two-phase architecture with OPML sync, parallel processing, incremental updates, Korean text support
