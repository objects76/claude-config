#!/bin/bash
# Weekly Work Report Generator
# Extracts work entries from daily log and organizes by Domain

set -e

# Configuration
WORK_LOG_SPREADSHEET="1rsKATqGP59zVU5zWcUq1KJa7UrDn14oL0Y4-54ik3NU"
WEEKLY_REPORT_SPREADSHEET="12Cs1IAzALEZQnKKF3OJGL4haOv670a6YFODWLCgOWo0"
USER_NAME="김정진"
USER_ROW=22
SHEET_NAME=""

echo "📊 Weekly Work Report Generator"
echo "================================"

# Step 1: Calculate date range
echo ""
echo "📅 Step 1: Calculating date range..."

python3 << 'PYTHON_EOF'
from datetime import datetime, timedelta

def get_report_date_range():
    today = datetime.now()
    days_since_friday = (today.weekday() - 4) % 7  # Friday is 4
    if days_since_friday == 0 and today.weekday() == 4:
        last_friday = today
    else:
        last_friday = today - timedelta(days=days_since_friday)
    return last_friday, today

def format_date(dt):
    return f"{dt.year}. {dt.month}. {dt.day}"

last_friday, today = get_report_date_range()
print(f"LAST_FRIDAY={format_date(last_friday)}")
print(f"TODAY={format_date(today)}")
PYTHON_EOF

echo ""
echo "📋 Step 2: Finding latest weekly report tab..."

LATEST_SHEET_NAME=$(python3 << 'PYTHON_EOF'
import json
import subprocess
import sys
from datetime import datetime

spreadsheet_id = "12Cs1IAzALEZQnKKF3OJGL4haOv670a6YFODWLCgOWo0"

cmd = [
    "gws", "sheets", "spreadsheets", "get",
    "--params", json.dumps({
        "spreadsheetId": spreadsheet_id,
        "fields": "sheets.properties.title"
    })
]

try:
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    data = json.loads(result.stdout)
except Exception as e:
    print(f"Error: Failed to get spreadsheet tabs: {e}", file=sys.stderr)
    sys.exit(1)

date_tabs = []
for sheet in data.get("sheets", []):
    title = sheet.get("properties", {}).get("title", "")
    if len(title) == 4 and title.isdigit():
        try:
            mm = int(title[:2])
            dd = int(title[2:])
            if 1 <= mm <= 12 and 1 <= dd <= 31:
                date_tabs.append((mm, dd, title))
        except Exception:
            pass

if not date_tabs:
    print("Error: No date-formatted weekly report tabs found", file=sys.stderr)
    sys.exit(1)

# Choose the latest tab by month/day within the current year.
latest = max(date_tabs, key=lambda x: (x[0], x[1]))
print(latest[2])
PYTHON_EOF
) || exit 1

SHEET_NAME="$LATEST_SHEET_NAME"
echo "✅ Latest tab found: $SHEET_NAME"

echo ""
echo "📋 Step 3: Reading work log from spreadsheet..."

# Read work log
# Keep stdout as pure JSON; send only stderr to a log file.
gws sheets +read --spreadsheet "$WORK_LOG_SPREADSHEET" --range "'$USER_NAME'" --format json 1> /tmp/work_log.json 2> /tmp/work_log.stderr || {
    echo "Error: Failed to read work log. Make sure you're authenticated with Google Workspace."
    cat /tmp/work_log.stderr >&2 || true
    exit 1
}

echo "✅ Work log downloaded"

# Step 3 & 4: Parse, filter, and organize by Domain
echo ""
echo "🔍 Step 3 & 4: Parsing and organizing by Domain..."

python3 << 'PYTHON_EOF'
import json
import sys
from datetime import datetime

# Get date range from environment or recalculate
from datetime import timedelta
today = datetime.now()
days_since_friday = (today.weekday() - 4) % 7
if days_since_friday == 0 and today.weekday() == 4:
    last_friday = today
else:
    last_friday = today - timedelta(days=days_since_friday)

