#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
KEYCHAIN_SERVICE="circleci-usage-script"
KEYCHAIN_ACCOUNT="api-key"
MERGE_FILES=true

# Parse command line arguments
INITIAL_ORG_ID=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -nomerge|--no-merge)
            MERGE_FILES=false
            shift
            ;;
        *)
            INITIAL_ORG_ID="$1"
            shift
            ;;
    esac
done

# Function to get API key from keychain
get_api_key() {
    security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w 2>/dev/null
}

# Function to save API key to keychain
save_api_key() {
    local api_key="$1"
    # Delete existing key if present
    security delete-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" 2>/dev/null
    # Add new key
    security add-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w "$api_key"
}

# Function to prompt for API key
prompt_for_api_key() {
    echo -e "${YELLOW}CircleCI API Key Required${NC}"
    echo "This script needs a CircleCI API key to access usage data."
    echo ""
    echo "To create an API key:"
    echo "  1. Go to https://app.circleci.com/settings/user/tokens"
    echo "  2. Click 'Create New Token'"
    echo "  3. Copy the token"
    echo ""
    read -sp "Enter your CircleCI API key: " api_key
    echo ""

    if [ -z "$api_key" ]; then
        echo -e "${RED}✗ No API key provided${NC}"
        exit 1
    fi

    # Validate key format (basic check)
    if [[ ! "$api_key" =~ ^CCIPAT_ ]]; then
        echo -e "${YELLOW}⚠ Warning: API key doesn't match expected format (should start with CCIPAT_)${NC}"
        read -p "Continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    echo -e "${CYAN}→ Saving API key to macOS Keychain...${NC}"
    if save_api_key "$api_key"; then
        echo -e "${GREEN}✓ API key saved securely${NC}"
        echo ""
    else
        echo -e "${RED}✗ Failed to save API key to keychain${NC}"
        echo "  The key will be used for this session only."
        echo ""
    fi

    echo "$api_key"
}

# Function to prompt for organization ID
prompt_for_org_id() {
    echo -e "${YELLOW}Enter Organization ID:${NC}" >&2
    read -p "Org ID: " org_id

    if [ -z "$org_id" ]; then
        echo -e "${RED}✗ No organization ID provided${NC}" >&2
        return 1
    fi

    echo "$org_id"
}

