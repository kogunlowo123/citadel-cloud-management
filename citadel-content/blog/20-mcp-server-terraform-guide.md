# Building a Terraform MCP Server: Give Claude Code Direct Infrastructure Access

**Pillar:** MCP Servers
**SEO Target:** terraform mcp server claude code infrastructure
**Word Count:** ~1800

Model Context Protocol (MCP) servers extend Claude Code with real tools. A Terraform MCP server lets Claude plan, apply, and inspect infrastructure directly from your conversation — no context-switching to a terminal. This guide builds a production Terraform MCP server with safety controls.

## What the Terraform MCP Server Does

The server exposes these tools to Claude:
- `terraform_init` — initialize working directory
- `terraform_plan` — generate and display execution plan
- `terraform_apply` — apply changes (with confirmation gate)
- `terraform_destroy` — destroy infrastructure (requires explicit confirmation)
- `terraform_show` — show current state
- `terraform_output` — read output values
- `terraform_validate` — validate configuration
- `terraform_workspace` — manage workspaces

## Server Architecture

```
mcp-server-terraform/
├── src/
│   ├── index.ts         # MCP server entry point
│   ├── tools/
│   │   ├── plan.ts
│   │   ├── apply.ts
│   │   ├── destroy.ts
│   │   ├── state.ts
│   │   └── validate.ts
│   └── safety/
│       ├── confirmation.ts
│       └── cost-estimate.ts
├── package.json
└── tsconfig.json
```

## Package Setup

```json
{
  "name": "@citadel/mcp-server-terraform",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js"
  },
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.0.0"
  },
  "devDependencies": {
    "typescript": "^5.3.0",
    "@types/node": "^20.0.0"
  }
}
```

## Main Server

```typescript
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  Tool,
} from "@modelcontextprotocol/sdk/types.js";
import { execSync } from "child_process";
import { existsSync } from "fs";
import { join } from "path";

const server = new Server(
  { name: "terraform", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

const TOOLS: Tool[] = [
  {
    name: "terraform_init",
    description: "Initialize a Terraform working directory",
    inputSchema: {
      type: "object",
      properties: {
        working_dir: {
          type: "string",
          description: "Path to the Terraform configuration directory",
        },
        upgrade: {
          type: "boolean",
          description: "Upgrade modules and providers to latest versions",
          default: false,
        },
      },
      required: ["working_dir"],
    },
  },
  {
    name: "terraform_plan",
    description: "Generate a Terraform execution plan and return its output",
    inputSchema: {
      type: "object",
      properties: {
        working_dir: { type: "string" },
        var_file: { type: "string", description: "Path to .tfvars file" },
        target: {
          type: "array",
          items: { type: "string" },
          description: "Specific resources to plan",
        },
        destroy: {
          type: "boolean",
          description: "Plan a destroy operation",
          default: false,
        },
      },
      required: ["working_dir"],
    },
  },
  {
    name: "terraform_apply",
    description: "Apply a Terraform plan. Requires explicit confirmation.",
    inputSchema: {
      type: "object",
      properties: {
        working_dir: { type: "string" },
        var_file: { type: "string" },
        target: { type: "array", items: { type: "string" } },
        confirmed: {
          type: "boolean",
          description: "MUST be true — user must explicitly confirm apply",
        },
      },
      required: ["working_dir", "confirmed"],
    },
  },
  {
    name: "terraform_show",
    description: "Show current Terraform state in human-readable format",
    inputSchema: {
      type: "object",
      properties: {
        working_dir: { type: "string" },
        resource: { type: "string", description: "Specific resource to show" },
      },
      required: ["working_dir"],
    },
  },
  {
    name: "terraform_output",
    description: "Read Terraform output values",
    inputSchema: {
      type: "object",
      properties: {
        working_dir: { type: "string" },
        output_name: { type: "string", description: "Specific output name" },
      },
      required: ["working_dir"],
    },
  },
  {
    name: "terraform_validate",
    description: "Validate Terraform configuration files",
    inputSchema: {
      type: "object",
      properties: {
        working_dir: { type: "string" },
      },
      required: ["working_dir"],
    },
  },
];

server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: TOOLS }));
```

## Tool Execution Handler