def parse_date(date_str):
    """Parse date from format '2026. 3. 13'"""
    try:
        parts = date_str.replace(".", " ").split()
        if len(parts) >= 3:
            return datetime(int(parts[0]), int(parts[1]), int(parts[2]))
    except:
        pass
    return None

def is_in_range(date_str, start_date, end_date):
    """Check if date is within range"""
    dt = parse_date(date_str)
    if dt is None:
        return False
    return start_date.date() <= dt.date() <= end_date.date()

# Read work log
try:
    with open('/tmp/work_log.json', 'r') as f:
        data = json.load(f)
except Exception as e:
    print(f"Error reading work log: {e}", file=sys.stderr)
    sys.exit(1)

# Extract rows from values
values = data.get('values', [])
if not values:
    print("No data found in work log")
    sys.exit(0)

# Process rows
# Current sheet columns: A=Date, B=Project, C=Category, D=Content, E=Hours, F=Note, G=Domain
entries_by_domain = {}
current_domain = None

for row in values[1:]:  # Skip header
    if len(row) < 1:
        continue

    date_str = row[0] if len(row) > 0 else ""
    task_content = row[3] if len(row) > 3 else ""  # Column D = 내용
    domain = row[6] if len(row) > 6 else ""  # Column G = Domain
    
    # Skip empty rows
    if not date_str and not task_content:
        continue
    
    # Update current domain if provided
    if domain and domain.strip():
        current_domain = domain.strip()
    
    # Check if date is in range
    if date_str and is_in_range(date_str, last_friday, today):
        if current_domain and task_content:
            if current_domain not in entries_by_domain:
                entries_by_domain[current_domain] = []
            entries_by_domain[current_domain].append(task_content.strip())

# Generate report format
report_lines = []
for domain, tasks in entries_by_domain.items():
    report_lines.append(f"{domain}:")
    for task in tasks:
        report_lines.append(f"- {task}")
    report_lines.append("")  # Empty line between domains

report_text = "\n".join(report_lines).strip()

# Save report
with open('/tmp/weekly_report.txt', 'w') as f:
    f.write(report_text)

# Also save as JSON for API
report_json = json.dumps({"values": [[report_text]]})
with open('/tmp/body.json', 'w') as f:
    f.write(report_json)

print(f"Generated report for period: {last_friday.strftime('%Y. %m. %d')} ~ {today.strftime('%Y. %m. %d')}")
print(f"\nFound {len(entries_by_domain)} domains:")
for domain in entries_by_domain.keys():
    print(f"  - {domain}: {len(entries_by_domain[domain])} tasks")

print(f"\n📄 Report preview:")
print("-" * 50)
print(report_text[:500] + "..." if len(report_text) > 500 else report_text)
print("-" * 50)
PYTHON_EOF

echo ""
echo "📝 Step 6: Preparing to update weekly report..."

# Determine which column to update (D=last week, E=this week)
# For now, we'll update column E (이번 주)
TARGET_COLUMN="E"

cat > /tmp/params.json << EOF
{
  "spreadsheetId": "$WEEKLY_REPORT_SPREADSHEET",
  "range": "'$SHEET_NAME'!${TARGET_COLUMN}${USER_ROW}",
  "valueInputOption": "USER_ENTERED"
}
EOF

echo ""
echo "📤 Update parameters:"
echo "  Spreadsheet: $WEEKLY_REPORT_SPREADSHEET"
echo "  Range: '$SHEET_NAME'!${TARGET_COLUMN}${USER_ROW}"
echo ""

read -p "Proceed with update? (y/n): " confirm

if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
    echo ""
    echo "🚀 Updating weekly report..."
    
    gws sheets spreadsheets values update \
        --params "$(cat /tmp/params.json)" \
        --json "$(cat /tmp/body.json)" 2>&1 || {
        echo "Error: Failed to update weekly report"
        exit 1
    }
    
    echo ""
    echo "✅ Weekly report updated successfully!"
else
    echo ""
    echo "⏭️ Update cancelled."
    echo ""
    echo "To update manually, run:"
    echo "  gws sheets spreadsheets values update --params '$(cat /tmp/params.json)' --json '$(cat /tmp/body.json)'"
fi

echo ""
echo "Done!"
