# Kubernetes MCP Server: Manage K8s Clusters with AI Agents

**Pillar:** MCP Servers
**SEO Target:** kubernetes mcp server ai agent kubectl terraform k8s automation
**Word Count:** ~1600

A Kubernetes MCP server lets AI agents manage clusters through natural language. Instead of `kubectl apply -f deployment.yaml`, your agent says "deploy the payment service at version 2.1.3 with 3 replicas" and the MCP server handles the API calls safely. This guide builds a production-grade K8s MCP server in TypeScript.

## Architecture

```
AI Agent (Claude/GPT)
    ↓ MCP Protocol
Kubernetes MCP Server (TypeScript)
    ↓ @kubernetes/client-node
Kubernetes API Server
    ↓
Cluster Resources
```

## Project Setup

```bash
mkdir k8s-mcp-server && cd k8s-mcp-server
npm init -y
npm install @modelcontextprotocol/sdk @kubernetes/client-node zod
npm install -D typescript @types/node ts-node
```

## Server with Safety Controls

```typescript
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import * as k8s from "@kubernetes/client-node";
import { z } from "zod";

const kc = new k8s.KubeConfig();
kc.loadFromDefault();
const coreV1 = kc.makeApiClient(k8s.CoreV1Api);
const appsV1 = kc.makeApiClient(k8s.AppsV1Api);

// Safety: read-only namespaces protected from writes
const PROTECTED_NAMESPACES = ["kube-system", "kube-public", "cert-manager"];

function assertNamespaceSafe(namespace: string, operation: "write" | "delete") {
  if (PROTECTED_NAMESPACES.includes(namespace) && operation !== "write") return;
  if (PROTECTED_NAMESPACES.includes(namespace)) {
    throw new Error(`Operation blocked: namespace ${namespace} is protected`);
  }
}

const server = new Server(
  { name: "kubernetes-mcp", version: "1.0.0" },
  { capabilities: { tools: {} } }
);
```

## Tools Definition

```typescript
server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "kubectl_get_pods",
      description: "List pods in a namespace with status and restart counts",
      inputSchema: {
        type: "object",
        properties: {
          namespace: { type: "string", description: "Kubernetes namespace", default: "default" },
          label_selector: { type: "string", description: "Label selector e.g. app=payment" },
        },
      },
    },
    {
      name: "kubectl_get_deployments",
      description: "List deployments with replica counts and rollout status",
      inputSchema: {
        type: "object",
        properties: {
          namespace: { type: "string", default: "default" },
          name: { type: "string", description: "Specific deployment name (optional)" },
        },
      },
    },
    {
      name: "kubectl_scale",
      description: "Scale a deployment to a specific replica count",
      inputSchema: {
        type: "object",
        required: ["name", "namespace", "replicas"],
        properties: {
          name:      { type: "string" },
          namespace: { type: "string" },
          replicas:  { type: "number", minimum: 0, maximum: 50 },
        },
      },
    },
    {
      name: "kubectl_rollout_restart",
      description: "Trigger a rolling restart of a deployment",
      inputSchema: {
        type: "object",
        required: ["name", "namespace"],
        properties: {
          name:      { type: "string" },
          namespace: { type: "string" },
        },
      },
    },
    {
      name: "kubectl_get_logs",
      description: "Get recent logs from a pod",
      inputSchema: {
        type: "object",
        required: ["pod_name", "namespace"],
        properties: {
          pod_name:  { type: "string" },
          namespace: { type: "string" },
          lines:     { type: "number", default: 100, maximum: 1000 },
          container: { type: "string" },
        },
      },
    },
    {
      name: "kubectl_describe_node",
      description: "Get node capacity, allocatable resources, and conditions",
      inputSchema: {
        type: "object",
        required: ["node_name"],
        properties: {
          node_name: { type: "string" },
        },
      },
    },
  ],
}));
```

## Tool Handlers

