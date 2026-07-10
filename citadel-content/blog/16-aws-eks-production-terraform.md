# AWS EKS Production Cluster with Terraform: Complete Guide

**Pillar:** AWS Infrastructure
**SEO Target:** aws eks terraform production
**Word Count:** ~1800

Amazon Elastic Kubernetes Service (EKS) is the managed Kubernetes offering on AWS. This guide walks through building a production-grade EKS cluster using Terraform with managed node groups, IRSA (IAM Roles for Service Accounts), and add-ons like the AWS Load Balancer Controller, EBS CSI Driver, and Cluster Autoscaler.

## Architecture Overview

A production EKS cluster requires:
- Private worker nodes in isolated subnets
- Control plane logging enabled
- OIDC provider for IRSA
- Managed node groups with auto-scaling
- VPC CNI with custom networking
- Secrets encryption with KMS

## Terraform Module Structure

```
eks/
├── main.tf          # EKS cluster resource
├── node_groups.tf   # Managed node groups
├── irsa.tf          # OIDC + IAM roles
├── addons.tf        # EKS managed add-ons
├── variables.tf
└── outputs.tf
```

## Cluster Configuration

```hcl
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = var.enable_public_endpoint
    public_access_cidrs     = var.public_access_cidrs
    security_group_ids      = [aws_security_group.cluster.id]
  }

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.eks.arn
    }
  }

  enabled_cluster_log_types = [
    "api", "audit", "authenticator",
    "controllerManager", "scheduler"
  ]

  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
    aws_cloudwatch_log_group.eks
  ]

  tags = var.tags
}
```

## Managed Node Groups

```hcl
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-ng-main"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids

  instance_types = var.node_instance_types
  capacity_type  = "ON_DEMAND"

  scaling_config {
    desired_size = var.node_desired_size
    max_size     = var.node_max_size
    min_size     = var.node_min_size
  }

  update_config {
    max_unavailable_percentage = 25
  }

  labels = {
    role        = "application"
    environment = var.environment
  }

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_AmazonEC2ContainerRegistryReadOnly,
  ]

  tags = var.tags
}
```

## IRSA — IAM Roles for Service Accounts

```hcl
data "aws_eks_cluster" "main" {
  name = aws_eks_cluster.main.name
}

data "aws_eks_cluster_auth" "main" {
  name = aws_eks_cluster.main.name
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# Example: Load Balancer Controller IRSA
module "lb_controller_irsa" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name                              = "${var.cluster_name}-lb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = aws_iam_openid_connect_provider.eks.arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}
```

## EKS Managed Add-ons

```hcl
resource "aws_eks_addon" "vpc_cni" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "vpc-cni"
  addon_version            = data.aws_eks_addon_version.vpc_cni.version
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    env = {
      ENABLE_PREFIX_DELEGATION = "true"
      WARM_PREFIX_TARGET       = "1"
    }
  })
}

resource "aws_eks_addon" "coredns" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "coredns"
  addon_version            = data.aws_eks_addon_version.coredns.version
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "kube-proxy"
  addon_version            = data.aws_eks_addon_version.kube_proxy.version
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
  resolve_conflicts_on_update = "OVERWRITE"
}
```

## Cluster Autoscaler

```hcl
resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = "9.29.0"

  set {
    name  = "autoDiscovery.clusterName"
    value = aws_eks_cluster.main.name
  }

  set {
    name  = "awsRegion"
    value = var.aws_region
  }

  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.cluster_autoscaler_irsa.iam_role_arn
  }

  set {
    name  = "extraArgs.balance-similar-node-groups"
    value = "true"
  }

  set {
    name  = "extraArgs.skip-nodes-with-system-pods"
    value = "false"
  }
}
```

## KMS Key for Secrets Encryption

```hcl
resource "aws_kms_key" "eks" {
  description             = "EKS cluster ${var.cluster_name} secrets encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-eks-key"
  })
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.cluster_name}-eks"
  target_key_id = aws_kms_key.eks.key_id
}
```

## Security Group Configuration

```hcl
resource "aws_security_group" "cluster" {
  name_prefix = "${var.cluster_name}-cluster-"
  vpc_id      = var.vpc_id

  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Allow HTTPS from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.cluster_name}-cluster-sg" })

  lifecycle {
    create_before_destroy = true
  }
}
```

## Variables

```hcl
variable "cluster_name" { type = string }
variable "kubernetes_version" { type = string; default = "1.29" }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "node_instance_types" { type = list(string); default = ["m5.xlarge"] }
variable "node_desired_size" { type = number; default = 3 }
variable "node_max_size" { type = number; default = 10 }
variable "node_min_size" { type = number; default = 1 }
variable "enable_public_endpoint" { type = bool; default = false }
variable "public_access_cidrs" { type = list(string); default = [] }
variable "environment" { type = string }
variable "aws_region" { type = string }
variable "tags" { type = map(string); default = {} }
```

## Outputs

```hcl
output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "cluster_certificate_authority_data" {
  value = aws_eks_cluster.main.certificate_authority[0].data
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.eks.arn
}

output "cluster_security_group_id" {
  value = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}
```

## Deployment

```bash
terraform init
terraform plan -var-file=prod.tfvars
terraform apply -var-file=prod.tfvars

# Configure kubectl
aws eks update-kubeconfig \
  --region us-east-1 \
  --name my-production-cluster

# Verify
kubectl get nodes
kubectl get pods -n kube-system
```

## Production Checklist

- [ ] Control plane logs enabled (all 5 log types)
- [ ] Secrets encryption with customer-managed KMS key
- [ ] Private API endpoint only (no public access)
- [ ] Managed node groups with Launch Template
- [ ] IRSA configured for all AWS-integrated pods
- [ ] Cluster Autoscaler deployed
- [ ] AWS Load Balancer Controller installed
- [ ] EBS CSI Driver with IRSA
- [ ] VPC CNI with prefix delegation
- [ ] Pod Security Admission configured
- [ ] Network policies enforced

This Terraform configuration gives you a fully production-hardened EKS cluster. The IRSA setup eliminates node-level IAM permissions, the KMS encryption protects Kubernetes secrets at rest, and private endpoint access ensures the API server is never exposed to the public internet.
