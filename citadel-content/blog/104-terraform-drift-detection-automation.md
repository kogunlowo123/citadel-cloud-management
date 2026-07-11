# Terraform Drift Detection: Automated Infrastructure Reconciliation

**Pillar:** DevSecOps
**SEO Target:** terraform drift detection automation, terraform infrastructure drift github actions, detect terraform drift ci cd
**Word Count:** ~1,700

Infrastructure drift — when real cloud resources diverge from Terraform state — is one of the most common production incidents. Manual console changes, auto-scaling events, and failed applies all cause drift. This guide implements automated drift detection with GitHub Actions, Slack alerting, and automatic reconciliation for non-critical drift.

## Drift Detection Architecture

```
Schedule (daily/hourly)
        ↓
GitHub Actions: tofu/terraform plan -detailed-exitcode
        ↓
Exit code 0 → No drift (no action)
Exit code 1 → Plan error (alert on-call)
Exit code 2 → Drift detected (parse plan, alert Slack)
        ↓
Auto-reconcile? → Check drift category
  Critical infra (VPC, IAM) → Human review required
  Non-critical (tags, scaling) → Auto-apply permitted
```

## GitHub Actions Drift Detection Workflow

```yaml
# .github/workflows/drift-detection.yml
name: Infrastructure Drift Detection

on:
  schedule:
    - cron: '0 6 * * *'   # Daily at 6 AM UTC
    - cron: '0 */4 * * *' # Every 4 hours for production
  workflow_dispatch:
    inputs:
      auto_remediate:
        description: 'Auto-apply non-critical drift'
        type: boolean
        default: false

jobs:
  detect-drift:
    name: Detect Drift — ${{ matrix.environment }}
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
      issues: write
    strategy:
      matrix:
        environment: [production, staging]
      fail-fast: false
    environment: ${{ matrix.environment }}-readonly
    steps:
      - uses: actions/checkout@v4

      - name: Setup OpenTofu
        uses: opentofu/setup-opentofu@v1
        with:
          tofu_version: "1.8.0"

      - name: Configure AWS (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.READONLY_ROLE_ARN }}
          aws-region: us-east-1

      - name: Initialize
        run: tofu init -input=false
        working-directory: environments/${{ matrix.environment }}

      - name: Detect Drift
        id: drift
        run: |
          set +e
          tofu plan \
            -detailed-exitcode \
            -no-color \
            -compact-warnings \
            -out=drift.plan \
            2>&1 | tee drift-output.txt
          EXIT_CODE=$?
          set -e

          echo "exit_code=$EXIT_CODE" >> $GITHUB_OUTPUT

          case $EXIT_CODE in
            0) echo "status=clean" >> $GITHUB_OUTPUT ;;
            1) echo "status=error" >> $GITHUB_OUTPUT ;;
            2) echo "status=drift" >> $GITHUB_OUTPUT ;;
          esac

          # Count drift items
          CREATES=$(grep "will be created" drift-output.txt | wc -l | tr -d ' ')
          UPDATES=$(grep "will be updated" drift-output.txt | wc -l | tr -d ' ')
          DESTROYS=$(grep "will be destroyed" drift-output.txt | wc -l | tr -d ' ')

          echo "creates=$CREATES" >> $GITHUB_OUTPUT
          echo "updates=$UPDATES" >> $GITHUB_OUTPUT
          echo "destroys=$DESTROYS" >> $GITHUB_OUTPUT
        working-directory: environments/${{ matrix.environment }}

      - name: No Drift — Report Clean
        if: steps.drift.outputs.status == 'clean'
        run: |
          echo "✅ No drift detected in ${{ matrix.environment }}"
          echo "## Drift Detection — ${{ matrix.environment }}" >> $GITHUB_STEP_SUMMARY
          echo "✅ **No drift detected** — infrastructure matches Terraform state" >> $GITHUB_STEP_SUMMARY

      - name: Drift Detected — Parse and Alert
        if: steps.drift.outputs.status == 'drift'
        env:
          SLACK_WEBHOOK: ${{ secrets.SLACK_WEBHOOK_URL }}
          ENVIRONMENT: ${{ matrix.environment }}
        run: |
          DRIFT_SUMMARY=$(cat drift-output.txt | grep -A2 "Plan:" | head -5)
          CREATES="${{ steps.drift.outputs.creates }}"
          UPDATES="${{ steps.drift.outputs.updates }}"
          DESTROYS="${{ steps.drift.outputs.destroys }}"

          echo "## ⚠️ Drift Detected — $ENVIRONMENT" >> $GITHUB_STEP_SUMMARY
          echo "| Type | Count |" >> $GITHUB_STEP_SUMMARY
          echo "|------|-------|" >> $GITHUB_STEP_SUMMARY
          echo "| To create | $CREATES |" >> $GITHUB_STEP_SUMMARY
          echo "| To update | $UPDATES |" >> $GITHUB_STEP_SUMMARY
          echo "| To destroy | $DESTROYS |" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "[View full plan](${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }})" >> $GITHUB_STEP_SUMMARY

          # Slack alert
          if [ -n "$SLACK_WEBHOOK" ]; then
            curl -sf -X POST "$SLACK_WEBHOOK" \
              -H "Content-Type: application/json" \
              -d "{
                \"text\": \"⚠️ Infrastructure drift detected in *${ENVIRONMENT}*\",
                \"blocks\": [{
                  \"type\": \"section\",
                  \"text\": {
                    \"type\": \"mrkdwn\",
                    \"text\": \"*Infrastructure Drift Detected*\\n*Environment:* ${ENVIRONMENT}\\n*Creates:* ${CREATES} | *Updates:* ${UPDATES} | *Destroys:* ${DESTROYS}\\n<${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}|View Details>\"
                  }
                }]
              }"
          fi

      - name: Plan Error — Alert On-Call
        if: steps.drift.outputs.status == 'error'
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          # Create GitHub issue for plan errors (may indicate state corruption)
          gh issue create \
            --title "P0: Terraform plan error in ${{ matrix.environment }}" \
            --body "Drift detection plan failed. This may indicate state corruption or provider errors. Run ID: ${{ github.run_id }}" \
            --label "infrastructure,urgent" || true

      - name: Auto-Remediate Non-Critical Drift
        if: steps.drift.outputs.status == 'drift' && inputs.auto_remediate == 'true' && matrix.environment == 'staging'
        run: |
          # Only auto-apply in staging, never production
          # Check for destructive changes before auto-applying
          if grep -q "will be destroyed" drift-output.txt; then
            echo "❌ Auto-remediate skipped — destructive changes detected. Human review required."
            exit 0
          fi

          echo "✅ Applying non-destructive drift in staging..."
          tofu apply -auto-approve drift.plan
        working-directory: environments/${{ matrix.environment }}
```