```typescript
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    switch (name) {
      case "kubectl_get_pods": {
        const resp = await coreV1.listNamespacedPod(
          args.namespace ?? "default",
          undefined, undefined, undefined,
          undefined,
          args.label_selector
        );
        const pods = resp.body.items.map((p) => ({
          name:     p.metadata?.name,
          status:   p.status?.phase,
          ready:    p.status?.containerStatuses?.every((c) => c.ready),
          restarts: p.status?.containerStatuses?.reduce(
            (sum, c) => sum + c.restartCount, 0
          ),
          node: p.spec?.nodeName,
          age:  p.metadata?.creationTimestamp,
        }));
        return { content: [{ type: "text", text: JSON.stringify(pods, null, 2) }] };
      }

      case "kubectl_scale": {
        assertNamespaceSafe(args.namespace, "write");
        const patch = {
          spec: { replicas: args.replicas }
        };
        await appsV1.patchNamespacedDeploymentScale(
          args.name,
          args.namespace,
          patch,
          undefined, undefined, undefined, undefined,
          { headers: { "Content-Type": "application/merge-patch+json" } }
        );
        return {
          content: [{
            type: "text",
            text: `Scaled ${args.namespace}/${args.name} to ${args.replicas} replicas`
          }]
        };
      }

      case "kubectl_rollout_restart": {
        assertNamespaceSafe(args.namespace, "write");
        const patch = {
          spec: {
            template: {
              metadata: {
                annotations: {
                  "kubectl.kubernetes.io/restartedAt": new Date().toISOString()
                }
              }
            }
          }
        };
        await appsV1.patchNamespacedDeployment(
          args.name, args.namespace, patch, undefined, undefined, undefined, undefined,
          { headers: { "Content-Type": "application/merge-patch+json" } }
        );
        return { content: [{ type: "text", text: `Restart triggered for ${args.namespace}/${args.name}` }] };
      }

      case "kubectl_get_logs": {
        const resp = await coreV1.readNamespacedPodLog(
          args.pod_name, args.namespace,
          args.container, false, undefined, undefined,
          undefined, false, undefined,
          args.lines ?? 100
        );
        return { content: [{ type: "text", text: resp.body }] };
      }

      default:
        throw new Error(`Unknown tool: ${name}`);
    }
  } catch (error) {
    return {
      content: [{ type: "text", text: `Error: ${(error as Error).message}` }],
      isError: true,
    };
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
```

## Claude Desktop Config

```json
{
  "mcpServers": {
    "kubernetes": {
      "command": "npx",
      "args": ["ts-node", "/path/to/k8s-mcp-server/server.ts"],
      "env": {
        "KUBECONFIG": "/home/user/.kube/config"
      }
    }
  }
}
```

## Example Agent Interactions

```
User: "What pods in the payment namespace are not ready?"
Agent → kubectl_get_pods(namespace="payment")
→ Returns: payment-api-7d8f9 (Running, ready=false, restarts=5)

User: "Restart the payment-api deployment"
Agent → kubectl_rollout_restart(name="payment-api", namespace="payment")
→ "Restart triggered for payment/payment-api"

User: "Scale the payment-api to 5 replicas"
Agent → kubectl_scale(name="payment-api", namespace="payment", replicas=5)
→ "Scaled payment/payment-api to 5 replicas"
```

## Production Checklist

- [ ] Protected namespace list blocks writes to kube-system
- [ ] Maximum replica guard (max 50) prevents runaway scaling
- [ ] Log line limit (max 1000) prevents memory exhaustion
- [ ] KUBECONFIG from environment (not hardcoded)
- [ ] Separate read-only server for monitoring use cases
- [ ] Audit log of all write operations (scale, restart, patch)
- [ ] RBAC: server SA with minimal permissions (list pods, scale deployments)

The K8s MCP server transforms cluster management from "know the exact kubectl syntax" to "describe what you want." Paired with Claude, an SRE can interrogate cluster health and trigger remediations in natural language during an incident.
