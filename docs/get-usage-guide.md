# get-usage.sh — Full Guide

`get-usage.sh` is a standalone Bash script that pulls CircleCI usage data from the API and saves it as a clean, analysis-ready CSV. It handles authentication, polling, download, decompression, and merging — and automatically names the output file using your org slug and date range.

---

## Prerequisites

| Requirement | Details | Install |
|---|---|---|
| macOS or Linux | Tested on macOS 13+ | — |
| bash 3+ | Pre-installed on macOS | — |
| curl | Pre-installed on macOS | — |
| jq | Strongly recommended | `brew install jq` |
| gunzip | Pre-installed on macOS | — |
| CircleCI API key | Token starting with `CCIPAT_` | See Step 1 |

---

## Setup (one time)

```bash
chmod +x get-usage.sh
brew install jq
```

---

## Usage

```bash
# Interactive
./get-usage.sh

# Pre-fill org ID
./get-usage.sh xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

# Keep part files instead of merging
./get-usage.sh --no-merge
```

---

## Step-by-Step

### Step 1 — API Key

On first run the script checks macOS Keychain. If no key is found, you are prompted:

```
CircleCI API Key Required
Enter your CircleCI API key: ••••••••••••
→ Saving API key to macOS Keychain...
✓ API key saved securely
```

**Where to get your key:**
1. Go to https://app.circleci.com/settings/user/tokens
2. Click **Create New Token**
3. Copy the token — it starts with `CCIPAT_`

Your key is stored in macOS Keychain and never written to disk as plaintext.

---

### Step 2 — Organization ID

```
Enter Organization ID:
Org ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

Find it in **CircleCI → Organization Settings → Overview**. Pass it as a CLI argument to skip this prompt on future runs.

---

### Step 3 — Date Range

```
[1] Default: Last 30 days
[2] Custom date range
```

> **API Limit:** Max 31 days per export job. For longer periods, run multiple times with consecutive windows.

---

### Step 4 — Export & Download

The script creates the export job, polls until ready, then downloads and merges all parts:

```
→ Creating export job...
✓ Export job created

→ Waiting for data to be prepared...
✓ Data ready! (took 0m 28s)

→ Downloading file 1/2...
  ✓ Downloaded and decompressed

→ Merging CSV files...
✓ Saved: orgname-usage_2025-12-01_to_2025-12-31.csv
```

The filename is built automatically from your org's name in the CSV combined with the date range.

---

## Output Structure

```
circleci_usage_{org_id}_{timestamp}/
└── orgname-usage_YYYY-MM-DD_to_YYYY-MM-DD.csv
```

---

## Troubleshooting

| Error | Fix |
|---|---|
| `HTTP 401` | Re-run and enter a new API key |
| `HTTP 403` | Use a token from an account with org access |
| `HTTP 400` | Date range > 31 days — shorten it |
| No download URLs | No activity in that date range |
| Timeout | Re-poll with the curl command shown in terminal |
| Charts don't render | Use `python3 -m http.server 8765` instead of opening directly |

---

## Update Saved API Key

```bash
security delete-generic-password -s "circleci-usage-script" -a "api-key"
./get-usage.sh
```