# Function to prompt for date range
prompt_for_date_range() {
    echo "" >&2
    echo -e "${YELLOW}Select Date Range:${NC}" >&2
    echo "" >&2
    echo "  [1] Default: Last 30 days" >&2
    echo "  [2] Custom date range" >&2
    echo "" >&2

    read -p "Enter choice (1 or 2) [default: 1]: " date_choice

    # Default to option 1 if empty
    if [ -z "$date_choice" ]; then
        date_choice="1"
    fi

    if [ "$date_choice" = "1" ]; then
        # Use default 30 days
        END_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        START_DATE=$(date -u -v-30d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "30 days ago" +"%Y-%m-%dT%H:%M:%SZ")
        echo -e "${GREEN}✓ Using default: Last 30 days${NC}" >&2
    elif [ "$date_choice" = "2" ]; then
        # Prompt for custom dates
        echo "" >&2
        echo -e "${CYAN}Enter dates in format: YYYY-MM-DD${NC}" >&2
        echo -e "${CYAN}Example: 2026-01-15${NC}" >&2
        echo "" >&2

        read -p "Start date (YYYY-MM-DD): " start_input
        read -p "End date (YYYY-MM-DD): " end_input

        # Validate date format
        if [[ ! "$start_input" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || [[ ! "$end_input" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
            echo -e "${RED}✗ Invalid date format. Please use YYYY-MM-DD${NC}" >&2
            return 1
        fi

        # Validate date range (max 31 days per CircleCI API)
        START_EPOCH=$(date -j -f "%Y-%m-%d" "$start_input" "+%s" 2>/dev/null || date -d "$start_input" "+%s" 2>/dev/null)
        END_EPOCH=$(date -j -f "%Y-%m-%d" "$end_input" "+%s" 2>/dev/null || date -d "$end_input" "+%s" 2>/dev/null)

        if [ -n "$START_EPOCH" ] && [ -n "$END_EPOCH" ]; then
            DAYS_DIFF=$(( (END_EPOCH - START_EPOCH) / 86400 ))

            if [ $DAYS_DIFF -lt 0 ]; then
                echo -e "${RED}✗ End date must be after start date${NC}" >&2
                return 1
            elif [ $DAYS_DIFF -gt 31 ]; then
                echo -e "${RED}✗ Date range cannot exceed 31 days (CircleCI API limit)${NC}" >&2
                echo "   Your range: $DAYS_DIFF days" >&2
                return 1
            fi
        fi

        START_DATE="${start_input}T00:00:00Z"
        END_DATE="${end_input}T23:59:59Z"
        echo -e "${GREEN}✓ Using custom range: $start_input to $end_input ($DAYS_DIFF days)${NC}" >&2
    else
        echo -e "${RED}✗ Invalid choice. Please enter 1 or 2${NC}" >&2
        return 1
    fi

    # Export for use in main script
    export START_DATE END_DATE
}

# Function to perform the usage data export
perform_export() {
    local org_id="$1"

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "Organization ID: $org_id"
    echo ""

    # Prompt for date range
    if ! prompt_for_date_range; then
        echo -e "${RED}✗ Failed to get date range${NC}"
        return 1
    fi

    echo ""
    echo -e "${YELLOW}→ Creating export job...${NC}"
    echo "   Date range: $START_DATE to $END_DATE"
    echo ""

    # Validate date is not more than 1 year old
    START_DATE_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$START_DATE" "+%s" 2>/dev/null || date -d "$START_DATE" "+%s" 2>/dev/null)
    CURRENT_EPOCH=$(date +%s)
    if [ -n "$START_DATE_EPOCH" ]; then
        DAYS_AGO=$(( (CURRENT_EPOCH - START_DATE_EPOCH) / 86400 ))
        if [ $DAYS_AGO -gt 365 ]; then
            echo -e "${RED}✗ Start date cannot be more than 1 year ago (CircleCI API limit)${NC}"
            echo "   Your start date: $START_DATE ($DAYS_AGO days ago)"
            echo "   Maximum: 365 days ago"
            return 1
        fi
    fi

    # Create temp file for curl stderr
    CURL_ERROR=$(mktemp)

    CREATE_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
        "https://circleci.com/api/v2/organizations/$org_id/usage_export_job" \
        -H "Circle-Token: $API_KEY" \
        -H "Content-Type: application/json" \
        -d "{
            \"start\": \"$START_DATE\",
            \"end\": \"$END_DATE\",
            \"shared_org_ids\": []
        }" 2>"$CURL_ERROR")

    # Extract HTTP status
    HTTP_STATUS=$(echo "$CREATE_RESPONSE" | grep "HTTP_STATUS:" | cut -d':' -f2)
    BODY=$(echo "$CREATE_RESPONSE" | sed '/HTTP_STATUS:/d')

    echo -e "${CYAN}API Response (Status: $HTTP_STATUS):${NC}"
    echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
    echo ""

    # Check if HTTP status is empty (network/API error)
    if [ -z "$HTTP_STATUS" ]; then
        echo -e "${RED}✗ Failed to communicate with CircleCI API${NC}"
        echo ""

        # Show curl errors if any
        if [ -s "$CURL_ERROR" ]; then
            echo -e "${YELLOW}Curl error:${NC}"
            cat "$CURL_ERROR"
            echo ""
        fi

        # Show raw response for debugging
        if [ -n "$CREATE_RESPONSE" ]; then
            echo -e "${YELLOW}Raw response:${NC}"
            echo "$CREATE_RESPONSE"
            echo ""
        fi

        echo "   This could be due to:"
        echo "   - Network connectivity issues"
        echo "   - Invalid API key for this organization"
        echo "   - Invalid organization ID"
        echo "   - API service unavailable"
        echo ""
        echo "   Troubleshooting:"
        echo "   1. Verify org ID: $org_id"
        echo "   2. Check API key has access to this org"
        echo "   3. Test API connection:"
        echo "      curl -H \"Circle-Token: \$CIRCLECI_API_KEY\" https://circleci.com/api/v2/me"

        rm -f "$CURL_ERROR"
        return 1
    fi

    # Clean up temp file
    rm -f "$CURL_ERROR"

    # Check if request was successful
    if [ "$HTTP_STATUS" != "201" ] && [ "$HTTP_STATUS" != "200" ]; then
        echo -e "${RED}✗ Failed to create export job (HTTP $HTTP_STATUS)${NC}"

        # Check if it's an auth error
        if [ "$HTTP_STATUS" = "401" ] || [ "$HTTP_STATUS" = "403" ]; then
            echo ""
            echo -e "${YELLOW}⚠ Authentication failed (HTTP $HTTP_STATUS).${NC}"
            echo "  Your saved API key may be expired or invalid."
            echo ""
            echo -e "${CYAN}  To reset your key, run:${NC}"
            echo "  security delete-generic-password -s "circleci-usage-script" -a "api-key""
            echo ""
            read -p "  Reset key and enter a new one now? (y/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                security delete-generic-password -s "circleci-usage-script" -a "api-key" 2>/dev/null || true
                echo -e "  ${GREEN}✓ Old key removed from Keychain${NC}"
                echo ""
                API_KEY=$(prompt_for_api_key)
                return 2  # Signal to retry
            fi
        fi
        return 1
    fi

    # Extract job ID (field name is "usage_export_job_id")
    JOB_ID=$(echo "$BODY" | grep -o '"usage_export_job_id":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [ -z "$JOB_ID" ]; then
        echo -e "${RED}✗ Could not extract job ID from response${NC}"
        return 1
    fi

    echo -e "${GREEN}✓ Export job created with ID: $JOB_ID${NC}"
    echo ""

    # Step 2: Poll for completion with 2-minute timeout
    echo -e "${YELLOW}→ Waiting for data to be prepared...${NC}"
    echo "   (Maximum wait time: 2 minutes)"
    echo ""

    MAX_ATTEMPTS=24  # 2 minutes (24 * 5 seconds)
    ATTEMPT=0
    START_TIME=$(date +%s)

    while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        sleep 5
        ATTEMPT=$((ATTEMPT + 1))

        STATUS_RESPONSE=$(curl -s \
            "https://circleci.com/api/v2/organizations/$org_id/usage_export_job/$JOB_ID" \
            -H "Circle-Token: $API_KEY")

        STATE=$(echo "$STATUS_RESPONSE" | grep -o '"state":"[^"]*"' | cut -d'"' -f4)

        # Show compact status updates
        ELAPSED=$(($(date +%s) - START_TIME))
        echo -e "${CYAN}[${ELAPSED}s] Check #$ATTEMPT: State = $STATE${NC}"

        if [ "$STATE" = "finished" ] || [ "$STATE" = "completed" ]; then
            MINUTES=$((ELAPSED / 60))
            SECONDS=$((ELAPSED % 60))
            echo ""
            echo -e "${GREEN}✓ Data ready! (took ${MINUTES}m ${SECONDS}s)${NC}"
            echo ""

            # Parse and download all CSV files
            echo -e "${YELLOW}→ Parsing download URLs...${NC}"

            # Extract all download URLs using jq if available, otherwise use grep
            if command -v jq &> /dev/null; then
                DOWNLOAD_URLS=$(echo "$STATUS_RESPONSE" | jq -r '.download_urls[]?' 2>/dev/null)
            else
                # Fallback: extract URLs using grep (less reliable but works without jq)
                DOWNLOAD_URLS=$(echo "$STATUS_RESPONSE" | grep -o 'https://[^"]*\.csv\.gz[^"]*' | head -10)
            fi

            if [ -z "$DOWNLOAD_URLS" ]; then
                echo -e "${RED}✗ No download URLs found in response${NC}"
                return 1
            fi

            URL_COUNT=$(echo "$DOWNLOAD_URLS" | wc -l | tr -d ' ')
            echo "   Found $URL_COUNT file(s) to download"
            echo ""

            # Create output directory
            OUTPUT_DIR="circleci_usage_${org_id}_$(date +%Y%m%d_%H%M%S)"
            mkdir -p "$OUTPUT_DIR"

            # Download and decompress each file
            FILE_NUM=0
            echo "$DOWNLOAD_URLS" | while read -r URL; do
                if [ -n "$URL" ]; then
                    FILE_NUM=$((FILE_NUM + 1))
                    GZ_FILE="$OUTPUT_DIR/usage_part_${FILE_NUM}.csv.gz"
                    CSV_FILE="$OUTPUT_DIR/usage_part_${FILE_NUM}.csv"

                    echo -e "${CYAN}→ Downloading file $FILE_NUM/$URL_COUNT...${NC}"

                    # Download with progress
                    curl -# -L -o "$GZ_FILE" "$URL"

                    if [ -f "$GZ_FILE" ]; then
                        FILE_SIZE=$(wc -c < "$GZ_FILE" | tr -d ' ')
                        echo -e "  ${GREEN}✓ Downloaded: ${FILE_SIZE} bytes${NC}"

                        # Decompress
                        echo -e "  ${CYAN}→ Decompressing...${NC}"
                        gunzip -f "$GZ_FILE"

                        if [ -f "$CSV_FILE" ]; then
                            CSV_SIZE=$(wc -c < "$CSV_FILE" | tr -d ' ')
                            echo -e "  ${GREEN}✓ Decompressed: ${CSV_SIZE} bytes${NC}"
                        else
                            echo -e "  ${RED}✗ Decompression failed${NC}"
                        fi
                    else
                        echo -e "  ${RED}✗ Download failed${NC}"
                    fi
                    echo ""
                fi
            done

            echo -e "${GREEN}✓ All files downloaded to: $OUTPUT_DIR${NC}"
            echo ""

            # Merge CSV files if requested
            if [ "$MERGE_FILES" = true ]; then
                echo -e "${YELLOW}→ Merging CSV files...${NC}"

                # Extract date portion from START_DATE and END_DATE (YYYY-MM-DD)
                START_DATE_ONLY=$(echo "$START_DATE" | cut -d'T' -f1)
                END_DATE_ONLY=$(echo "$END_DATE" | cut -d'T' -f1)

                MERGED_FILE="$OUTPUT_DIR/usage_${START_DATE_ONLY}_to_${END_DATE_ONLY}.csv"
                PART_FILES=($OUTPUT_DIR/usage_part_*.csv)

                if [ ${#PART_FILES[@]} -eq 0 ]; then
                    echo -e "${RED}✗ No CSV files found to merge${NC}"
                else
                    # Write header from first file
                    head -1 "${PART_FILES[0]}" > "$MERGED_FILE"

                    # Append data from all files (skip headers)
                    for csv_file in "${PART_FILES[@]}"; do
                        echo -e "  ${CYAN}→ Merging $(basename "$csv_file")...${NC}"
                        tail -n +2 "$csv_file" >> "$MERGED_FILE"
                    done

                    if [ -f "$MERGED_FILE" ]; then
                        MERGED_SIZE=$(wc -c < "$MERGED_FILE" | tr -d ' ')
                        MERGED_LINES=$(wc -l < "$MERGED_FILE" | tr -d ' ')
                        echo ""
                        echo -e "${GREEN}✓ Merged into: $(basename "$MERGED_FILE")${NC}"
                        echo "   Size: $MERGED_SIZE bytes"
                        echo "   Lines: $MERGED_LINES (including header)"
                        echo ""

                        # Ask if user wants to remove individual files
                        read -p "Remove individual part files? (y/n) " -n 1 -r
                        echo
                        if [[ $REPLY =~ ^[Yy]$ ]]; then
                            rm -f "${PART_FILES[@]}"
                            echo -e "${GREEN}✓ Individual files removed${NC}"
                            echo ""
                        fi

                        # ── Prefix merged file and folder with org name ──────────────
                        ORG_SLUG=""
                        if [ -f "$MERGED_FILE" ]; then
                            # Read ORGANIZATION_NAME from column 2 of first data row
                            RAW_ORG_NAME=$(awk -F',' 'NR==2{gsub(/"/, "", $2); print $2}' "$MERGED_FILE")
                            if [ -n "$RAW_ORG_NAME" ]; then
                                # Sanitize: lowercase, spaces→hyphens, strip special chars
                                ORG_SLUG=$(echo "$RAW_ORG_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-_')
                            fi
                        fi

                        if [ -n "$ORG_SLUG" ]; then
                            # Rename the merged CSV file
                            MERGED_DIR=$(dirname "$MERGED_FILE")
                            MERGED_BASE=$(basename "$MERGED_FILE")
                            NEW_MERGED_FILE="$MERGED_DIR/${ORG_SLUG}-${MERGED_BASE}"
                            mv "$MERGED_FILE" "$NEW_MERGED_FILE"
                            MERGED_FILE="$NEW_MERGED_FILE"
                            echo -e "${GREEN}✓ Renamed to: $(basename "$MERGED_FILE")${NC}"

                            # Rename the output folder too
                            NEW_OUTPUT_DIR=$(dirname "$OUTPUT_DIR")/${ORG_SLUG}-$(basename "$OUTPUT_DIR")
                            mv "$OUTPUT_DIR" "$NEW_OUTPUT_DIR"
                            OUTPUT_DIR="$NEW_OUTPUT_DIR"
                            MERGED_FILE="$OUTPUT_DIR/$(basename "$MERGED_FILE")"
                            echo -e "${GREEN}✓ Folder renamed to: $(basename "$OUTPUT_DIR")${NC}"
                            echo ""
                        fi

                                                # Show preview of merged file
                        echo -e "${BLUE}Preview (first 10 lines of merged file):${NC}"
                        head -10 "$MERGED_FILE"
                        echo ""

                        # Show visualizer link
                        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                        echo -e "${YELLOW}📊 Visualize your usage data:${NC}"
                        echo -e ""
                        echo -e "${CYAN}   File: $(basename "$MERGED_FILE")${NC}"
                        echo -e "${CYAN}   Path: $MERGED_FILE${NC}"
                        echo -e ""
                        echo -e "${GREEN}   Click here to open visualizer:${NC}"
                        echo -e "${BLUE}   https://hennaabbas.github.io/circleci-usage-report-visualizer/${NC}"
                        echo -e ""
                        echo -e "   Upload your CSV file to the visualizer to see detailed charts and insights."
                        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                    else
                        echo -e "${RED}✗ Merge failed${NC}"
                    fi
                fi
            else
                echo -e "${CYAN}ℹ Skipping merge (--no-merge flag set)${NC}"
                echo ""

                # Show preview of first CSV file
                FIRST_CSV=$(find "$OUTPUT_DIR" -name "*.csv" -type f | head -1)
                if [ -n "$FIRST_CSV" ]; then
                    echo -e "${BLUE}Preview (first 10 lines of $(basename "$FIRST_CSV")):${NC}"
                    head -10 "$FIRST_CSV"
                    echo ""

                    # Show visualizer link for separate files
                    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                    echo -e "${YELLOW}📊 Visualize your usage data:${NC}"
                    echo -e ""
                    echo -e "${CYAN}   Directory: $OUTPUT_DIR${NC}"
                    echo -e "${CYAN}   Files: $(ls -1 $OUTPUT_DIR/*.csv | wc -l | tr -d ' ') CSV files${NC}"
                    echo -e ""
                    echo -e "${GREEN}   Click here to open visualizer:${NC}"
                    echo -e "${BLUE}   https://hennaabbas.github.io/circleci-usage-report-visualizer/${NC}"
                    echo -e ""
                    echo -e "   ${YELLOW}Note:${NC} Merge your files first or upload them individually."
                    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                fi
            fi

            return 0
        elif [ "$STATE" = "failed" ]; then
            echo ""
            echo -e "${RED}✗ Export job failed${NC}"
            echo "$STATUS_RESPONSE" | jq '.' 2>/dev/null || echo "$STATUS_RESPONSE"
            return 1
        fi
    done

    echo ""
    echo -e "${RED}✗ Timeout: Data not ready after 2 minutes${NC}"
    echo "   Job ID: $JOB_ID"
    echo "   Last state: $STATE"
    echo ""
    echo "   You can check status later with:"
    echo "   curl -H \"Circle-Token: \$CIRCLECI_API_KEY\" \\"
    echo "     \"https://circleci.com/api/v2/organizations/$org_id/usage_export_job/$JOB_ID\""
    return 1
}

# Main script starts here
echo -e "${BLUE}CircleCI Usage Data Export${NC}"
echo -e "${BLUE}===========================${NC}"
echo ""

# Get or prompt for API key
API_KEY=$(get_api_key)

if [ -z "$API_KEY" ]; then
    echo -e "${YELLOW}→ No saved API key found${NC}"
    echo ""
    API_KEY=$(prompt_for_api_key)
else
    echo -e "${GREEN}✓ Using saved API key from Keychain${NC}"
    echo ""
fi

# Main loop
while true; do
    # Get organization ID (from argument on first run, or prompt)
    if [ -n "$INITIAL_ORG_ID" ]; then
        ORG_ID="$INITIAL_ORG_ID"
        INITIAL_ORG_ID=""  # Clear so we prompt next time
    else
        echo ""
        ORG_ID=$(prompt_for_org_id)
        if [ -z "$ORG_ID" ]; then
            echo -e "${RED}✗ No organization ID provided${NC}"
            exit 1
        fi
    fi

    # Perform the export
    perform_export "$ORG_ID"
    RESULT=$?

    # If result is 2, retry with new API key
    if [ $RESULT -eq 2 ]; then
        continue
    fi

    # Ask if user wants to get more data
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -p "Would you like to retrieve more usage data? (y/n) " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${GREEN}✓ Done! Thank you for using CircleCI Usage Export${NC}"
        exit 0
    fi
done
