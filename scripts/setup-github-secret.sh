#!/usr/bin/env bash
# Add GitHub Actions secrets for this repo
# Usage: bash scripts/setup-github-secret.sh

set -euo pipefail

REPO="kogunlowo123/citadel-cloud-management"

echo "Setting up GitHub Actions secrets for $REPO"
echo ""

if ! command -v gh &>/dev/null; then
  echo "gh CLI not found. Install with: apt install gh"
  echo ""
  echo "Alternatively, add secrets manually at:"
  echo "https://github.com/$REPO/settings/secrets/actions"
  exit 1
fi

# Add Resend API key
read -p "Enter RESEND_API_KEY (press Enter to skip): " resend_key
if [ -n "$resend_key" ]; then
  echo "$resend_key" | gh secret set RESEND_API_KEY --repo "$REPO"
  echo "✅ RESEND_API_KEY set"
fi

echo ""
echo "Setup complete. Verify at:"
echo "https://github.com/$REPO/settings/secrets/actions"