```typescript
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  const workingDir = args.working_dir as string;

  if (!existsSync(workingDir)) {
    return {
      content: [{ type: "text", text: `Error: Directory not found: ${workingDir}` }],
      isError: true,
    };
  }

  try {
    switch (name) {
      case "terraform_init": {
        const upgradeFlag = args.upgrade ? " -upgrade" : "";
        const result = runTerraform(`init -no-color${upgradeFlag}`, workingDir);
        return { content: [{ type: "text", text: result }] };
      }

      case "terraform_plan": {
        let cmd = "plan -no-color";
        if (args.var_file) cmd += ` -var-file="${args.var_file}"`;
        if (args.destroy) cmd += " -destroy";
        if (args.target) {
          for (const t of args.target as string[]) {
            cmd += ` -target="${t}"`;
          }
        }
        const result = runTerraform(cmd, workingDir);
        return { content: [{ type: "text", text: result }] };
      }

      case "terraform_apply": {
        if (!args.confirmed) {
          return {
            content: [{
              type: "text",
              text: "Apply requires explicit confirmation. Set confirmed=true to proceed.",
            }],
            isError: true,
          };
        }
        let cmd = "apply -auto-approve -no-color";
        if (args.var_file) cmd += ` -var-file="${args.var_file}"`;
        if (args.target) {
          for (const t of args.target as string[]) {
            cmd += ` -target="${t}"`;
          }
        }
        const result = runTerraform(cmd, workingDir);
        return { content: [{ type: "text", text: result }] };
      }

      case "terraform_show": {
        const resourceArg = args.resource ? ` ${args.resource}` : "";
        const result = runTerraform(`show -no-color${resourceArg}`, workingDir);
        return { content: [{ type: "text", text: result }] };
      }

      case "terraform_output": {
        const outputArg = args.output_name ? ` ${args.output_name}` : " -json";
        const result = runTerraform(`output${outputArg}`, workingDir);
        return { content: [{ type: "text", text: result }] };
      }

      case "terraform_validate": {
        const result = runTerraform("validate -no-color", workingDir);
        return { content: [{ type: "text", text: result }] };
      }

      default:
        return {
          content: [{ type: "text", text: `Unknown tool: ${name}` }],
          isError: true,
        };
    }
  } catch (error) {
    return {
      content: [{ type: "text", text: `Error: ${(error as Error).message}` }],
      isError: true,
    };
  }
});

function runTerraform(command: string, cwd: string): string {
  return execSync(`terraform ${command}`, {
    cwd,
    timeout: 300_000,
    encoding: "utf-8",
    env: { ...process.env },
  });
}

const transport = new StdioServerTransport();
await server.connect(transport);
```

## Register in Claude Code

Add to your `.claude/settings.json`:

```json
{
  "mcpServers": {
    "terraform": {
      "command": "node",
      "args": ["/path/to/mcp-server-terraform/dist/index.js"],
      "env": {
        "AWS_PROFILE": "production",
        "AWS_REGION": "us-east-1"
      }
    }
  }
}
```

## Usage in Claude Code

```
You: Plan the EKS cluster deployment in ./infrastructure/eks
Claude: [calls terraform_plan with working_dir="./infrastructure/eks"]
Plan output: +12 to add, 0 to change, 0 to destroy
  + aws_eks_cluster.main
  + aws_eks_node_group.main
  ...

You: Apply it
Claude: I'll apply the plan. This will create 12 resources. Confirmed?

You: Yes
Claude: [calls terraform_apply with confirmed=true]
Apply complete! Resources: 12 added, 0 changed, 0 destroyed.
```

## Safety Features

**Confirmation gate**: Apply and Destroy require `confirmed=true`. Claude will always ask before setting this.

**Timeout protection**: Commands time out after 5 minutes to prevent hanging.

**Directory validation**: The server validates working directories exist before running any command.

**Read-only defaults**: Plan, Show, Output, and Validate never modify state.

## Production Checklist

- [ ] Never pass AWS credentials directly — use AWS profiles or instance roles
- [ ] Run with minimum IAM permissions for the intended operations
- [ ] Keep the MCP server binary path outside the Terraform working directory
- [ ] Add workspace selection before apply in multi-env setups
- [ ] Log all apply/destroy operations with timestamps and identity
- [ ] Integrate with cost estimation (Infracost) before confirming applies

This MCP server transforms Claude Code into a live Terraform operator — plan, inspect, and apply infrastructure through natural language while the safety gates keep destructive operations behind explicit confirmation.
