# MCP Server for GitHub: AI-Powered Repository Management

**Pillar:** MCP Servers
**SEO Target:** github mcp server ai repository issues pull requests automation
**Word Count:** ~1500

A GitHub MCP server lets AI agents manage repositories, create issues, review PRs, and automate release processes through natural language. This guide builds a TypeScript GitHub MCP server using the Octokit SDK that AI agents can use to manage the entire software development lifecycle.

## GitHub MCP Server Setup

```typescript
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { Octokit } from "@octokit/rest";

const octokit = new Octokit({ auth: process.env.GITHUB_TOKEN });

const server = new Server(
  { name: "github-mcp", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "github_list_issues",
      description: "List open issues in a repository with labels and assignees",
      inputSchema: {
        type: "object",
        required: ["owner", "repo"],
        properties: {
          owner:  { type: "string" },
          repo:   { type: "string" },
          labels: { type: "string", description: "Comma-separated label names" },
          state:  { type: "string", enum: ["open", "closed", "all"], default: "open" },
          limit:  { type: "number", default: 20, maximum: 100 },
        },
      },
    },
    {
      name: "github_create_issue",
      description: "Create a new issue with title, body, labels, and assignees",
      inputSchema: {
        type: "object",
        required: ["owner", "repo", "title"],
        properties: {
          owner:     { type: "string" },
          repo:      { type: "string" },
          title:     { type: "string" },
          body:      { type: "string" },
          labels:    { type: "array", items: { type: "string" } },
          assignees: { type: "array", items: { type: "string" } },
          milestone: { type: "number" },
        },
      },
    },
    {
      name: "github_list_prs",
      description: "List pull requests with review status",
      inputSchema: {
        type: "object",
        required: ["owner", "repo"],
        properties: {
          owner:  { type: "string" },
          repo:   { type: "string" },
          state:  { type: "string", enum: ["open", "closed", "all"], default: "open" },
          base:   { type: "string", description: "Filter PRs by base branch" },
        },
      },
    },
    {
      name: "github_create_pr",
      description: "Create a pull request from head branch to base branch",
      inputSchema: {
        type: "object",
        required: ["owner", "repo", "title", "head", "base"],
        properties: {
          owner:               { type: "string" },
          repo:                { type: "string" },
          title:               { type: "string" },
          body:                { type: "string" },
          head:                { type: "string" },
          base:                { type: "string" },
          draft:               { type: "boolean", default: false },
          maintainer_can_modify: { type: "boolean", default: true },
        },
      },
    },
    {
      name: "github_get_file",
      description: "Get the content of a file from a repository",
      inputSchema: {
        type: "object",
        required: ["owner", "repo", "path"],
        properties: {
          owner: { type: "string" },
          repo:  { type: "string" },
          path:  { type: "string" },
          ref:   { type: "string", description: "Branch, tag, or commit SHA" },
        },
      },
    },
    {
      name: "github_search_code",
      description: "Search for code across GitHub repositories",
      inputSchema: {
        type: "object",
        required: ["query"],
        properties: {
          query: { type: "string", description: "GitHub code search query" },
          limit: { type: "number", default: 10, maximum: 30 },
        },
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    switch (name) {
      case "github_list_issues": {
        const { data } = await octokit.issues.listForRepo({
          owner:    args.owner,
          repo:     args.repo,
          state:    args.state ?? "open",
          labels:   args.labels,
          per_page: args.limit ?? 20,
        });
        return {
          content: [{
            type: "text",
            text: JSON.stringify(data.map((i) => ({
              number:  i.number,
              title:   i.title,
              state:   i.state,
              labels:  i.labels.map((l: any) => l.name),
              assignees: i.assignees?.map((a) => a.login),
              created: i.created_at,
              url:     i.html_url,
            })), null, 2),
          }],
        };
      }

      case "github_create_issue": {
        const { data } = await octokit.issues.create({
          owner:     args.owner,
          repo:      args.repo,
          title:     args.title,
          body:      args.body,
          labels:    args.labels,
          assignees: args.assignees,
          milestone: args.milestone,
        });
        return {
          content: [{
            type: "text",
            text: `Created issue #${data.number}: ${data.html_url}`,
          }],
        };
      }

      case "github_get_file": {
        const { data } = await octokit.repos.getContent({
          owner: args.owner,
          repo:  args.repo,
          path:  args.path,
          ref:   args.ref,
        });
        if ("content" in data) {
          const content = Buffer.from(data.content, "base64").toString("utf8");
          return { content: [{ type: "text", text: content }] };
        }
        throw new Error("Path is a directory, not a file");
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

## Production Checklist

- [ ] Fine-grained PAT with minimum required scopes (repo, issues, pull_requests)
- [ ] Rate limit handling (Octokit built-in retry with exponential backoff)
- [ ] Read-only tools for browsing vs write tools for mutations (separate concern)
- [ ] Audit log all write operations (create_issue, create_pr)
- [ ] Repository allowlist: limit server to specific repos (not org-wide by default)
- [ ] Webhook listener for reactive automation (issue created → assign, label, respond)

A GitHub MCP server transforms an AI agent into a software project manager — it can triage incoming issues, draft PR descriptions, link related issues, and keep stakeholders updated without human intervention.

## About This Guide

This guide is part of the Citadel Cloud Management content series covering AWS, Azure, GCP, DevSecOps, MCP Servers, and Cloud Careers. Follow our GitHub: https://github.com/kogunlowo123/citadel-cloud-management