## Terraform Module: Drift Alerting Infrastructure

```hcl
# SNS topic for drift alerts
resource "aws_sns_topic" "drift_alerts" {
  name              = "${var.prefix}-terraform-drift"
  kms_master_key_id = aws_kms_key.sns.arn
  tags              = var.tags
}

resource "aws_sns_topic_subscription" "drift_email" {
  topic_arn = aws_sns_topic.drift_alerts.arn
  protocol  = "email"
  endpoint  = var.ops_email
}

resource "aws_sns_topic_subscription" "drift_slack" {
  topic_arn = aws_sns_topic.drift_alerts.arn
  protocol  = "https"
  endpoint  = var.slack_webhook_url
}

# EventBridge rule to catch Config rule non-compliance (complementary to plan-based drift)
resource "aws_cloudwatch_event_rule" "config_compliance" {
  name        = "${var.prefix}-config-compliance"
  description = "Alert on AWS Config rule non-compliance (complementary drift signal)"

  event_pattern = jsonencode({
    source      = ["aws.config"]
    detail-type = ["Config Rules Compliance Change"]
    detail = {
      newEvaluationResult = {
        complianceType = ["NON_COMPLIANT"]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "config_to_sns" {
  rule      = aws_cloudwatch_event_rule.config_compliance.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.drift_alerts.arn
}
```

## Drift Categorization Lambda

```hcl
resource "aws_lambda_function" "drift_categorizer" {
  function_name = "${var.prefix}-drift-categorizer"
  role          = aws_iam_role.drift_lambda.arn
  runtime       = "python3.12"
  handler       = "index.handler"
  timeout       = 60
  filename      = data.archive_file.drift_lambda.output_path

  environment {
    variables = {
      SNS_TOPIC_ARN  = aws_sns_topic.drift_alerts.arn
      CRITICAL_RESOURCES = "aws_vpc,aws_iam_role,aws_iam_policy,aws_kms_key,aws_security_group"
    }
  }
}
```

```python
# drift_categorizer/index.py
import json
import os
import boto3

CRITICAL = set(os.environ['CRITICAL_RESOURCES'].split(','))
sns = boto3.client('sns')

def handler(event, context):
    plan = event.get('plan', {})
    changes = plan.get('resource_changes', [])

    critical_drift = []
    non_critical_drift = []

    for change in changes:
        resource_type = change['type']
        actions = change['change']['actions']

        if resource_type in CRITICAL or 'delete' in actions:
            critical_drift.append({
                'resource': f"{change['type']}.{change['name']}",
                'actions': actions
            })
        else:
            non_critical_drift.append({
                'resource': f"{change['type']}.{change['name']}",
                'actions': actions
            })

    result = {
        'critical': critical_drift,
        'non_critical': non_critical_drift,
        'auto_remediate': len(critical_drift) == 0
    }

    if critical_drift:
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject='P0: Critical infrastructure drift detected',
            Message=json.dumps(result, indent=2)
        )

    return result
```

## Variables

```hcl
variable "prefix" {
  type = string
}

variable "ops_email" {
  description = "Email address for drift alerts"
  type        = string
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for drift alerts"
  type        = string
  sensitive   = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

## Production Checklist

- [ ] Drift detection runs at minimum daily (`cron: '0 6 * * *'`)
- [ ] OIDC authentication (not static AWS keys) for GitHub Actions
- [ ] Read-only IAM role used for plan-only runs
- [ ] Separate write role gated behind environment approval for auto-remediate
- [ ] Slack webhook configured for immediate drift alerts
- [ ] Critical resources list maintained (`aws_vpc`, `aws_iam_role`, `aws_kms_key`)
- [ ] Auto-remediation disabled for production (staging only)
- [ ] Destructive change guard: never auto-apply destroys
- [ ] GitHub issue created on plan errors (state corruption signal)
- [ ] AWS Config rules enabled as secondary drift signal

Automated drift detection turns a reactive "why is prod broken" into a proactive daily signal — critical for any team managing more than 3 environments.
