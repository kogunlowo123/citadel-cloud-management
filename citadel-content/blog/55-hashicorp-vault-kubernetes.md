# HashiCorp Vault on Kubernetes with Terraform: Secrets Management

**Pillar:** Multi-Cloud Architecture
**SEO Target:** hashicorp vault kubernetes terraform secrets management dynamic credentials raft
**Word Count:** ~1500

HashiCorp Vault is the gold standard for secrets management in multi-cloud environments. Dynamic credentials, PKI issuance, encryption as a service, and audit logging in one platform. This guide deploys Vault on Kubernetes with Terraform using Raft storage.

## Vault Helm Deployment

```hcl
resource "helm_release" "vault" {
  name       = "vault"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  version    = "0.28.1"
  namespace  = kubernetes_namespace.vault.metadata[0].name

  values = [yamlencode({
    global = {
      enabled    = true
      tlsDisable = false
    }

    server = {
      ha = {
        enabled  = true
        replicas = 3
        raft = {
          enabled   = true
          setNodeId = true
          config    = <<-HCL
            ui = true
            listener "tcp" {
              tls_disable = 0
              address     = "[::]:8200"
              cluster_address = "[::]:8201"
              tls_cert_file = "/vault/userconfig/vault-tls/tls.crt"
              tls_key_file  = "/vault/userconfig/vault-tls/tls.key"
            }
            storage "raft" {
              path    = "/vault/data"
              node_id = HOSTNAME
              retry_join {
                leader_api_addr       = "https://vault-0.vault-internal:8200"
                leader_ca_cert_file   = "/vault/userconfig/vault-tls/ca.crt"
              }
            }
            service_registration "kubernetes" {}
          HCL
        }
      }
      resources = {
        requests = { memory = "256Mi", cpu = "250m" }
        limits   = { memory = "512Mi", cpu = "500m" }
      }
      affinity = {
        podAntiAffinity = {
          requiredDuringSchedulingIgnoredDuringExecution = [{
            labelSelector = {
              matchLabels = { "app.kubernetes.io/name" = "vault" }
            }
            topologyKey = "kubernetes.io/hostname"
          }]
        }
      }
    }

    injector = {
      enabled = true
      resources = {
        requests = { memory = "64Mi",  cpu = "50m" }
        limits   = { memory = "256Mi", cpu = "250m" }
      }
    }
  })]
}
```

## Vault Provider Configuration

```hcl
provider "vault" {
  address = "https://vault.${var.domain}"
  token   = var.vault_token
}
```

## AWS Dynamic Credentials Engine

```hcl
resource "vault_aws_secret_backend" "aws" {
  path       = "aws"
  region     = var.region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key

  default_lease_ttl_seconds = 3600
  max_lease_ttl_seconds     = 86400
}

resource "vault_aws_secret_backend_role" "s3_reader" {
  name            = "s3-reader"
  backend         = vault_aws_secret_backend.aws.path
  credential_type = "iam_user"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = ["arn:aws:s3:::${var.bucket_name}", "arn:aws:s3:::${var.bucket_name}/*"]
    }]
  })
}
```

## Kubernetes Auth Method

```hcl
resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
  path = "kubernetes"
}

resource "vault_kubernetes_auth_backend_config" "main" {
  backend            = vault_auth_backend.kubernetes.path
  kubernetes_host    = var.kubernetes_host
  kubernetes_ca_cert = var.kubernetes_ca_cert
  issuer             = var.kubernetes_issuer
}

resource "vault_kubernetes_auth_backend_role" "app" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "app"
  bound_service_account_names      = ["app-service-account"]
  bound_service_account_namespaces = ["default", "production"]
  token_ttl                        = 3600
  token_policies                   = ["app-policy"]
}
```

## PKI Secrets Engine

```hcl
resource "vault_mount" "pki" {
  path                      = "pki"
  type                      = "pki"
  default_lease_ttl_seconds = 86400
  max_lease_ttl_seconds     = 315360000
}

resource "vault_pki_secret_backend_role" "server" {
  backend          = vault_mount.pki.path
  name             = "server"
  ttl              = 86400
  allow_ip_sans    = true
  key_type         = "rsa"
  key_bits         = 4096
  allowed_domains  = ["${var.domain}", "*.${var.domain}"]
  allow_subdomains = true
}
```

## Production Checklist

- [ ] 3-node Raft cluster across 3 availability zones (HA)
- [ ] TLS everywhere (Vault → Vault communication)
- [ ] Kubernetes auth method (pods authenticate via service account JWT)
- [ ] AWS Dynamic Credentials (1h TTL — leaked creds expire fast)
- [ ] PKI engine for internal TLS cert issuance (replaces static certs)
- [ ] Vault Agent Injector sidecar for transparent secret injection
- [ ] Audit log to CloudWatch / Splunk (every secret access logged)
- [ ] Auto-unseal with AWS KMS (eliminates manual unseal on restart)
