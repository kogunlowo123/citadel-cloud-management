# Kubernetes Gateway API with Terraform: Replacing Ingress in Production

**Pillar:** AWS Infrastructure
**SEO Target:** kubernetes gateway api terraform, k8s gateway api replace ingress terraform, eks gateway api terraform
**Word Count:** ~1,800

The Kubernetes Gateway API (GA since Kubernetes 1.28) replaces Ingress with a role-oriented, expressive API that separates infrastructure concerns from application routing. Where Ingress requires annotations for anything beyond basic routing, Gateway API provides first-class resources for traffic management, TLS, and multi-team isolation. This guide deploys Gateway API on EKS with Terraform using AWS Load Balancer Controller as the implementation.

## Gateway API vs Ingress

| Feature | Ingress | Gateway API |
|---------|---------|-------------|
| TLS termination | Annotation-based | First-class `TLSRoute` |
| Header-based routing | Controller-specific annotation | `HTTPRoute` with `matches` |
| Traffic splitting | Annotation hack | `backendRefs` with `weight` |
| Multi-team isolation | Single resource | `GatewayClass` + `Gateway` per team |
| GRPC routing | Not supported | `GRPCRoute` resource |
| TCP/UDP routing | Not supported | `TCPRoute` / `UDPRoute` |
| GA status | GA (but frozen) | GA since K8s 1.28 |

## Install Gateway API CRDs with Terraform

```hcl
# Install Gateway API CRDs from official channel
resource "null_resource" "gateway_api_crds" {
  provisioner "local-exec" {
    command = <<-EOT
      kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml
    EOT
  }

  triggers = {
    version = "v1.1.0"
  }
}

# Or install via Helm (preferred for lifecycle management)
resource "helm_release" "gateway_api" {
  name             = "gateway-api"
  repository       = "https://kubernetes-sigs.github.io/gateway-api"
  chart            = "gateway-api"
  version          = "1.1.0"
  namespace        = "gateway-system"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }
}
```

## AWS Load Balancer Controller (Gateway Implementation)

```hcl
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.8.0"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.alb_controller.arn
  }

  set {
    name  = "enableGatewayAPI"
    value = "true"
  }

  depends_on = [helm_release.gateway_api]
}
```

## GatewayClass — Infrastructure Team Resource

```hcl
resource "kubernetes_manifest" "gateway_class_internet" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "GatewayClass"
    metadata = {
      name = "internet-facing"
      annotations = {
        "gateway.networking.k8s.io/bundle-version" = "v1.1.0"
      }
    }
    spec = {
      controllerName = "eks.amazonaws.com/alb"
      parametersRef = {
        group     = "eks.amazonaws.com"
        kind      = "IngressClassParams"
        name      = "internet-facing-params"
        namespace = "kube-system"
      }
    }
  }
}

resource "kubernetes_manifest" "gateway_class_internal" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "GatewayClass"
    metadata = { name = "internal" }
    spec = {
      controllerName = "eks.amazonaws.com/alb"
    }
  }
}
```

## Gateway — Platform Team Resource

```hcl
resource "kubernetes_manifest" "gateway_prod" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = "prod-gateway"
      namespace = "gateway-system"
      annotations = {
        "service.beta.kubernetes.io/aws-load-balancer-ssl-cert"    = aws_acm_certificate.main.arn
        "service.beta.kubernetes.io/aws-load-balancer-ssl-policy"  = "ELBSecurityPolicy-TLS13-1-2-2021-06"
        "service.beta.kubernetes.io/aws-load-balancer-scheme"      = "internet-facing"
        "service.beta.kubernetes.io/aws-load-balancer-subnets"     = join(",", var.public_subnet_ids)
      }
    }
    spec = {
      gatewayClassName = "internet-facing"
      listeners = [
        {
          name     = "http"
          port     = 80
          protocol = "HTTP"
          allowedRoutes = {
            namespaces = { from = "Selector"
              selector = { matchLabels = { "gateway-access" = "allowed" } }
            }
          }
        },
        {
          name     = "https"
          port     = 443
          protocol = "HTTPS"
          tls = {
            mode = "Terminate"
            certificateRefs = [{
              name      = "prod-tls-cert"
              namespace = "gateway-system"
            }]
          }
          allowedRoutes = {
            namespaces = { from = "Selector"
              selector = { matchLabels = { "gateway-access" = "allowed" } }
            }
          }
        }
      ]
    }
  }
}
```

## HTTPRoute — Application Team Resource (No Cluster-Admin Needed)

