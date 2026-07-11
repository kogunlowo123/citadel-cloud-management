---
title: "AWS ECS Fargate with Terraform: Serverless Containers in Production"
published: true
description: "Deploy a production ECS Fargate service with Terraform: ALB, ECR, Secrets Manager, auto-scaling, Container Insights, and X-Ray tracing — no EC2 to manage."
tags: aws, terraform, containers, devops
series: "Citadel Cloud Management: 100 Free Terraform Guides"
canonical_url: https://github.com/kogunlowo123/citadel-cloud-management/blob/main/citadel-content/blog/31-aws-ecs-fargate-terraform.md
cover_image: ""
---

ECS Fargate runs containers without managing EC2 capacity. This guide deploys a production-grade service with ALB, auto-scaling, secrets injection, Container Insights, and X-Ray.

## Architecture

```
Internet → ALB (HTTPS/443) → ECS Fargate Service
                                  ├── Task (Container)
                                  ├── ECR (private registry)
                                  ├── Secrets Manager (env injection)
                                  └── CloudWatch Logs + X-Ray
```

## VPC and Networking

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.prefix}-fargate-vpc"
  cidr = "10.0.0.0/16"
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)

  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway     = true
  one_nat_gateway_per_az = true
  enable_dns_hostnames   = true
  tags = var.tags
}
```

## ECS Cluster

```hcl
resource "aws_ecs_cluster" "main" {
  name = "${var.prefix}-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  tags = var.tags
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}
```

## ECR Repository

```hcl
resource "aws_ecr_repository" "app" {
  name                 = "${var.prefix}/app"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }

  tags = var.tags
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
```

## Task Definition

```hcl
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.prefix}-app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "app"
    image     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
    essential = true
    portMappings = [{ containerPort = 8080, protocol = "tcp" }]

    environment = [
      { name = "APP_ENV", value = var.environment }
    ]

    secrets = [
      {
        name      = "DB_PASSWORD"
        valueFrom = "${aws_secretsmanager_secret.db.arn}:password::"
      },
      {
        name      = "API_KEY"
        valueFrom = aws_secretsmanager_secret.api_key.arn
      }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "app"
      }
    }

    # X-Ray sidecar
  }, {
    name      = "xray-daemon"
    image     = "public.ecr.aws/xray/aws-xray-daemon:latest"
    essential = false
    portMappings = [{ containerPort = 2000, protocol = "udp" }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "xray"
      }
    }
  }])

  tags = var.tags
}
```

## ALB and Target Group

```hcl
module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 9.0"

  name    = "${var.prefix}-alb"
  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.public_subnets

  security_groups = [aws_security_group.alb.id]

  listeners = {
    https = {
      port            = 443
      protocol        = "HTTPS"
      certificate_arn = var.acm_certificate_arn
      forward = { target_group_key = "app" }
    }
    http_redirect = {
      port     = 80
      protocol = "HTTP"
      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  target_groups = {
    app = {
      name             = "${var.prefix}-app-tg"
      protocol         = "HTTP"
      port             = 8080
      target_type      = "ip"
      health_check = {
        enabled             = true
        path                = "/health"
        healthy_threshold   = 2
        unhealthy_threshold = 3
        timeout             = 5
        interval            = 30
      }
    }
  }

  tags = var.tags
}
```

## ECS Service

```hcl
resource "aws_ecs_service" "app" {
  name                               = "${var.prefix}-app"
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.app.arn
  desired_count                      = 2
  launch_type                        = "FARGATE"
  health_check_grace_period_seconds  = 60
  enable_execute_command             = var.environment != "prod"

  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = module.alb.target_groups["app"].arn
    container_name   = "app"
    container_port   = 8080
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_controller {
    type = "ECS"
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = var.tags
}
```

## Auto-Scaling

```hcl
resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = 10
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.prefix}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 70
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

resource "aws_appautoscaling_policy" "memory" {
  name               = "${var.prefix}-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 80
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
  }
}
```

## IAM Roles

```hcl
resource "aws_iam_role" "ecs_execution" {
  name = "${var.prefix}-ecs-execution"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Grant execution role access to secrets
resource "aws_iam_role_policy" "secrets_access" {
  name = "secrets-access"
  role = aws_iam_role.ecs_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "kms:Decrypt"]
      Resource = [aws_secretsmanager_secret.db.arn, aws_secretsmanager_secret.api_key.arn]
    }]
  })
}
```

## Security Groups

```hcl
resource "aws_security_group" "alb" {
  name   = "${var.prefix}-alb-sg"
  vpc_id = module.vpc.vpc_id

  ingress { from_port = 80;  to_port = 80;  protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"] }
  ingress { from_port = 443; to_port = 443; protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"] }
  egress  { from_port = 0;   to_port = 0;   protocol = "-1";  cidr_blocks = ["0.0.0.0/0"] }
  tags = var.tags
}

resource "aws_security_group" "ecs_tasks" {
  name   = "${var.prefix}-ecs-tasks-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress { from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }
  tags = var.tags
}
```

## Task Size Guide

| Workload | CPU | Memory | Notes |
|----------|-----|--------|-------|
| Lightweight API | 256 | 512 MB | Simple REST, low concurrency |
| Standard web service | 512 | 1024 MB | Most web apps |
| CPU-intensive | 1024 | 2048 MB | ML inference, image processing |
| Memory-intensive | 512 | 4096 MB | JVM apps, large caches |
| High-throughput | 2048 | 4096 MB | High-traffic production |

## Production Checklist

- [ ] IMMUTABLE image tags in ECR (never overwrite `:latest` in prod)
- [ ] ECR scan on push + lifecycle policy (keep last N images)
- [ ] Private subnets for tasks, no public IP assignment
- [ ] ALB HTTP → HTTPS redirect enforced
- [ ] Deployment circuit breaker enabled with auto-rollback
- [ ] Desired count `ignore_changes` to prevent Terraform reverting auto-scaling
- [ ] Secrets Manager for all credentials — no env vars with plaintext secrets
- [ ] X-Ray sidecar for distributed tracing
- [ ] Container Insights enabled for service-level metrics
- [ ] `enable_execute_command = false` in production (security)
- [ ] ALB access logs to S3 for audit trail
- [ ] CPU + memory auto-scaling policies (both dimensions)

## Full Repository

MIT licensed: [github.com/kogunlowo123/citadel-cloud-management](https://github.com/kogunlowo123/citadel-cloud-management)

Part of the **Citadel Cloud Management** series — 100+ free Terraform guides.
