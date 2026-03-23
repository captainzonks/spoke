#!/usr/bin/env bash
# ==============================================================================
# CROWDSEC WEEKLY THREAT SUMMARY
# ==============================================================================
# Description: Generate and email weekly summary of CrowdSec threat decisions
# Author: Matt Barham
# Created: 2025-12-14
# Modified: 2026-03-16
# Version: 2.0.0
# ==============================================================================
# Purpose: Aggregate CrowdSec decisions from the past week, deduplicate IPs,
#          and send a single summary email via ProtonMail Bridge
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# Configuration
CROWDSEC_CONTAINER="crowdsec"
PROTONMAIL_BRIDGE_HOST="protonmail-bridge"
PROTONMAIL_BRIDGE_PORT="587"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPOKE_DIR="${SPOKE_DIR:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
# Configuration files
BASE_ENV_FILE="${SPOKE_DIR}/shared/env/base.env"
HUB_ENV_FILE="${SPOKE_DIR}/shared/env/hub.env"

# Load environment variables (base.env first — hub.env references its variables)
for env_file in "${BASE_ENV_FILE}" "${HUB_ENV_FILE}"; do
    if [[ -f "${env_file}" ]]; then
        # shellcheck disable=SC1090
        source "${env_file}"
    else
        printf "ERROR: Environment file not found: %s\n" "${env_file}" >&2
        exit 1
    fi
done

# Verify required environment variables
: "${ADMIN_EMAIL:?ERROR: ADMIN_EMAIL not set in environment}"
: "${SERVICES_EMAIL:?ERROR: SERVICES_EMAIL not set in environment}"

# Get bridge password from secret
BRIDGE_PASSWORD_FILE="${SPOKE_DIR}/secrets/proton/proton_bridge_password"
if [[ -f "${BRIDGE_PASSWORD_FILE}" ]]; then
    PROTONMAIL_BRIDGE_PASSWORD="$(cat "${BRIDGE_PASSWORD_FILE}")"
else
    printf "ERROR: ProtonMail bridge password file not found: %s\n" "${BRIDGE_PASSWORD_FILE}" >&2
    exit 1
fi

# Get alerts from the past 7 days
printf "Fetching CrowdSec alerts from the past 7 days...\n"
ALERTS_JSON=$(docker exec "${CROWDSEC_CONTAINER}" cscli alerts list --since 7d -o json 2>/dev/null) || {
    printf "ERROR: Failed to retrieve CrowdSec alerts\n" >&2
    exit 1
}

# Check if there are any alerts
ALERT_COUNT=$(printf "%s" "${ALERTS_JSON}" | jq 'length')
if [[ "${ALERT_COUNT}" -eq 0 ]]; then
    printf "No alerts found in the past 7 days. No email will be sent.\n"
    exit 0
fi

# Parse and aggregate alerts by IP
printf "Processing %s alerts...\n" "${ALERT_COUNT}"

