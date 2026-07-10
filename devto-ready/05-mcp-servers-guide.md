---
title: "Building MCP Servers for Infrastructure Automation: Terraform, Kubernetes, and AWS"
published: false
description: "Build MCP servers in TypeScript to automate Terraform, Kubernetes, and AWS infrastructure with the Model Context Protocol"
tags: mcp, typescript, devops, ai
canonical_url:
cover_image:
---

# Building MCP Servers for Infrastructure Automation: Terraform, Kubernetes, and AWS

> **Header Image Suggestion:** A diagram showing the MCP protocol flow: an MCP client (IDE or chat interface) communicating via JSON-RPC with three MCP servers — one for Terraform, one for Kubernetes, one for AWS — each connected to their respective infrastructure.

**Tags:** `#devtools` `#automation` `#kubernetes` `#terraform` `#opensource`

---

The Model Context Protocol (MCP) is changing how developers interact with infrastructure. Instead of switching between terminals, dashboards, and documentation, MCP lets you query and manage infrastructure through a standardized protocol that any compatible client can use.

I've built three MCP servers for the infrastructure tools I use daily:

- [mcp-server-terraform](https://github.com/kogunlowo123/mcp-server-terraform) — Plan, apply, and inspect Terraform state
- [mcp-server-kubernetes](https://github.com/kogunlowo123/mcp-server-kubernetes) — Query and manage Kubernetes clusters
- [mcp-server-aws](https://github.com/kogunlowo123/mcp-server-aws) — Interact with AWS services

This article explains what MCP is, how it works, and how to build your own MCP servers for infrastructure automation.

## What is MCP?

MCP (Model Context Protocol) is an open protocol that standardizes how applications provide context and tools to language models. Think of it as a USB-C port for developer tools — a universal interface that any client can plug into.

The protocol defines three core primitives:

1. **Tools** — Functions the client can invoke (e.g., "run terraform plan", "get pod logs")
2. **Resources** — Data the client can read (e.g., "current Terraform state", "cluster node list")
3. **Prompts** — Reusable templates for common workflows

Communication happens over JSON-RPC 2.0, typically via stdio (for local servers) or SSE (for remote servers).

```
┌─────────────┐     JSON-RPC      ┌──────────────┐
│  MCP Client │ ◄──────────────► │  MCP Server   │
│  (IDE/Chat) │    stdio / SSE    │  (Your Code)  │
└─────────────┘                   └──────┬───────┘
                                         │
                                    ┌────▼────┐
                                    │ Infra   │
                                    │ (AWS,   │
                                    │  K8s,   │
                                    │  TF)    │
                                    └─────────┘
```

## MCP Server Architecture

An MCP server is a program that implements the MCP protocol. It registers tools and resources, handles incoming requests, and returns structured responses.

Here's the basic structure using the TypeScript SDK:

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const server = new McpServer({
  name: "my-infra-server",
  version: "1.0.0",
  capabilities: {
    tools: {},
    resources: {},
  },
});

// Register a tool
server.tool(
  "get-cluster-status",
  "Get the status of a Kubernetes cluster",
  {
    context: z.string().describe("Kubernetes context name"),
  },
  async ({ context }) => {
    // Implementation here
    const status = await getClusterStatus(context);
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify(status, null, 2),
        },
      ],
    };
  }
);

