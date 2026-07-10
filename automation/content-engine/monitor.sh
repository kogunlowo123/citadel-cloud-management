#!/usr/bin/env bash
# Citadel Cloud Management — Growth Monitor Script
# Run: bash automation/content-engine/monitor.sh
# Schedule: 3:47pm CDT daily via Claude Code scheduled session or GitHub Actions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DASHBOARD="$REPO_ROOT/automation/content-engine/GROWTH-DASHBOARD.md"
DATE=$(TZ='America/Chicago' date +%Y-%m-%d)
TIME=$(TZ='America/Chicago' date +%H:%M)
RESEND_KEY="${RESEND_API_KEY:-}"

echo "=== Citadel Growth Monitor — $DATE $TIME CDT ==="
echo ""

# --- 1. Content Velocity ---
BLOG_COUNT=$(find "$REPO_ROOT/citadel-content/blog" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
PIPELINE_COUNT=$(find "$REPO_ROOT/articles" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
SOCIAL_COUNT=$(find "$REPO_ROOT/citadel-content/social-media" -name "distribution-batch-*.md" 2>/dev/null | wc -l | tr -d ' ')
TOTAL=$((BLOG_COUNT + PIPELINE_COUNT))

echo "📊 Content Metrics:"
echo "  Blog articles:      $BLOG_COUNT (target: 100)"
echo "  Pipeline articles:  $PIPELINE_COUNT"
echo "  Social batches:     $SOCIAL_COUNT"
echo "  TOTAL:              $TOTAL"
echo ""

# --- 2. Pillar Coverage ---
echo "🗂  Pillar Coverage:"
declare -A PILLARS=(
  ["AWS Infrastructure"]="vpc|eks|ecs|rds|lambda|cloudfront|s3-bucket|alb|cloudwatch"
  ["Azure Infrastructure"]="azure|aks|azure-openai|key-vault|hub-spoke"
  ["GCP Infrastructure"]="gcp|gke|vertex|cloud-run|bigquery|cloud-sql"
  ["MCP Servers"]="mcp"
  ["Multi-Cloud"]="multi-cloud|landing-zone"
  ["AI/ML Engineering"]="bedrock|agentforge|ai-agent|rag|llm"
  ["DevSecOps"]="security|waf|guardduty|devsecops"
  ["Career"]="career|certification|cert-guide"
)
P0_GAPS=()
for pillar in "${!PILLARS[@]}"; do
  pattern="${PILLARS[$pillar]}"
  count=$(find "$REPO_ROOT/citadel-content/blog" "$REPO_ROOT/articles" -name "*.md" 2>/dev/null | \
    xargs grep -il "$pattern" 2>/dev/null | wc -l | tr -d ' ')
  status=$([ "$count" -eq 0 ] && echo "🔴 P0 GAP" || echo "✅ ($count articles)")
  echo "  $pillar: $status"
  [ "$count" -eq 0 ] && P0_GAPS+=("$pillar")
done
echo ""

# --- 3. SEO Health Check ---
echo "🌐 SEO Health Check:"
for url in \
  "https://www.citadelcloudmanagement.com/sitemap.xml" \
  "https://www.citadelcloudmanagement.com/" \
  "https://www.citadelcloudmanagement.com/blogs/news"; do

  if command -v curl &>/dev/null; then
    status=$(curl -sS --max-time 10 -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "ERROR")
    echo "  $url → HTTP $status"
  else
    echo "  $url → curl not available"
  fi
done
echo ""

# --- 4. Issue Detection ---
echo "🚨 Issues:"
[ "$TOTAL" -lt 100 ] && echo "  🔴 P0: Total articles ($TOTAL) below 100 — compound writing needed"
[ "$TOTAL" -ge 100 ] && echo "  ✅ Article count on target"
[ "${#P0_GAPS[@]}" -gt 0 ] && echo "  🔴 P0 Pillar gaps: ${P0_GAPS[*]}"
[ "$SOCIAL_COUNT" -lt 4 ] && echo "  🟡 Social distribution behind — need at least 1 batch/week"
echo ""

# --- 5. Update Dashboard ---
echo "📝 Updating GROWTH-DASHBOARD.md..."
# Update last-updated line
sed -i.bak "s/> Auto-updated by the daily monitor.*/> Auto-updated by the daily monitor at 3:47pm CDT. Last updated: $DATE/" "$DASHBOARD" 2>/dev/null || true
rm -f "${DASHBOARD}.bak"
echo "  Done"
echo ""

# --- 6. Email Report ---
if [ -n "$RESEND_KEY" ]; then
  echo "📧 Sending email report..."
  STATUS_ICON=$([ "$TOTAL" -lt 100 ] && echo "🔴" || echo "✅")

  HTML="<h2>Citadel Cloud Management — Daily Growth Report</h2>
<p><strong>Date:</strong> $DATE $TIME CDT $STATUS_ICON</p>
<h3>Content Metrics</h3>
<table border='1' cellpadding='6' style='border-collapse:collapse'>
<tr><th>Metric</th><th>Count</th><th>Target</th></tr>
<tr><td>Blog articles</td><td>$BLOG_COUNT</td><td>100</td></tr>
<tr><td>Pipeline articles</td><td>$PIPELINE_COUNT</td><td>20</td></tr>
<tr><td>Social batches</td><td>$SOCIAL_COUNT</td><td>10</td></tr>
<tr><td><strong>TOTAL</strong></td><td><strong>$TOTAL</strong></td><td><strong>100</strong></td></tr>
</table>
<h3>Top 3 Actions for Tomorrow</h3>
<ol>
<li>Write 5 articles on highest-priority pillar gap$([ ${#P0_GAPS[@]} -gt 0 ] && echo ": ${P0_GAPS[0]}" || echo "")</li>
<li>Distribute this week's social batch (citadel-content/social-media/)</li>
<li>Publish 1 article to Dev.to — best day: Monday 14:00 UTC</li>
</ol>
<p><a href='https://github.com/kogunlowo123/citadel-cloud-management'>View Repository on GitHub</a></p>"

  response=$(curl -s -X POST 'https://api.resend.com/emails' \
    -H "Authorization: Bearer $RESEND_KEY" \
    -H 'Content-Type: application/json' \
    -d "{
      \"from\": \"Citadel Growth Monitor <onboarding@resend.dev>\",
      \"to\": [\"citadelcloudmanagement@gmail.com\"],
      \"subject\": \"[Citadel Growth] Daily Report — $DATE\",
      \"html\": \"$HTML\"
    }" 2>&1)
  echo "  Response: $response"
else
  echo "⚠️  Email skipped — RESEND_API_KEY not set"
  echo "   Set it with: export RESEND_API_KEY=re_..."
fi
echo ""

# --- 7. Compound Action ---
if [ "$TOTAL" -lt 100 ]; then
  echo "📝 Compound Action: Article count below 100 — flag for Claude Code to write articles"
  echo "   Run: claude 'Write a 1500-word production article on ${P0_GAPS[0]:-the highest-priority pillar gap}'"
  echo "   Save to: citadel-content/blog/$(printf '%02d' $((TOTAL+1)))-[topic].md"
fi

echo ""
echo "=== Monitor complete ==="