```hcl
# Application teams manage their own HTTPRoute in their namespace
resource "kubernetes_manifest" "api_route" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "api-service"
      namespace = "team-api"  # Application namespace
    }
    spec = {
      parentRefs = [{
        name      = "prod-gateway"
        namespace = "gateway-system"
        sectionName = "https"
      }]
      hostnames = ["api.citadelcloudmanagement.com"]
      rules = [
        # Route v2 traffic to new service (canary)
        {
          matches = [{
            headers = [{
              type  = "Exact"
              name  = "x-api-version"
              value = "v2"
            }]
          }]
          backendRefs = [{
            name = "api-service-v2"
            port = 8080
            weight = 100
          }]
        },
        # Default: weighted split for canary (10% v2, 90% v1)
        {
          backendRefs = [
            { name = "api-service-v1", port = 8080, weight = 90 },
            { name = "api-service-v2", port = 8080, weight = 10 }
          ]
        },
        # Redirect HTTP to HTTPS
        {
          matches = [{ path = { type = "PathPrefix", value = "/" } }]
          filters = [{
            type = "RequestRedirect"
            requestRedirect = {
              scheme     = "https"
              statusCode = 301
            }
          }]
        }
      ]
    }
  }
}
```

## GRPCRoute (New in Gateway API v1.1)

```hcl
resource "kubernetes_manifest" "grpc_route" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "GRPCRoute"
    metadata = {
      name      = "grpc-service"
      namespace = "team-backend"
    }
    spec = {
      parentRefs = [{
        name      = "prod-gateway"
        namespace = "gateway-system"
      }]
      hostnames = ["grpc.citadelcloudmanagement.com"]
      rules = [{
        matches = [{
          method = {
            type    = "Exact"
            service = "citadel.v1.UserService"
          }
        }]
        backendRefs = [{ name = "grpc-user-service", port = 9090 }]
      }]
    }
  }
}
```

## RBAC: Multi-Team Isolation

```hcl
# Application teams can manage HTTPRoutes in their namespace
# They cannot modify the Gateway or GatewayClass (platform-owned)
resource "kubernetes_role" "app_team_gateway" {
  for_each = var.app_namespaces

  metadata {
    name      = "gateway-route-manager"
    namespace = each.key
  }

  rule {
    api_groups = ["gateway.networking.k8s.io"]
    resources  = ["httproutes", "grpcroutes"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # Read-only on Gateway status (to debug routing issues)
  rule {
    api_groups = ["gateway.networking.k8s.io"]
    resources  = ["gateways"]
    verbs      = ["get", "list", "watch"]
  }
}
```

## Namespace Labels for Gateway Access

```hcl
resource "kubernetes_namespace" "team_api" {
  metadata {
    name = "team-api"
    labels = {
      "gateway-access" = "allowed"  # Required by Gateway's allowedRoutes
    }
  }
}
```

## Outputs

```hcl
output "gateway_address" {
  value = kubernetes_manifest.gateway_prod.manifest.status.addresses[0].value
}

output "gateway_class_internet" {
  value = kubernetes_manifest.gateway_class_internet.manifest.metadata.name
}
```

## Migration from Ingress

```bash
# Check existing Ingress annotations
kubectl get ingress -A -o yaml | grep "kubernetes.io/ingress"

# Common annotation → Gateway API mapping:
# nginx.ingress.kubernetes.io/rewrite-target → HTTPRoute path rewrite filter
# nginx.ingress.kubernetes.io/canary-weight → backendRefs weight
# cert-manager.io/cluster-issuer → Gateway TLS certificateRefs
# nginx.ingress.kubernetes.io/ssl-redirect → RequestRedirect filter
```

## Production Checklist

- [ ] Gateway API CRDs v1.1.0+ installed (`standard-install.yaml` for GA channels)
- [ ] AWS Load Balancer Controller v1.8.0+ with `enableGatewayAPI=true`
- [ ] `GatewayClass` owned by platform/infra team, not application teams
- [ ] `Gateway` namespace labeled and RBAC-scoped per environment
- [ ] Application namespaces have `gateway-access: allowed` label
- [ ] TLS policy set to `ELBSecurityPolicy-TLS13-1-2-2021-06` (TLS 1.3 preferred)
- [ ] HTTP→HTTPS redirect configured in Gateway listener rules
- [ ] Canary routing tested with header-based + weighted split
- [ ] GRPC routes configured if using gRPC services
- [ ] Ingress migration validated by running both Ingress and HTTPRoute in parallel before cutover

Gateway API's role-oriented model is the future of Kubernetes traffic management — it solves Ingress annotation sprawl while enabling multi-team self-service without cluster-admin access.