// Start the server
const transport = new StdioServerTransport();
await server.connect(transport);
```

Every MCP server follows this pattern: create a server instance, register tools and resources, connect a transport. The SDK handles all the JSON-RPC serialization and protocol negotiation.

## Building the Terraform MCP Server

The [mcp-server-terraform](https://github.com/kogunlowo123/mcp-server-terraform) server exposes Terraform operations as MCP tools. Here's how the key tools are implemented:

### Tool: terraform-plan

```typescript
server.tool(
  "terraform-plan",
  "Run terraform plan on a workspace and return the planned changes",
  {
    workingDir: z.string().describe("Path to the Terraform workspace"),
    varFile: z.string().optional().describe("Path to a .tfvars file"),
    target: z.string().optional().describe("Resource address to target"),
  },
  async ({ workingDir, varFile, target }) => {
    const args = ["plan", "-no-color", "-detailed-exitcode"];

    if (varFile) args.push(`-var-file=${varFile}`);
    if (target) args.push(`-target=${target}`);

    const result = await execTerraform(args, workingDir);

    // Parse the plan output for structured data
    const summary = parsePlanOutput(result.stdout);

    return {
      content: [
        {
          type: "text",
          text: JSON.stringify({
            exitCode: result.exitCode,
            hasChanges: result.exitCode === 2,
            summary: {
              toAdd: summary.add,
              toChange: summary.change,
              toDestroy: summary.destroy,
            },
            planOutput: result.stdout,
          }, null, 2),
        },
      ],
    };
  }
);
```

### Tool: terraform-state-list

```typescript
server.tool(
  "terraform-state-list",
  "List all resources in the current Terraform state",
  {
    workingDir: z.string().describe("Path to the Terraform workspace"),
    filter: z.string().optional().describe("Filter resources by address prefix"),
  },
  async ({ workingDir, filter }) => {
    const args = ["state", "list"];
    if (filter) args.push(filter);

    const result = await execTerraform(args, workingDir);
    const resources = result.stdout.trim().split("\n").filter(Boolean);

    return {
      content: [
        {
          type: "text",
          text: JSON.stringify({
            count: resources.length,
            resources: resources,
          }, null, 2),
        },
      ],
    };
  }
);
```

### Tool: terraform-show-resource

```typescript
server.tool(
  "terraform-show-resource",
  "Show the current state of a specific Terraform resource",
  {
    workingDir: z.string().describe("Path to the Terraform workspace"),
    address: z.string().describe("Resource address (e.g., aws_instance.web)"),
  },
  async ({ workingDir, address }) => {
    const result = await execTerraform(
      ["state", "show", address],
      workingDir
    );

    return {
      content: [
        {
          type: "text",
          text: result.stdout,
        },
      ],
    };
  }
);
```

### Safety Boundaries

The Terraform server intentionally limits what it can do. `terraform apply` is only available with the `--enable-apply` flag, and it requires explicit confirmation:

```typescript
server.tool(
  "terraform-apply",
  "Apply a Terraform plan. Requires --enable-apply flag on server start.",
  {
    workingDir: z.string().describe("Path to the Terraform workspace"),
    autoApprove: z.boolean().default(false).describe("Skip confirmation"),
  },
  async ({ workingDir, autoApprove }) => {
    if (!config.enableApply) {
      return {
        content: [{
          type: "text",
          text: "Error: terraform apply is disabled. Start the server with --enable-apply to enable.",
        }],
        isError: true,
      };
    }

    if (!autoApprove) {
      return {
        content: [{
          type: "text",
          text: "Terraform apply requires explicit confirmation. Set autoApprove to true to proceed.",
        }],
        isError: true,
      };
    }

    const result = await execTerraform(
      ["apply", "-auto-approve", "-no-color"],
      workingDir
    );

    return {
      content: [{
        type: "text",
        text: result.stdout,
      }],
    };
  }
);
```

This two-level guard (server flag + parameter confirmation) prevents accidental infrastructure changes.

## Building the Kubernetes MCP Server

The [mcp-server-kubernetes](https://github.com/kogunlowo123/mcp-server-kubernetes) server uses the official Kubernetes client library to interact with clusters:

```typescript
import * as k8s from "@kubernetes/client-node";

const kc = new k8s.KubeConfig();
kc.loadFromDefault();

