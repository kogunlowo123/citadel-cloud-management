---
title: "GitOps with ArgoCD and Terraform: Declarative Kubernetes Deployments"
published: true
description: "Deploy ArgoCD on EKS with Terraform, configure multi-cluster GitOps, and implement progressive delivery with Argo Rollouts. Full Terraform + Helm code for production."
tags: kubernetes, terraform, gitops, devops
series: "Citadel Cloud Management: 100 Free Terraform Guides"
canonical_url: https://github.com/kogunlowo123/citadel-cloud-management/blob/main/citadel-content/blog/40-gitops-argocd-terraform.md
cover_image: https://kogunlowo123.github.io/citadel-cloud-management/assets/images/og-default.png
---

> **This is part of the [Citadel Cloud Management](https://github.com/kogunlowo123/citadel-cloud-management) free Terraform guide library — 100+ production-ready guides, MIT licensed, no paywall.**

GitOps treats Git as the single source of truth for infrastructure and application state. ArgoCD watches your Git repo and continuously reconciles the live cluster to match. This guide deploys ArgoCD on EKS with Terraform and configures multi-cluster management with progressive delivery.

## What you'll build

```
Git repo (manifests/Helm charts)
        ↓
ArgoCD (running on EKS)
   ├── App of Apps pattern
   └── ApplicationSet (multi-cluster)
        ↓
Target clusters (staging + production EKS)
        ↓
Argo Rollouts (canary / blue-green)
```

## ArgoCD Installation via Helm

```hcl
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "7.3.6"
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  values = [yamlencode({
    global = {
      image = { tag = "v2.11.3" }
    }
    server = {
      extraArgs = ["--insecure"]  # TLS terminated at ALB
      service = { type = "ClusterIP" }
      ingress = {
        enabled          = true
        ingressClassName = "alb"
        annotations = {
          "alb.ingress.kubernetes.io/scheme"       = "internet-facing"
          "alb.ingress.kubernetes.io/target-type"  = "ip"
          "alb.ingress.kubernetes.io/certificate-arn" = var.acm_certificate_arn
        }
        hosts = [var.argocd_hostname]
        tls   = [{ hosts = [var.argocd_hostname] }]
      }
    }
    configs = {
      params = {
        "server.disable.auth" = false
      }
      cm = {
        "url"                    = "https://${var.argocd_hostname}"
        "oidc.config"            = yamlencode({
          name         = "Okta"
          issuer       = var.okta_issuer_url
          clientID     = var.okta_client_id
          clientSecret = "$oidc.okta.clientSecret"
          requestedScopes = ["openid", "profile", "email", "groups"]
        })
      }
    }
    repoServer = {
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { cpu = "500m", memory = "512Mi" }
      }
    }
  })]

  depends_on = [kubernetes_namespace.argocd]
}
```

## App of Apps Pattern

```hcl
# Root application that manages all other ArgoCD applications
resource "kubernetes_manifest" "app_of_apps" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "app-of-apps"
      namespace = "argocd"
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.gitops_repo_url
        targetRevision = "HEAD"
        path           = "apps/production"  # Directory of Application manifests
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  }

  depends_on = [helm_release.argocd]
}
```

## ApplicationSet: Multi-Cluster Deployment

```hcl
resource "kubernetes_manifest" "appset_microservices" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "ApplicationSet"
    metadata = {
      name      = "microservices"
      namespace = "argocd"
    }
    spec = {
      generators = [{
        matrix = {
          generators = [
            {
              list = {
                elements = [
                  { cluster = "staging",    url = var.staging_cluster_url,    env = "staging" }
                  { cluster = "production", url = var.production_cluster_url, env = "production" }
                ]
              }
            },
            {
              git = {
                repoURL  = var.gitops_repo_url
                revision = "HEAD"
                directories = [{ path = "services/*" }]
              }
            }
          ]
        }
      }]
      template = {
        metadata = {
          name = "{{path.basename}}-{{cluster}}"
        }
        spec = {
          project = "{{cluster}}"
          source = {
            repoURL        = var.gitops_repo_url
            targetRevision = "HEAD"
            path           = "{{path}}"
            helm = {
              valueFiles = ["values-{{env}}.yaml"]
            }
          }
          destination = {
            server    = "{{url}}"
            namespace = "{{path.basename}}"
          }
          syncPolicy = {
            automated = {
              prune    = true
              selfHeal = true
            }
            syncOptions = ["CreateNamespace=true", "ApplyOutOfSyncOnly=true"]
            retry = {
              limit = 5
              backoff = {
                duration    = "5s"
                factor      = 2
                maxDuration = "3m"
              }
            }
          }
        }
      }
    }
  }
}
```

## Argo Rollouts: Canary Deployment

```hcl
resource "kubernetes_manifest" "rollout_api" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Rollout"
    metadata = {
      name      = "api-service"
      namespace = "api"
    }
    spec = {
      replicas = 10
      strategy = {
        canary = {
          canaryService = "api-canary"
          stableService = "api-stable"
          trafficRouting = {
            alb = {
              ingress        = "api-ingress"
              servicePort    = 80
            }
          }
          steps = [
            { setWeight = 5 }                           # 5% canary
            { pause = { duration = "5m" } }             # Wait 5 minutes
            { analysis = { templates = [{ templateName = "error-rate" }] } }
            { setWeight = 25 }                          # 25% canary
            { pause = { duration = "10m" } }
            { setWeight = 50 }                          # 50%
            { pause = { duration = "10m" } }
            { setWeight = 100 }                         # Full rollout
          ]
          analysis = {
            startingStep = 2  # Analysis starts after first weight change
          }
        }
      }
      selector = { matchLabels = { app = "api-service" } }
      template = {
        metadata = { labels = { app = "api-service" } }
        spec = {
          containers = [{
            name  = "api"
            image = "${var.ecr_url}/api:latest"
            ports = [{ containerPort = 8080 }]
          }]
        }
      }
    }
  }
}

# AnalysisTemplate: auto-rollback on error rate spike
resource "kubernetes_manifest" "analysis_error_rate" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AnalysisTemplate"
    metadata   = { name = "error-rate", namespace = "api" }
    spec = {
      metrics = [{
        name             = "error-rate"
        interval         = "2m"
        successCondition = "result[0] < 0.05"  # < 5% error rate
        failureLimit     = 3
        provider = {
          prometheus = {
            address = "http://prometheus-server.monitoring:9090"
            query   = "sum(rate(http_requests_total{status=~'5..',service='api-service'}[2m])) / sum(rate(http_requests_total{service='api-service'}[2m]))"
          }
        }
      }]
    }
  }
}
```

## RBAC: Developer Self-Service

```hcl
resource "kubernetes_manifest" "argocd_project" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata   = { name = "team-api", namespace = "argocd" }
    spec = {
      description = "API team — self-service deployments"
      sourceRepos = ["https://github.com/kogunlowo123/*"]
      destinations = [
        { server = "https://kubernetes.default.svc", namespace = "api" }
        { server = var.staging_cluster_url, namespace = "api" }
      ]
      clusterResourceWhitelist = []  # No cluster-scoped resources
      namespaceResourceWhitelist = [
        { group = "apps", kind = "Deployment" }
        { group = "apps", kind = "StatefulSet" }
        { group = "", kind = "Service" }
        { group = "argoproj.io", kind = "Rollout" }
      ]
      roles = [{
        name     = "developer"
        policies = [
          "p, proj:team-api:developer, applications, get, team-api/*, allow"
          "p, proj:team-api:developer, applications, sync, team-api/*, allow"
        ]
        groups = ["api-team"]
      }]
    }
  }
}
```

## Production Checklist

- [ ] ArgoCD HA mode (3 replicas for server + repo-server + application-controller)
- [ ] OIDC SSO (Okta/GitHub) — no local users in production
- [ ] App of Apps pattern for bootstrapping all applications
- [ ] ApplicationSet for multi-cluster / multi-env deployment
- [ ] RBAC: AppProject per team with namespace restrictions
- [ ] Argo Rollouts with canary + AnalysisTemplate on error rate
- [ ] `selfHeal: true` + `prune: true` for true GitOps enforcement
- [ ] Git webhook → ArgoCD (don't rely on polling alone)
- [ ] ArgoCD notifications to Slack on sync failures
- [ ] Backup ArgoCD state with Velero (includes all Application CRDs)

## Full Code

Complete guide with multi-cluster registration, ArgoCD notifications, secret management with External Secrets, and Velero backup:

👉 [github.com/kogunlowo123/citadel-cloud-management — Article 40](https://github.com/kogunlowo123/citadel-cloud-management/blob/main/citadel-content/blog/40-gitops-argocd-terraform.md)

---

*Part of 100 free production Terraform guides covering AWS, Azure, GCP, Kubernetes, DevSecOps, AI/ML, and Cloud Careers. MIT licensed. [Browse the full library →](https://github.com/kogunlowo123/citadel-cloud-management)*
