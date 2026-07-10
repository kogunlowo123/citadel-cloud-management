# MCP Servers for DevOps: The Complete Guide to AI-Powered Infrastructure Management

**Pillar:** MCP Servers
**SEO Target:** "mcp servers devops", "model context protocol infrastructure", "claude mcp terraform"
**Word Count:** ~2,400

---

The Model Context Protocol (MCP) is quietly reshaping how engineers interact with infrastructure. Instead of switching between terminals, dashboards, and docs, you can ask an AI assistant to run Terraform, query Kubernetes, or inspect your AWS resources — and it actually does it.

I've built eight MCP servers covering the full DevOps toolchain. This guide explains what they do, how they work together, and when to use them.

## What Is MCP?

MCP (Model Context Protocol) is an open protocol from Anthropic that lets AI assistants like Claude connect to external tools and data sources. Think of it as giving an AI the ability to actually run commands and return real results — not just hallucinate them.

Each MCP server exposes a set of tools to the AI. When you ask "what's the CPU utilization on my EKS nodes?", the AI calls the relevant MCP tool, gets the real data, and reasons about it.

## The Eight MCP Servers

### 1. mcp-server-terraform

The most powerful in the collection. Run Terraform operations from any Claude conversation.

**Tools available:**
- `terraform_init` — initialize a working directory
- `terraform_plan` — generate and review execution plan
- `terraform_apply` — apply changes (requires confirmation)
- `terraform_state_list` — list resources in state
- `terraform_output` — read module outputs
- `terraform_validate` — validate configuration syntax

**Setup:**

```json
{
  "mcpServers": {
    "terraform": {
      "command": "node",
      "args": ["/path/to/mcp-server-terraform/dist/index.js"],
      "env": {
        "WORKING_DIR": "/path/to/terraform/modules"
      }
    }
  }
}
```

**Example conversation:**

> "Run terraform plan on the vpc module and tell me what will change"

The AI calls `terraform_plan`, reads the full output, and gives you a plain-English summary of what will be created, modified, or destroyed.

### 2. mcp-server-aws

Query AWS resources across your account without leaving your AI conversation.

**Tools available:**
- EC2: list instances, describe security groups, check instance health
- S3: list buckets, check bucket policies, list objects
- Lambda: list functions, get function details, check concurrency
- CloudWatch: get metrics, describe alarms, list log groups
- IAM: list roles, check policies, audit permissions

```json
{
  "mcpServers": {
    "aws": {
      "command": "node",
      "args": ["/path/to/mcp-server-aws/dist/index.js"],
      "env": {
        "AWS_PROFILE": "production",
        "AWS_REGION": "us-east-1"
      }
    }
  }
}
```

### 3. mcp-server-kubernetes

Full Kubernetes cluster management from Claude.

**Tools available:**
- `kubectl_get` — get resources (pods, deployments, services)
- `kubectl_describe` — describe resource details
- `kubectl_logs` — stream or fetch pod logs
- `kubectl_exec` — execute commands in containers
- `kubectl_scale` — scale deployments
- `kubectl_apply` — apply manifests

**Example:**

> "Show me all pods in the production namespace that have been restarting in the last hour"

The AI calls `kubectl_get` with appropriate filters and returns a ranked list of problematic pods with their restart counts.

### 4. mcp-server-github

Interact with GitHub repositories, issues, and PRs.

**Tools available:**
- `repo_list` — list repositories
- `issue_list` / `issue_create` — manage issues
- `pr_list` / `pr_review` — manage pull requests
- `code_search` — search code across repos
- `workflow_list` / `workflow_run` — manage GitHub Actions
- `commit_list` — browse commit history

### 5. mcp-server-azure

Azure resource management through Claude.

**Covers:** VMs, Storage, Key Vault, AKS, Monitor, Resource Groups, Networking

### 6. mcp-server-database

Query PostgreSQL, MySQL, and SQLite databases from Claude.

**Important:** The server runs read-only queries by default. Write operations require explicit enabling.

```json
{
  "env": {
    "DB_URL": "postgresql://user:pass@localhost:5432/mydb",
    "ALLOW_WRITES": "false"
  }
}
```

### 7. mcp-server-devops

Docker, Helm, Ansible, Jenkins, and general DevOps tooling in one server.

**Tools available:**
- Docker: build, run, ps, logs, exec
- Helm: install, upgrade, list, status, rollback
- Ansible: run playbooks, check inventory
- Jenkins: list builds, trigger jobs, get build logs

### 8. mcp-server-vector-db

Query vector databases for RAG pipelines.

**Supports:** Pinecone, Weaviate, Qdrant, ChromaDB

Useful when you want Claude to search your own knowledge base before answering questions.

## Real-World Workflow Example

Here's an incident response workflow using multiple MCP servers:

**Situation:** "Production is slow. Figure out what's wrong."

1. Claude calls `mcp-server-aws` → CloudWatch metrics → "High CPU on ECS tasks"
2. Claude calls `mcp-server-kubernetes` → pod logs → "OOMKilled events on 3 pods"
3. Claude calls `mcp-server-terraform` → current state → "Memory limits set to 512MB"
4. Claude proposes a fix, calls `terraform_plan` → shows the change
5. You approve, Claude calls `terraform_apply`
6. Claude calls `kubectl_get` to confirm pods are healthy

That entire workflow took minutes instead of the typical 45-minute terminal spelunking session.

## Security Considerations

- Run MCP servers with minimal IAM permissions
- Use read-only database connections by default
- Review all Terraform plans before applying (the AI will prompt you)
- Store credentials in environment variables, never in MCP config files
- Use separate AWS profiles for different environments

## Getting Started

1. Clone the server you need from the [Citadel-Cloud-Management](https://github.com/Citadel-Cloud-Management) org
2. Run `npm install && npm run build`
3. Add the MCP config to your `~/.claude.json`
4. Restart Claude Desktop

Full setup guides in each repo's README.

## What's Coming

- mcp-server-datadog: query metrics and manage monitors
- mcp-server-pagerduty: incident management
- mcp-server-argocd: GitOps deployments
- mcp-server-vault: HashiCorp Vault secrets management
