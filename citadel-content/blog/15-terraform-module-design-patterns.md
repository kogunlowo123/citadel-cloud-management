# Terraform Module Design Patterns: What I Learned from Writing 60+ Production Modules

**Pillar:** AWS/Azure/GCP Infrastructure
**SEO Target:** "terraform module design patterns", "terraform modules best practices production"
**Word Count:** ~2,300

---

Writing your first Terraform module is easy. Writing one that's used by 50 teams, survives 12 months of feature requests, and still passes `terraform plan` cleanly is a different problem entirely.

After writing 60+ production modules covering AWS, Azure, GCP, and multi-cloud patterns, these are the design decisions that actually matter.

## 1. Be Opinionated at the Right Layer

The most common mistake: trying to expose every possible configuration option. This produces modules that are technically flexible but practically unusable.

**The wrong approach:**
```hcl
variable "aws_lb_algorithm_type" {
  type    = string
  default = "round_robin"
}

variable "aws_lb_slow_start" {
  type    = number
  default = 0
}

# ... 40 more variables nobody needs
```

**The right approach:** Expose the 20% of parameters that account for 80% of customization needs. Hard-code sensible production defaults for everything else.

```hcl
# Module users care about these
variable "cluster_name" { type = string }
variable "node_count" { type = number; default = 3 }
variable "instance_type" { type = string; default = "t3.medium" }

# Production defaults that should almost never change
locals {
  health_check_interval   = 30
  health_check_threshold  = 3
  connection_draining_timeout = 300
}
```

## 2. Outputs Are Your API — Design Them Deliberately

Module outputs are consumed by other modules and root configurations. Treat them like a public API.

**Output every resource that a caller might need to reference:**

```hcl
# Bad: caller has to dig into module internals
output "subnet_ids" {
  value = aws_subnet.private[*].id
}

# Good: give callers everything they'd reasonably need
output "vpc_id" {
  value       = aws_vpc.main.id
  description = "The VPC ID"
}

output "private_subnet_ids" {
  value       = aws_subnet.private[*].id
  description = "List of private subnet IDs (one per AZ)"
}

output "public_subnet_ids" {
  value       = aws_subnet.public[*].id
  description = "List of public subnet IDs (one per AZ)"
}

output "nat_gateway_ips" {
  value       = aws_eip.nat[*].public_ip
  description = "Elastic IPs of NAT Gateways (for allowlisting)"
}
```

## 3. Use `for_each` for Multi-Resource Patterns

`count` creates brittle resources — deleting element 1 of 5 shifts all indices and triggers unnecessary destruction. Use `for_each` with a map:

```hcl
# BAD: count-based (index-sensitive)
resource "aws_security_group_rule" "ingress" {
  count       = length(var.ingress_rules)
  type        = "ingress"
  from_port   = var.ingress_rules[count.index].from_port
  ...
}

# GOOD: for_each with descriptive key
resource "aws_security_group_rule" "ingress" {
  for_each  = { for rule in var.ingress_rules : rule.description => rule }
  type      = "ingress"
  from_port = each.value.from_port
  ...
}
```

## 4. Tag Inheritance via Merge

Every module should accept a `tags` variable and merge it with module-specific tags:

```hcl
variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags to apply to all resources"
}

locals {
  module_tags = {
    Module    = "terraform-aws-vpc-complete"
    ManagedBy = "terraform"
  }
  tags = merge(local.module_tags, var.tags)
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags       = merge(local.tags, { Name = var.vpc_name })
}
```

The caller's tags always override module defaults. This means billing tags (CostCenter, Owner, Environment) propagate correctly without any special handling.

## 5. Lifecycle Management

Production resources need lifecycle controls:

```hcl
resource "aws_instance" "main" {
  # ...

  lifecycle {
    # Prevent accidental deletion of stateful resources
    prevent_destroy = true  # Use for databases, EFS, etc.

    # Don't destroy before replacement (for stateless resources)
    create_before_destroy = true

    # Ignore AMI updates (apply separately, not in every plan)
    ignore_changes = [ami]
  }
}
```

For databases and persistent storage, `prevent_destroy = true` is non-negotiable. Add it to every module that manages data.

## 6. Provider Version Pinning

Never use `>= 4.0` in a module. Use a range:

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 6.0"  # Compatible with v5, not v6 (breaking changes)
    }
  }
}
```

This lets callers upgrade providers within a major version without breaking your module, but prevents silent breaks when a major version is released.

## 7. Validation with Meaningful Errors

Use variable validation to catch mistakes before `terraform apply`:

```hcl
variable "environment" {
  type    = string

  validation {
    condition = contains(["production", "staging", "development"], var.environment)
    error_message = "environment must be 'production', 'staging', or 'development'. Got: ${var.environment}"
  }
}

variable "vpc_cidr" {
  type = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block (e.g., '10.0.0.0/16'). Got: ${var.vpc_cidr}"
  }
}
```

Good error messages save hours of debugging. Always include the received value in the error message.

## 8. Separate Environments with Workspaces or Directories

Two patterns work in production:

**Directory-based (preferred for large teams):**
```
environments/
├── production/
│   ├── main.tf       # Calls modules
│   ├── variables.tf
│   └── terraform.tfvars
├── staging/
└── development/
```

**Workspace-based (simpler for small teams):**
```bash
terraform workspace new production
terraform workspace new staging
terraform apply -var-file="production.tfvars"
```

Directory-based is safer — it's impossible to accidentally apply production state to staging. Workspace-based is faster to iterate on.

## 9. Remote State with Locking

Always use remote state. The module should never manage this — it's the root configuration's responsibility.

```hcl
# In root configuration (not the module)
terraform {
  backend "s3" {
    bucket         = "terraform-state-production"
    key            = "vpc/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-locks"
  }
}
```

## 10. Testing

Modules without tests become unmaintainable. Three approaches:

**Terratest (Go):**
```go
func TestVPCModule(t *testing.T) {
    opts := &terraform.Options{
        TerraformDir: "../examples/complete",
        Vars: map[string]interface{}{
            "vpc_cidr": "10.0.0.0/16",
        },
    }
    defer terraform.Destroy(t, opts)
    terraform.InitAndApply(t, opts)

    vpcID := terraform.Output(t, opts, "vpc_id")
    assert.NotEmpty(t, vpcID)
}
```

**terraform-compliance (policy-as-code):**
```gherkin
Feature: VPC Security
  Scenario: Flow logs must be enabled
    Given I have aws_flow_log defined
    Then it must contain log_destination
```

## Repository Structure for 60+ Modules

```
terraform-aws-vpc-complete/   ← One repo per module
├── main.tf
├── variables.tf
├── outputs.tf
├── versions.tf
├── README.md                 ← Auto-generated by terraform-docs
├── examples/
│   ├── complete/             ← Full example (used for testing)
│   └── minimal/             ← Minimal usage example
└── tests/
    └── complete_test.go      ← Terratest
```

One module per repository. It's more repos to manage but simpler versioning, cleaner changelogs, and no cross-module dependency hell.

## The Module That Started It All

[terraform-aws-vpc-complete](https://github.com/kogunlowo123/terraform-aws-vpc-complete) — and 60 more at [Citadel-Cloud-Management](https://github.com/Citadel-Cloud-Management).