// Tool: get-pods
server.tool(
  "get-pods",
  "List pods in a namespace with their status",
  {
    namespace: z.string().default("default"),
    labelSelector: z.string().optional().describe("Label selector (e.g., app=nginx)"),
  },
  async ({ namespace, labelSelector }) => {
    const k8sApi = kc.makeApiClient(k8s.CoreV1Api);
    const response = await k8sApi.listNamespacedPod(
      namespace,
      undefined,
      undefined,
      undefined,
      undefined,
      labelSelector
    );

    const pods = response.body.items.map((pod) => ({
      name: pod.metadata?.name,
      namespace: pod.metadata?.namespace,
      status: pod.status?.phase,
      ready: pod.status?.conditions
        ?.find((c) => c.type === "Ready")?.status === "True",
      restarts: pod.status?.containerStatuses
        ?.reduce((sum, cs) => sum + (cs.restartCount || 0), 0) || 0,
      age: pod.metadata?.creationTimestamp,
      node: pod.spec?.nodeName,
    }));

    return {
      content: [{
        type: "text",
        text: JSON.stringify({ count: pods.length, pods }, null, 2),
      }],
    };
  }
);
```

### Resource: cluster-info

MCP Resources provide read-only data that clients can fetch on demand:

```typescript
server.resource(
  "cluster-info",
  "cluster://info",
  "Current Kubernetes cluster information",
  async () => {
    const k8sApi = kc.makeApiClient(k8s.CoreV1Api);
    const versionApi = kc.makeApiClient(k8s.VersionApi);

    const [nodes, version] = await Promise.all([
      k8sApi.listNode(),
      versionApi.getCode(),
    ]);

    const clusterInfo = {
      currentContext: kc.getCurrentContext(),
      serverVersion: `${version.body.major}.${version.body.minor}`,
      nodeCount: nodes.body.items.length,
      nodes: nodes.body.items.map((node) => ({
        name: node.metadata?.name,
        status: node.status?.conditions
          ?.find((c) => c.type === "Ready")?.status,
        kubeletVersion: node.status?.nodeInfo?.kubeletVersion,
        os: node.status?.nodeInfo?.osImage,
        cpu: node.status?.capacity?.cpu,
        memory: node.status?.capacity?.memory,
      })),
    };

    return {
      contents: [{
        uri: "cluster://info",
        mimeType: "application/json",
        text: JSON.stringify(clusterInfo, null, 2),
      }],
    };
  }
);
```

### Pod Log Streaming

One of the most useful tools — getting pod logs for debugging:

```typescript
server.tool(
  "get-pod-logs",
  "Retrieve logs from a pod, optionally from a specific container",
  {
    name: z.string().describe("Pod name"),
    namespace: z.string().default("default"),
    container: z.string().optional(),
    tailLines: z.number().default(100),
    sinceSeconds: z.number().optional().describe("Return logs from the last N seconds"),
    previous: z.boolean().default(false).describe("Get logs from the previous container instance"),
  },
  async ({ name, namespace, container, tailLines, sinceSeconds, previous }) => {
    const k8sApi = kc.makeApiClient(k8s.CoreV1Api);

    const response = await k8sApi.readNamespacedPodLog(
      name,
      namespace,
      container,
      undefined,        // follow
      undefined,        // insecureSkipTLSVerifyBackend
      undefined,        // limitBytes
      undefined,        // pretty
      previous,         // previous
      sinceSeconds,     // sinceSeconds
      tailLines,        // tailLines
      undefined         // timestamps
    );

    return {
      content: [{
        type: "text",
        text: response.body || "No logs available",
      }],
    };
  }
);
```

## Building the AWS MCP Server

The [mcp-server-aws](https://github.com/kogunlowo123/mcp-server-aws) server wraps the AWS SDK to provide infrastructure querying capabilities:

```typescript
import {
  EC2Client,
  DescribeInstancesCommand,
  DescribeSecurityGroupsCommand,
} from "@aws-sdk/client-ec2";
import {
  ECSClient,
  ListClustersCommand,
  ListServicesCommand,
  DescribeServicesCommand,
} from "@aws-sdk/client-ecs";

const ec2Client = new EC2Client({ region: process.env.AWS_REGION || "eu-west-1" });
const ecsClient = new ECSClient({ region: process.env.AWS_REGION || "eu-west-1" });

