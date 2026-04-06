#!/usr/bin/env bash
# ==============================================================================
# SPOKE LOG ANALYSIS - AI-TRIAGED DAILY LOG REPORT
# ==============================================================================
# Description: Query Loki for errors/warnings, analyze with Claude Code,
#              and email a structured severity-triaged report
# Author: Matt Barham
# Created: 2026-03-28
# Version: 1.0.0
# ==============================================================================
# Dependencies:
#   - Loki container running on Docker network (monitoring module)
#   - Mail relay module deployed (spoke-mail-relay)
#   - Claude Code CLI authenticated (claude -p)
#   - curl, jq
# ==============================================================================
# Usage: ./spoke_log_analysis.sh [--hours N] [--dry-run]
#   --hours N    Look back N hours (default: 24)
#   --dry-run    Query and analyze but don't send email
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
# CONFIGURATION
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPOKE_DIR="${SPOKE_DIR:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
BASE_ENV_FILE="${SPOKE_DIR}/shared/env/base.env"

# Defaults (overridable via environment)
LOKI_HOST="${LOKI_HOST:-loki}"
LOKI_PORT="${LOKI_PORT:-3100}"
LOKI_TENANT_ID="${LOKI_TENANT_ID:-fake}"
MAIL_RELAY_HOST="${MAIL_RELAY_HOST:-}"
MAIL_RELAY_PORT="${MAIL_RELAY_PORT:-8000}"
LOOKBACK_HOURS="${LOOKBACK_HOURS:-24}"
CLAUDE_MODEL="${CLAUDE_MODEL:-sonnet}"
DRY_RUN="${DRY_RUN:-false}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --hours)
            LOOKBACK_HOURS="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        *)
            printf "Unknown argument: %s\n" "$1" >&2
            exit 1
            ;;
    esac
done