# Create aggregated data structure: IP -> {count, scenarios[], first_seen, last_seen, country, asn}
AGGREGATED=$(printf "%s" "${ALERTS_JSON}" | jq -r '
def get_meta($key):
    if .events and (.events | length > 0) and .events[0].meta and (.events[0].meta | length > 0) then
        (.events[0].meta | map(select(.key == $key)) | .[0].value // "Unknown")
    else
        "Unknown"
    end;

[.[] |
    select(.decisions != null) |
    .decisions[] as $decision |
    {
        ip: $decision.value,
        scenario: $decision.scenario,
        type: $decision.type,
        origin: $decision.origin,
        created: .created_at,
        country: get_meta("IsoCode"),
        asn: get_meta("ASNOrg")
    }
] |
group_by(.ip) |
map({
    ip: .[0].ip,
    count: length,
    scenarios: [.[].scenario] | unique,
    types: [.[].type] | unique,
    first_seen: ([.[].created] | sort | .[0]),
    last_seen: ([.[].created] | sort | .[-1]),
    country: .[0].country // "Unknown",
    asn: .[0].asn // "Unknown"
}) |
sort_by(.count) | reverse
')

# Generate HTML email body
WEEK_START=$(date -d "7 days ago" "+%Y-%m-%d")
WEEK_END=$(date "+%Y-%m-%d")
TOTAL_UNIQUE_IPS=$(printf "%s" "${AGGREGATED}" | jq 'length')
TOTAL_DECISIONS=$(printf "%s" "${AGGREGATED}" | jq '[.[].count] | add')

HTML_BODY=$(cat <<EOF
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { background-color: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #d32f2f; border-bottom: 3px solid #d32f2f; padding-bottom: 10px; }
        h2 { color: #424242; margin-top: 30px; }
        .summary { background-color: #f5f5f5; padding: 15px; border-radius: 5px; margin: 20px 0; }
        .summary p { margin: 8px 0; }
        .stats { font-weight: bold; color: #d32f2f; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th { background-color: #d32f2f; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .ip-link { color: #1976d2; text-decoration: none; font-weight: bold; }
        .ip-link:hover { text-decoration: underline; }
        .count-badge {
            background-color: #ff5722;
            color: white;
            padding: 4px 8px;
            border-radius: 12px;
            font-weight: bold;
            font-size: 0.9em;
        }
        .scenario {
            background-color: #e3f2fd;
            padding: 2px 6px;
            border-radius: 3px;
            margin: 2px;
            display: inline-block;
            font-size: 0.85em;
        }
        .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; color: #757575; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Spoke CrowdSec Weekly Threat Summary</h1>

        <div class="summary">
            <p><strong>Report Period:</strong> ${WEEK_START} to ${WEEK_END}</p>
            <p><strong>Total Unique IPs Blocked:</strong> <span class="stats">${TOTAL_UNIQUE_IPS}</span></p>
            <p><strong>Total Security Decisions:</strong> <span class="stats">${TOTAL_DECISIONS}</span></p>
        </div>

        <h2>Blocked IP Addresses (Sorted by Frequency)</h2>

        <table>
            <thead>
                <tr>
                    <th>IP Address</th>
                    <th>Count</th>
                    <th>Country</th>
                    <th>ASN</th>
                    <th>Scenarios Triggered</th>
                    <th>First Seen</th>
                    <th>Last Seen</th>
                </tr>
            </thead>
            <tbody>
EOF
)

# Add table rows for each IP
while IFS= read -r row; do
    IP=$(printf "%s" "${row}" | jq -r '.ip')
    COUNT=$(printf "%s" "${row}" | jq -r '.count')
    COUNTRY=$(printf "%s" "${row}" | jq -r '.country')
    ASN=$(printf "%s" "${row}" | jq -r '.asn')
    SCENARIOS=$(printf "%s" "${row}" | jq -r '.scenarios | join(", ")')
    FIRST_SEEN=$(printf "%s" "${row}" | jq -r '.first_seen' | cut -d'T' -f1)
    LAST_SEEN=$(printf "%s" "${row}" | jq -r '.last_seen' | cut -d'T' -f1)

    # Truncate ASN if too long
    if [[ ${#ASN} -gt 30 ]]; then
        ASN="${ASN:0:27}..."
    fi

    HTML_BODY+=$(cat <<EOF

                <tr>
                    <td><a href="https://www.whois.com/whois/${IP}" class="ip-link" target="_blank">${IP}</a></td>
                    <td><span class="count-badge">${COUNT}</span></td>
                    <td>${COUNTRY}</td>
                    <td>${ASN}</td>
                    <td><span class="scenario">${SCENARIOS}</span></td>
                    <td>${FIRST_SEEN}</td>
                    <td>${LAST_SEEN}</td>
                </tr>
EOF
)
done < <(printf "%s" "${AGGREGATED}" | jq -c '.[]')

# Close HTML
HTML_BODY+=$(cat <<EOF

            </tbody>
        </table>

        <div class="footer">
            <p>This is an automated weekly summary from Spoke CrowdSec</p>
            <p>Generated on $(date "+%Y-%m-%d %H:%M:%S %Z")</p>
        </div>
    </div>
</body>
</html>
EOF
)

# Send email using Python on the host system
printf "Sending weekly summary email to %s...\n" "${ADMIN_EMAIL}"

# Export environment variables for Python script
export SMTP_PORT="${PROTONMAIL_BRIDGE_PORT}"
export SENDER_EMAIL="${SERVICES_EMAIL}"
export RECEIVER_EMAIL="${ADMIN_EMAIL}"
export SMTP_PASSWORD="${PROTONMAIL_BRIDGE_PASSWORD}"
export WEEK_START="${WEEK_START}"
export WEEK_END="${WEEK_END}"
export HTML_BODY

# Use host's Python3 to send email via ProtonMail Bridge running in Docker
python3 <<'PYTHON_SCRIPT'
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
import subprocess
import sys
import os

# Get environment variables passed from bash
smtp_port = int(os.environ.get('SMTP_PORT', '587'))
sender_email = os.environ.get('SENDER_EMAIL', '')
receiver_email = os.environ.get('RECEIVER_EMAIL', '')
password = os.environ.get('SMTP_PASSWORD', '')
week_start = os.environ.get('WEEK_START', '')
week_end = os.environ.get('WEEK_END', '')
html_body = os.environ.get('HTML_BODY', '')

# Get ProtonMail Bridge IP from Docker network
try:
    bridge_ip = subprocess.check_output([
        'docker', 'inspect', 'protonmail-bridge',
        '--format', '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
    ], text=True).strip().split()[0]  # Take first IP if multiple networks
except Exception as e:
    print(f"Error getting ProtonMail Bridge IP: {e}")
    sys.exit(1)

smtp_host = bridge_ip
sender_name = "Spoke CrowdSec"

# Create message
msg = MIMEMultipart('alternative')
msg['Subject'] = f"Spoke CrowdSec Weekly Summary - {week_start} to {week_end}"
msg['From'] = f"{sender_name} <{sender_email}>"
msg['To'] = receiver_email

# Attach HTML part
html_part = MIMEText(html_body, 'html')
msg.attach(html_part)

# Send email
try:
    with smtplib.SMTP(smtp_host, smtp_port) as server:
        server.login(sender_email, password)
        server.send_message(msg)
    print(f"Email sent successfully to {receiver_email}")
except Exception as e:
    print(f"Error sending email: {e}")
    sys.exit(1)
PYTHON_SCRIPT

if [[ $? -ne 0 ]]; then
    printf "ERROR: Failed to send email\n" >&2
    exit 1
fi

printf "Weekly CrowdSec summary email sent successfully!\n"
printf "   Unique IPs: %s\n" "${TOTAL_UNIQUE_IPS}"
printf "   Total Decisions: %s\n" "${TOTAL_DECISIONS}"
