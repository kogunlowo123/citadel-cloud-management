# GitOps with ArgoCD and Terraform: Declarative Kubernetes Deployments

**Pillar:** Multi-Cloud Architecture
**SEO Target:** gitops argocd terraform kubernetes declarative deployments multi-cloud
**Word Count:** ~1600

GitOps treats Git as the single source of truth for infrastructure and application state. ArgoCD watches your Git repo and continuously reconciles the live cluster state to match. This guide deploys ArgoCD on EKS with Terraform, configures multi-cluster management, and implements progressive delivery with Argo Rollouts.

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

    configs = {
      params = {
        "server.insecure"                    = false
        "application.namespaces"             = "*"
        "applicationsetcontroller.enable-progressive-syncs" = true
      }

      cm = {
        "exec.enabled"                     = false
        "server.rbac.log.enforce.enable"   = true
        "admin.enabled"                    = false
        "resource.exclusions"              = yamlencode([
          { apiGroups = ["*"], kinds = ["ProviderConfigUsage"] }
        ])
      }

      rbac = {
        "policy.default" = "role:readonly"
        "policy.csv"     = <<-RBAC
          p, role:admin, applications, *, */*, allow
          p, role:admin, clusters, *, *, allow
          p, role:admin, repositories, *, *, allow
          g, argocd-admins, role:admin
        RBAC
      }
    }

    server = {
      autoscaling = { enabled = true, minReplicas = 2, maxReplicas = 5 }
      ingress = {
        enabled          = true
        ingressClassName = "nginx"
        annotations = {
          "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
        }
        hosts  = ["argocd.${var.domain}"]
        tls    = [{ hosts = ["argocd.${var.domain}"], secretName = "argocd-tls" }]
      }
    }

    redis = {
      autoscaling = { enabled = false }
    }

    applicationSet = {
      replicaCount = 2
    }

    notifications = {
      enabled = true
    }
  })]
}
```

## ApplicationSet for Multi-Cluster Deployment

```hcl
resource "kubectl_manifest" "appset_services" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "ApplicationSet"
    metadata = {
      name      = "services"
      namespace = "argocd"
    }
    spec = {
      goTemplate = true
      generators = [{
        matrix = {
          generators = [
            {
              git = {
                repoURL  = var.gitops_repo_url
                revision = "HEAD"
                directories = [{ path = "services/*" }]
              }
            },
            {
              list = {
                elements = [
                  { cluster = "eks-us-east-1", url = var.cluster_us_east_url },
                  { cluster = "eks-eu-west-1", url = var.cluster_eu_west_url }
                ]
              }
            }
          ]
        }
      }]

      template = {
        metadata = {
          name = "{{.path.basename}}-{{.cluster}}"
          labels = {
            "app.kubernetes.io/name"    = "{{.path.basename}}"
            "app.kubernetes.io/managed" = "argocd"
          }
        }
        spec = {
          project = "default"
          source = {
            repoURL        = var.gitops_repo_url
            path           = "{{.path.path}}/overlays/{{.cluster}}"
            targetRevision = "HEAD"
          }
          destination = {
            server    = "{{.url}}"
            namespace = "{{.path.basename}}"
          }
          syncPolicy = {
            automated = {
              prune     = true
              selfHeal  = true
              allowEmpty = false
            }
            syncOptions = [
              "CreateNamespace=true",
              "ServerSideApply=true",
              "PrunePropagationPolicy=foreground"
            ]
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
  })
}
```

## Argo Rollouts Progressive Delivery

```hcl
resource "helm_release" "argo_rollouts" {
  name       = "argo-rollouts"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-rollouts"
  version    = "2.37.3"
  namespace  = "argo-rollouts"

  set {
    name  = "dashboard.enabled"
    value = "true"
  }
}

resource "kubectl_manifest" "rollout_payment" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Rollout"
    metadata = {
      name      = "payment-service"
      namespace = "payment"
    }
    spec = {
      replicas = 4
      selector = {
        matchLabels = { app = "payment-service" }
      }
      template = {
        metadata = {
          labels = { app = "payment-service" }
        }
        spec = {
          containers = [{
            name  = "payment"
            image = "${var.ecr_url}/payment-service:${var.payment_version}"
            ports = [{ containerPort = 8080 }]
          }]
        }
      }
      strategy = {
        canary = {
          steps = [
            { setWeight = 10 },
            { pause = { duration = "5m" } },
            { setWeight = 30 },
            { pause = { duration = "5m" } },
            { setWeight = 60 },
            { pause = { duration = "5m" } },
            { setWeight = 100 }
          ]
          analysis = {
            templates = [{
              templateName = "payment-success-rate"
            }]
            startingStep = 1
          }
        }
      }
    }
  })
}
```

## Image Updater for Automatic Deploys

```hcl
resource "helm_release" "argocd_image_updater" {
  name       = "argocd-image-updater"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-image-updater"
  version    = "0.9.6"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
}
```

## Production Checklist

- [ ] ArgoCD HA: server autoscaling 2-5, applicationSet replicas=2
- [ ] Admin account disabled — use SSO (Dex) or OIDC
- [ ] RBAC: readonly default, admins via group mapping
- [ ] ApplicationSet with Matrix generator deploys same service to all clusters
- [ ] Automated sync with prune + selfHeal + allowEmpty=false
- [ ] Retry with exponential backoff on sync failures
- [ ] Argo Rollouts canary: 10% → 30% → 60% → 100% with 5-min pauses
- [ ] Analysis templates gate promotion on error rate metrics
- [ ] Image Updater automates deployments when new images are pushed to ECR/ACR/GCR

GitOps eliminates SSH access for deployments. Every change is a Git commit with a review trail. Rollback is `git revert`. Drift between clusters is impossible when ArgoCD continuously reconciles.