# Load environment
if [[ -f "${BASE_ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${BASE_ENV_FILE}"
else
    printf "ERROR: Base environment file not found: %s\n" "${BASE_ENV_FILE}" >&2
    exit 1
fi

: "${ADMIN_EMAIL:?ERROR: ADMIN_EMAIL not set in environment}"
: "${SERVICES_EMAIL:?ERROR: SERVICES_EMAIL not set in environment}"

# Resolve mail relay host from Docker if not explicitly set
if [[ -z "${MAIL_RELAY_HOST}" ]]; then
    MAIL_RELAY_HOST=$(docker inspect mail-relay \
        --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null \
        | head -1) || true
    if [[ -z "${MAIL_RELAY_HOST}" ]]; then
        printf "ERROR: Cannot resolve mail-relay container IP. Is the mail_relay module running?\n" >&2
        exit 1
    fi
fi

# Resolve Loki host from Docker if using default hostname
if [[ "${LOKI_HOST}" == "loki" ]]; then
    RESOLVED_LOKI=$(docker inspect loki \
        --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null \
        | head -1) || true
    if [[ -n "${RESOLVED_LOKI}" ]]; then
        LOKI_HOST="${RESOLVED_LOKI}"
    fi
fi

LOKI_URL="http://${LOKI_HOST}:${LOKI_PORT}"
RELAY_URL="http://${MAIL_RELAY_HOST}:${MAIL_RELAY_PORT}"
TODAY_DATE=$(date "+%Y-%m-%d")
INSTANCE_NAME="${INSTANCE_NAME:-Spoke}"

printf "=== Spoke Log Analysis ===\n"
printf "  Instance:    %s\n" "${INSTANCE_NAME}"
printf "  Loki:        %s\n" "${LOKI_URL}"
printf "  Mail relay:  %s\n" "${RELAY_URL}"
printf "  Lookback:    %s hours\n" "${LOOKBACK_HOURS}"
printf "  Recipient:   %s\n" "${ADMIN_EMAIL}"
printf "  Model:       %s\n" "${CLAUDE_MODEL}"
printf "  Dry run:     %s\n" "${DRY_RUN}"

# ==============================================================================
# STEP 1: VERIFY DEPENDENCIES
# ==============================================================================

printf "\n[1/4] Verifying dependencies...\n"

if ! command -v claude &>/dev/null; then
    printf "ERROR: Claude Code CLI not found. Install from https://claude.ai/code\n" >&2
    exit 1
fi

_loki_ready=false
for _i in $(seq 1 12); do
    if curl -sf --max-time 5 "${LOKI_URL}/ready" &>/dev/null; then
        _loki_ready=true
        break
    fi
    printf "  Waiting for Loki... (%s/12)\n" "${_i}"
    sleep 10
done
if [[ "${_loki_ready}" != "true" ]]; then
    printf "ERROR: Loki not reachable at %s after 2 minutes\n" "${LOKI_URL}" >&2
    # Attempt to send alert email if relay is available
    if curl -sf "${RELAY_URL}/health" &>/dev/null; then
        curl -sf -X POST "${RELAY_URL}/send" \
            -H "Content-Type: application/json" \
            -d "{\"to\":\"${ADMIN_EMAIL}\",\"subject\":\"[${INSTANCE_NAME}] Log Analysis FAILED - Loki Unreachable\",\"body_text\":\"Loki is not responding at ${LOKI_URL}. Log analysis could not run.\"}" \
            &>/dev/null || true
    fi
    exit 1
fi

if ! curl -sf "${RELAY_URL}/health" &>/dev/null; then
    printf "ERROR: Mail relay not reachable at %s\n" "${RELAY_URL}" >&2
    exit 1
fi

printf "  All dependencies OK\n"

# ==============================================================================
# STEP 2: QUERY LOKI
# ==============================================================================

printf "\n[2/4] Querying Loki for the last %s hours...\n" "${LOOKBACK_HOURS}"

START_TS="$(date -d "${LOOKBACK_HOURS} hours ago" +%s)000000000"
END_TS="$(date +%s)000000000"
TMPDIR_LOGS=$(mktemp -d)
trap 'rm -rf "${TMPDIR_LOGS}"' EXIT

query_loki() {
    local label="$1"
    local query="$2"
    local limit="${3:-5000}"
    local encoded_query

    encoded_query=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''${query}'''))")

    local response
    response=$(curl -sf --max-time 60 \
        -H "X-Scope-OrgID: ${LOKI_TENANT_ID}" \
        "${LOKI_URL}/loki/api/v1/query_range?query=${encoded_query}&start=${START_TS}&end=${END_TS}&limit=${limit}" 2>/dev/null) || {
        printf "  WARN: Query '%s' failed or timed out\n" "${label}" >&2
        printf "{\"status\":\"error\",\"data\":{\"result\":[]}}" > "${TMPDIR_LOGS}/${label}.json"
        return 0
    }

    printf "%s" "${response}" > "${TMPDIR_LOGS}/${label}.json"

    local result_count
    result_count=$(printf "%s" "${response}" | jq '[.data.result[].values | length] | add // 0' 2>/dev/null || printf "0")
    printf "  %-25s %s entries\n" "${label}:" "${result_count}"
}

query_loki "critical_fatal" '{job="docker"} |~ `(?i)(fatal|panic|killed|oom|segfault|out of memory)`'
query_loki "errors" '{job="docker"} | json | level=~`error|err|ERROR`' 2000
query_loki "warnings" '{job="docker"} | json | level=~`warn|warning|WARN|WARNING`' 1000
query_loki "system_issues" '{job="system"} |~ `(?i)(error|failed|critical|panic|oom)`'

# ==============================================================================
# STEP 3: AI ANALYSIS
# ==============================================================================

printf "\n[3/4] Running AI analysis with Claude (%s)...\n" "${CLAUDE_MODEL}"

# Load known patterns context if available
KNOWN_PATTERNS_FILE="${SCRIPT_DIR}/log_analysis_known_patterns.md"
KNOWN_PATTERNS=""
if [[ -f "${KNOWN_PATTERNS_FILE}" ]]; then
    KNOWN_PATTERNS=$(cat "${KNOWN_PATTERNS_FILE}")
    printf "  Loaded known patterns from %s\n" "${KNOWN_PATTERNS_FILE}"
fi

# Build the analysis prompt with raw log data
ANALYSIS_PROMPT=$(cat <<'PROMPT_HEADER'
You are analyzing server logs for a Spoke infrastructure instance. The raw Loki query results are below in JSON format. Each result set contains stream labels and timestamped log values.

## Your Task

1. Parse all the log entries from the JSON data below
2. Categorize each distinct issue by severity:
   - **CRITICAL**: OOM kills, segfaults, panics, container crashes, data loss, security breaches
   - **HIGH**: Persistent recurring errors, service connectivity failures, auth failures, resource warnings
   - **MEDIUM**: Intermittent errors, non-critical service warnings, configuration issues
   - **LOW**: Transient network hiccups, expected retries, routine warnings
   - **INFO**: Normal operations that matched error patterns but aren't actual problems
3. Deduplicate: group identical/similar errors, report count + first/last occurrence
4. Ignore noise: health check failures for stopped containers are expected (mention briefly)
5. Context matters: errors from critical infrastructure (traefik, authentik, postgres, crowdsec) rank higher
6. For CRITICAL/HIGH items, suggest a specific remediation step

## Output Format

You MUST output ONLY a single valid JSON object with this exact structure (no markdown, no explanation, no code fences):

{"summary":"1-3 sentence overview","total_events":N,"health":"healthy|degraded|critical","sections":[{"severity":"CRITICAL","color":"#dc3545","items":[{"service":"name","issue":"description","count":N,"first_seen":"timestamp","last_seen":"timestamp","recommendation":"action"}]},{"severity":"HIGH","color":"#fd7e14","items":[...]},{"severity":"MEDIUM","color":"#ffc107","items":[...]},{"severity":"LOW","color":"#6c757d","items":[...]},{"severity":"INFO","color":"#17a2b8","items":[...]}]}

If a severity level has no items, include it with an empty items array.
Timestamps should be human-readable (YYYY-MM-DD HH:MM:SS).
Keep the total JSON under 50KB.

## Raw Log Data

PROMPT_HEADER
)

# Inject known patterns if available
if [[ -n "${KNOWN_PATTERNS}" ]]; then
    ANALYSIS_PROMPT+=$(printf "\n## Known Patterns (Institutional Knowledge)\n\nThe following patterns have been observed and classified by the operator. Use these to calibrate your severity ratings — do not escalate items that match known-benign patterns.\n\n%s\n\n## Log Query Results\n\n" "${KNOWN_PATTERNS}")
fi

# Append each query result
for query_file in "${TMPDIR_LOGS}"/*.json; do
    label=$(basename "${query_file}" .json)
    ANALYSIS_PROMPT+=$(printf "\n### %s\n\n" "${label}")
    # Trim large results to avoid context overflow — keep first 100KB per query
    ANALYSIS_PROMPT+=$(head -c 102400 "${query_file}")
    ANALYSIS_PROMPT+=$'\n'
done

# Run Claude analysis
CLAUDE_STDERR=$(mktemp)
ANALYSIS_RESULT=$(printf "%s" "${ANALYSIS_PROMPT}" | claude -p --model "${CLAUDE_MODEL}" --allowedTools "" --output-format text 2>"${CLAUDE_STDERR}") || {
    printf "ERROR: Claude analysis failed (exit code: %s)\n" "$?" >&2
    if [[ -s "${CLAUDE_STDERR}" ]]; then
        printf "  Claude stderr: %s\n" "$(head -c 500 "${CLAUDE_STDERR}")" >&2
    else
        printf "  Claude stderr: (empty — possible auth token expiry or rate limit)\n" >&2
    fi
    # Send a basic report without AI analysis
    ANALYSIS_RESULT='{"summary":"AI analysis unavailable — Claude CLI returned an error. Raw log queries completed but could not be triaged.","total_events":0,"health":"unknown","sections":[]}'
}
rm -f "${CLAUDE_STDERR}"

# Treat empty output as a failure
if [[ -z "${ANALYSIS_RESULT}" ]]; then
    printf "ERROR: Claude returned empty output (possible auth token expiry)\n" >&2
    ANALYSIS_RESULT='{"summary":"AI analysis unavailable — Claude CLI returned empty output. Possible auth token expiry.","total_events":0,"health":"unknown","sections":[]}'
fi

# Validate JSON output
if ! printf "%s" "${ANALYSIS_RESULT}" | jq empty 2>/dev/null; then
    printf "WARN: Claude returned non-JSON output, attempting extraction...\n" >&2
    # Try to extract JSON from markdown code fences
    EXTRACTED=$(printf "%s" "${ANALYSIS_RESULT}" | sed -n '/^{/,/^}/p' | head -1)
    if printf "%s" "${EXTRACTED}" | jq empty 2>/dev/null; then
        ANALYSIS_RESULT="${EXTRACTED}"
    else
        ANALYSIS_RESULT='{"summary":"AI analysis produced unparseable output. Manual log review recommended.","total_events":0,"health":"unknown","sections":[]}'
    fi
fi

printf "  Analysis complete\n"

# ==============================================================================
# STEP 4: FORMAT AND SEND REPORT
# ==============================================================================

printf "\n[4/4] Formatting and sending report...\n"

# Build HTML report from analysis JSON
REPORT_HTML=$(printf "%s" "${ANALYSIS_RESULT}" | python3 -c "
import json, sys, html
from datetime import datetime

data = json.load(sys.stdin)
instance = '${INSTANCE_NAME}'
today = '${TODAY_DATE}'
lookback = '${LOOKBACK_HOURS}'
now = datetime.now().strftime('%Y-%m-%d %H:%M:%S %Z')

health_colors = {'healthy': '#28a745', 'degraded': '#fd7e14', 'critical': '#dc3545', 'unknown': '#6c757d'}
health_color = health_colors.get(data.get('health', 'unknown'), '#6c757d')

parts = []
parts.append(f'''<div style=\"font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px;\">
<h1 style=\"border-bottom: 3px solid #333; padding-bottom: 10px;\">{html.escape(instance)} Daily Log Report</h1>
<p><strong>Period:</strong> Last {lookback} hours ending {today} |
<strong>Health:</strong> <span style=\"color: {health_color}; font-weight: bold;\">{html.escape(data.get('health', 'unknown')).upper()}</span> |
<strong>Total Events:</strong> {data.get('total_events', 0)}</p>

<h2>Executive Summary</h2>
<p>{html.escape(data.get('summary', 'No summary available.'))}</p>''')

for section in data.get('sections', []):
    severity = section.get('severity', 'UNKNOWN')
    color = section.get('color', '#333')
    items = section.get('items', [])

    parts.append(f'<h2 style=\"color: {color};\">{html.escape(severity)} ({len(items)})</h2>')

    if not items:
        parts.append('<p style=\"color: #999;\">None</p>')
        continue

    if severity in ('CRITICAL', 'HIGH'):
        for item in items:
            parts.append(f'''<div style=\"border-left: 4px solid {color}; padding: 8px 12px; margin: 8px 0; background: #f8f9fa;\">
<strong>{html.escape(item.get('service', '?'))}</strong>: {html.escape(item.get('issue', ''))}
<br><small>Count: {item.get('count', '?')} | First: {html.escape(str(item.get('first_seen', '?')))} | Last: {html.escape(str(item.get('last_seen', '?')))}</small>
<br><em style=\"color: #0066cc;\">Recommendation: {html.escape(item.get('recommendation', 'Review logs'))}</em>
</div>''')
    elif severity == 'MEDIUM':
        parts.append('<ul>')
        for item in items:
            parts.append(f'<li><strong>{html.escape(item.get(\"service\", \"?\"))}</strong>: {html.escape(item.get(\"issue\", \"\"))} (x{item.get(\"count\", \"?\")})</li>')
        parts.append('</ul>')
    else:
        if items:
            summary_items = ', '.join(f'{html.escape(i.get(\"service\", \"?\"))} (x{i.get(\"count\", \"?\")})' for i in items[:10])
            parts.append(f'<p>{summary_items}</p>')
            if len(items) > 10:
                parts.append(f'<p style=\"color: #999;\">...and {len(items) - 10} more</p>')

parts.append(f'''<hr style=\"margin-top: 30px;\">
<p style=\"color: #999; font-size: 0.85em;\">Generated by Spoke Log Analysis Agent (Claude {html.escape('${CLAUDE_MODEL}')}) at {html.escape(now)}</p>
</div>''')

print('\\n'.join(parts))
")

# Build plain text version
REPORT_TEXT=$(printf "%s" "${ANALYSIS_RESULT}" | python3 -c "
import json, sys

data = json.load(sys.stdin)
instance = '${INSTANCE_NAME}'
lookback = '${LOOKBACK_HOURS}'
today = '${TODAY_DATE}'

lines = []
lines.append(f'{instance} Daily Log Report')
lines.append('=' * 60)
lines.append(f'Period: Last {lookback} hours ending {today}')
lines.append(f'Health: {data.get(\"health\", \"unknown\").upper()}')
lines.append(f'Total Events: {data.get(\"total_events\", 0)}')
lines.append('')
lines.append('EXECUTIVE SUMMARY')
lines.append('-' * 40)
lines.append(data.get('summary', 'No summary available.'))
lines.append('')

for section in data.get('sections', []):
    severity = section.get('severity', 'UNKNOWN')
    items = section.get('items', [])
    lines.append(f'{severity} ({len(items)})')
    lines.append('-' * 40)
    if not items:
        lines.append('  None')
    else:
        for item in items:
            lines.append(f'  [{item.get(\"service\", \"?\")}] {item.get(\"issue\", \"\")} (x{item.get(\"count\", \"?\")})')
            if severity in ('CRITICAL', 'HIGH'):
                lines.append(f'    -> {item.get(\"recommendation\", \"Review logs\")}')
    lines.append('')

lines.append('---')
lines.append(f'Generated by Spoke Log Analysis Agent (Claude {\"${CLAUDE_MODEL}\"})')

print('\\n'.join(lines))
")

if [[ "${DRY_RUN}" == "true" ]]; then
    printf "\n--- DRY RUN: Report would be sent to %s ---\n" "${ADMIN_EMAIL}"
    printf "%s\n" "${REPORT_TEXT}"
    exit 0
fi

# Send via mail relay
SUBJECT="[${INSTANCE_NAME}] Daily Log Report - ${TODAY_DATE}"

# Use python to properly JSON-encode the payloads
SEND_RESULT=$(python3 -c "
import json, sys, urllib.request

payload = json.dumps({
    'to': '${ADMIN_EMAIL}',
    'subject': $(python3 -c "import json; print(json.dumps('${SUBJECT}'))"),
    'body_text': $(printf "%s" "${REPORT_TEXT}" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))"),
    'body_html': $(printf "%s" "${REPORT_HTML}" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))")
}).encode('utf-8')

req = urllib.request.Request(
    '${RELAY_URL}/send',
    data=payload,
    headers={'Content-Type': 'application/json'},
    method='POST'
)

try:
    with urllib.request.urlopen(req, timeout=30) as resp:
        result = json.loads(resp.read())
        print(json.dumps(result))
except Exception as e:
    print(json.dumps({'status': 'error', 'detail': str(e)}))
    sys.exit(1)
")

SEND_STATUS=$(printf "%s" "${SEND_RESULT}" | jq -r '.status' 2>/dev/null || printf "unknown")

if [[ "${SEND_STATUS}" == "sent" ]]; then
    printf "  Report sent to %s\n" "${ADMIN_EMAIL}"
else
    printf "ERROR: Mail relay returned: %s\n" "${SEND_RESULT}" >&2
    exit 1
fi

printf "\n=== Log analysis complete ===\n"
