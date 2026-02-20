# CircleCI Usage Report Visualizer

A **zero-dependency, single-file HTML dashboard** for analyzing CircleCI usage data exported via the CircleCI Usage Export API. Drop in your CSV and instantly get interactive charts, credit burn analysis, resource utilization insights, and downloadable rightsizing reports — all running locally in your browser with no data ever leaving your machine.

---

## 📥 Getting Your Data — `get-usage.sh`

The fastest way to get your usage data is the included shell script. It handles everything: authentication, polling, download, decompression, and merging — and automatically names the output file using your org slug and date range.

```bash
# One-time setup
chmod +x get-usage.sh
brew install jq          # recommended for reliable parsing

# Run it
./get-usage.sh
```

**What happens when you run it:**

```
✓ Using saved API key from Keychain

Enter Organization ID:
Org ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

Select Date Range:
  [1] Default: Last 30 days
  [2] Custom date range

→ Creating export job...
→ Waiting for data to be prepared...
✓ Data ready! (took 0m 28s)
→ Downloading and merging files...
✓ Saved: orgname-usage_2025-12-01_to_2025-12-31.csv
```

Your file is named automatically using your org's name and the date range — no manual renaming needed. See [`docs/get-usage-guide.md`](docs/get-usage-guide.md) for the complete walkthrough.

---

## 🔑 API Key Management

Your CircleCI API key is stored securely in macOS Keychain — it is never written to disk as plaintext.

**First run:** The script will prompt you to enter your key and save it automatically.

**If your key has expired or you entered it incorrectly**, reset it with one command:

```bash
security delete-generic-password -s "circleci-usage-script" -a "api-key"
```

Then re-run `./get-usage.sh` — it will prompt for a fresh key and save it.

**Where to get or create an API key:**
1. Go to [https://app.circleci.com/settings/user/tokens](https://app.circleci.com/settings/user/tokens)
2. Click **Create New Token**
3. Give it a name (e.g. `Usage Export`)
4. Copy the token — it starts with `CCIPAT_`

**Signs your key needs replacing:**
- The script returns `HTTP 401` — key is invalid or expired
- The script returns `HTTP 403` — key doesn't have access to that org
- The script says "API key doesn't match expected format" — you may have copied it incorrectly

---

## ✨ Features

| Feature | Details |
|---|---|
| **Credit Burn Rate** | Daily and weekly credit burn charts across the full date range |
| **Top Consumers** | Projects, workflows, and jobs ranked by credit spend |
| **Resource Class Distribution** | See which resource classes are driving your bill |
| **CPU & RAM Utilization Analysis** | Histogram distributions across all jobs |
| **Underutilized Jobs Detection** | Jobs with CPU & RAM ≤ 40% — rightsizing candidates |
| **Underprovisioned Jobs Detection** | Jobs with CPU or RAM ≥ 80% — candidates for upsizing |
| **Failed Jobs Analysis** | Failure rates by project and workflow |
| **Smart Download Naming** | Exported reports auto-prefixed with org name + date range |
| **Auto-load via URL param** | Pass `?autoload=filename.csv` to skip the file picker |

---

## 🚀 Quick Start

### Option 1 — Local server (recommended)

```bash
# Run from the directory containing index.html and your CSV
python3 -m http.server 8765
```

Then open: `http://localhost:8765`

> A local server is recommended because some browsers block reading local files directly. It also enables the `?autoload` feature.

### Option 2 — GitHub Pages

This visualizer is hosted publicly at:
**[https://amarirules.github.io/circleci-usage-visualizer/](https://amarirules.github.io/circleci-usage-visualizer/)**

Upload your CSV using the file picker. No data is sent to any server — everything runs in your browser.

---

## 🔧 Auto-load Feature

When running with a local server, skip the file picker by passing your filename as a URL parameter:

```
http://localhost:8765/?autoload=orgname-usage_2025-12-01_to_2025-12-31.csv
```

The CSV must be in the same directory as `index.html`.

---

## 📤 Export Naming Convention

Downloaded reports are automatically named to match the source file:

| Source file | Exported report |
|---|---|
| `orgname-usage_YYYY-MM-DD_to_YYYY-MM-DD.csv` | `orgname-usage_YYYY-MM-DD_to_YYYY-MM-DD-circleci-underutilized-jobs.csv` |
| `orgname-usage_YYYY-MM-DD_to_YYYY-MM-DD.csv` | `orgname-usage_YYYY-MM-DD_to_YYYY-MM-DD-circleci-overprovisioned-jobs.csv` |

---

## 📊 CSV Format

**Required columns:**
`PROJECT_NAME` · `JOB_NAME` · `WORKFLOW_NAME` · `RESOURCE_CLASS` · `JOB_BUILD_STATUS` · `JOB_RUN_SECONDS` · `TOTAL_CREDITS` · `JOB_RUN_DATE` · `PIPELINE_CREATED_AT` · `VCS_BRANCH`

**Optional (enables Resource Utilization section):**
`MEDIAN_CPU_UTILIZATION_PCT` · `MEDIAN_RAM_UTILIZATION_PCT`

---

## 🛠 Tech Stack

Vanilla HTML/JS — no build step, no Node, no dependencies to install.

[PapaParse](https://www.papaparse.com/) · [Chart.js](https://www.chartjs.org/) · [Lodash](https://lodash.com/) · [Tailwind CSS](https://tailwindcss.com/)

---

## 📄 License

MIT — use freely, fork freely.