// Tool: list-ec2-instances
server.tool(
  "list-ec2-instances",
  "List EC2 instances with optional filtering",
  {
    filters: z.array(z.object({
      name: z.string(),
      values: z.array(z.string()),
    })).optional().describe("EC2 API filters"),
    region: z.string().optional(),
  },
  async ({ filters, region }) => {
    const client = region ? new EC2Client({ region }) : ec2Client;

    const command = new DescribeInstancesCommand({
      Filters: filters?.map((f) => ({
        Name: f.name,
        Values: f.values,
      })),
    });

    const response = await client.send(command);
    const instances = response.Reservations?.flatMap(
      (r) => r.Instances || []
    ).map((i) => ({
      instanceId: i.InstanceId,
      state: i.State?.Name,
      type: i.InstanceType,
      privateIp: i.PrivateIpAddress,
      publicIp: i.PublicIpAddress,
      az: i.Placement?.AvailabilityZone,
      name: i.Tags?.find((t) => t.Key === "Name")?.Value,
      launchTime: i.LaunchTime,
    }));

    return {
      content: [{
        type: "text",
        text: JSON.stringify({
          count: instances?.length || 0,
          instances,
        }, null, 2),
      }],
    };
  }
);
```

### ECS Service Health

```typescript
server.tool(
  "describe-ecs-services",
  "Get detailed status of ECS services in a cluster",
  {
    cluster: z.string().describe("ECS cluster name or ARN"),
    services: z.array(z.string()).optional().describe("Service names to describe (all if omitted)"),
  },
  async ({ cluster, services }) => {
    let serviceArns = services;

    if (!serviceArns) {
      const listResponse = await ecsClient.send(
        new ListServicesCommand({ cluster })
      );
      serviceArns = listResponse.serviceArns || [];
    }

    if (serviceArns.length === 0) {
      return {
        content: [{
          type: "text",
          text: JSON.stringify({ message: "No services found in cluster", cluster }),
        }],
      };
    }

    const describeResponse = await ecsClient.send(
      new DescribeServicesCommand({ cluster, services: serviceArns })
    );

    const serviceDetails = describeResponse.services?.map((s) => ({
      name: s.serviceName,
      status: s.status,
      desiredCount: s.desiredCount,
      runningCount: s.runningCount,
      pendingCount: s.pendingCount,
      taskDefinition: s.taskDefinition?.split("/").pop(),
      deployments: s.deployments?.map((d) => ({
        status: d.status,
        desiredCount: d.desiredCount,
        runningCount: d.runningCount,
        rolloutState: d.rolloutState,
      })),
      healthCheck: {
        healthy: s.runningCount === s.desiredCount,
        message: s.runningCount !== s.desiredCount
          ? `${s.desiredCount! - s.runningCount!} tasks not running`
          : "All tasks healthy",
      },
    }));

    return {
      content: [{
        type: "text",
        text: JSON.stringify({ cluster, services: serviceDetails }, null, 2),
      }],
    };
  }
);
```

## Client Configuration

To use these servers, configure them in your MCP client. Here's a typical configuration file:

```json
{
  "mcpServers": {
    "terraform": {
      "command": "node",
      "args": ["path/to/mcp-server-terraform/dist/index.js"],
      "env": {
        "TF_PLUGIN_CACHE_DIR": "/tmp/terraform-plugin-cache"
      }
    },
    "kubernetes": {
      "command": "node",
      "args": ["path/to/mcp-server-kubernetes/dist/index.js"],
      "env": {
        "KUBECONFIG": "/home/user/.kube/config"
      }
    },
    "aws": {
      "command": "node",
      "args": ["path/to/mcp-server-aws/dist/index.js"],
      "env": {
        "AWS_PROFILE": "production",
        "AWS_REGION": "eu-west-1"
      }
    }
  }
}
```

Each server runs as a separate process. The client communicates with each over stdio, and each server handles authentication and API calls independently.

## Deployment Patterns

### Local Development

For local development, servers run as Node.js processes on your workstation. They use your local credentials (AWS CLI profile, kubeconfig, etc.):

```bash
# Install and build
git clone https://github.com/kogunlowo123/mcp-server-terraform.git
cd mcp-server-terraform
npm install && npm run build

# Test directly
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | node dist/index.js
```

### Containerized Deployment

For team-shared servers or CI/CD integration, package the server as a container:

```dockerfile
FROM node:20-slim

# Install Terraform
RUN apt-get update && apt-get install -y wget unzip && \
    wget https://releases.hashicorp.com/terraform/1.7.0/terraform_1.7.0_linux_amd64.zip && \
    unzip terraform_1.7.0_linux_amd64.zip -d /usr/local/bin/ && \
    rm terraform_1.7.0_linux_amd64.zip

WORKDIR /app
COPY package*.json ./
RUN npm ci --production
COPY dist/ ./dist/

# Run on SSE transport for remote access
ENV MCP_TRANSPORT=sse
ENV MCP_PORT=3000

EXPOSE 3000
CMD ["node", "dist/index.js"]
```

When using SSE transport, the server exposes an HTTP endpoint that clients connect to. This enables scenarios where the server runs in a private network with access to infrastructure, while developers connect from their workstations.

### Security Considerations

MCP servers are powerful — they can execute Terraform, read Kubernetes secrets, and interact with AWS APIs. Security is critical:

1. **Principle of least privilege.** The IAM role or service account the server runs under should only have permissions for the operations it exposes.

2. **Read-only by default.** Start with read-only tools. Add write operations (apply, delete, scale) only when needed, behind explicit flags.

3. **Audit logging.** Log every tool invocation with the user identity, parameters, and result. This is essential for compliance.

4. **Network isolation.** If the server can access production infrastructure, it should not be exposed to the public internet. Use a VPN or private network.

```typescript
// Audit middleware example
const originalTool = server.tool.bind(server);
server.tool = (name, description, schema, handler) => {
  const wrappedHandler = async (params: any) => {
    const startTime = Date.now();
    console.error(JSON.stringify({
      event: "tool_invocation",
      tool: name,
      params: sanitizeParams(params),
      timestamp: new Date().toISOString(),
    }));

    const result = await handler(params);

    console.error(JSON.stringify({
      event: "tool_result",
      tool: name,
      durationMs: Date.now() - startTime,
      isError: result.isError || false,
    }));

    return result;
  };

  return originalTool(name, description, schema, wrappedHandler);
};
```

## Practical Workflow Example

Here's how these servers work together in a real debugging scenario. A developer notices an ECS service is unhealthy. Using MCP-enabled tooling, the investigation looks like this:

1. **AWS server**: "List ECS services in the production cluster" — identifies the unhealthy service
2. **AWS server**: "Describe the service" — sees that 2 of 3 tasks are failing
3. **Kubernetes server**: "Get events in the production namespace" — sees image pull errors (if running on EKS)
4. **Terraform server**: "Show the ECR repository resource" — checks the repository URL and lifecycle policy
5. **AWS server**: "Describe the security group" — verifies ECR VPC endpoint access

What would normally involve five different terminal sessions and three different AWS console pages becomes a single conversational flow.

## What's Next for MCP in Infrastructure

MCP is still early, but the potential is significant:

- **Policy-as-code validation** — An MCP server that runs OPA/Rego policies against proposed infrastructure changes before they're applied
- **Cost estimation** — Query Infracost or AWS Pricing API through MCP to estimate the cost impact of Terraform changes
- **Incident response automation** — An MCP server that combines CloudWatch alarms, Terraform state, and Kubernetes status into a unified incident context
- **Multi-cluster management** — Federated Kubernetes queries across clusters and clouds

## Conclusion

MCP servers turn infrastructure CLIs into programmable interfaces. The protocol is simple enough to implement in an afternoon, but powerful enough to transform how teams interact with their infrastructure.

The three servers discussed in this article are all open source and ready to use:

- [mcp-server-terraform](https://github.com/kogunlowo123/mcp-server-terraform) — Terraform operations via MCP
- [mcp-server-kubernetes](https://github.com/kogunlowo123/mcp-server-kubernetes) — Kubernetes cluster management via MCP
- [mcp-server-aws](https://github.com/kogunlowo123/mcp-server-aws) — AWS service queries via MCP

Find all my projects at [github.com/kogunlowo123](https://github.com/kogunlowo123). Contributions and feedback are welcome — open an issue or submit a PR.

---

*Building your own MCP server for a different tool? I'd love to see what you're working on. Share it in the comments or tag me on GitHub.*