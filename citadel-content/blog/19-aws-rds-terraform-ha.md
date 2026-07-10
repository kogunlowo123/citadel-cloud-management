# AWS RDS Aurora PostgreSQL with Terraform: High Availability Setup

**Pillar:** AWS Infrastructure
**SEO Target:** aws rds aurora postgresql terraform high availability
**Word Count:** ~1600

Amazon Aurora PostgreSQL delivers up to 3× the throughput of standard PostgreSQL with automatic failover, self-healing storage, and read replica scaling. This guide builds a production Aurora cluster with Terraform including parameter groups, enhanced monitoring, and automated backups.

## Aurora vs Standard RDS

Aurora's distributed storage replicates data 6 ways across 3 Availability Zones automatically. Failover completes in under 30 seconds, storage auto-scales to 128 TiB, and you pay only for storage you use. For applications needing >99.95% uptime, Aurora is the right choice over RDS PostgreSQL.

## Subnet Group

```hcl
resource "aws_db_subnet_group" "main" {
  name       = "${var.cluster_name}-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.tags, { Name = "${var.cluster_name}-subnet-group" })
}
```

## Security Group

```hcl
resource "aws_security_group" "aurora" {
  name_prefix = "${var.cluster_name}-aurora-"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_group_ids = var.allowed_security_group_ids
    description     = "PostgreSQL from application"
  }

  tags = merge(var.tags, { Name = "${var.cluster_name}-aurora-sg" })

  lifecycle { create_before_destroy = true }
}
```

## Parameter Group

```hcl
resource "aws_rds_cluster_parameter_group" "main" {
  name   = "${var.cluster_name}-pg"
  family = "aurora-postgresql15"

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements,auto_explain"
  }

  parameter {
    name  = "pg_stat_statements.track"
    value = "all"
  }

  parameter {
    name  = "auto_explain.log_min_duration"
    value = "1000"
  }
}
```

## Aurora Cluster

```hcl
resource "aws_rds_cluster" "main" {
  cluster_identifier = var.cluster_name
  engine             = "aurora-postgresql"
  engine_version     = var.engine_version
  engine_mode        = "provisioned"

  database_name   = var.database_name
  master_username = var.master_username
  master_password = random_password.master.result

  db_subnet_group_name            = aws_db_subnet_group.main.name
  vpc_security_group_ids          = [aws_security_group.aurora.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.main.name

  storage_encrypted = true
  kms_key_id        = aws_kms_key.aurora.arn

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"

  deletion_protection = var.deletion_protection
  skip_final_snapshot = false
  final_snapshot_identifier = "${var.cluster_name}-final-${formatdate("YYYY-MM-DD", timestamp())}"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  serverlessv2_scaling_configuration {
    max_capacity = var.max_acu
    min_capacity = var.min_acu
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [master_password, availability_zones]
  }
}
```

## Cluster Instances

```hcl
resource "aws_rds_cluster_instance" "writer" {
  identifier         = "${var.cluster_name}-writer"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version

  db_parameter_group_name = aws_db_parameter_group.main.name

  monitoring_interval          = 60
  monitoring_role_arn          = aws_iam_role.rds_monitoring.arn
  performance_insights_enabled = true
  performance_insights_kms_key_id = aws_kms_key.aurora.arn
  performance_insights_retention_period = 7

  auto_minor_version_upgrade = true
  publicly_accessible        = false

  tags = merge(var.tags, { role = "writer" })
}

resource "aws_rds_cluster_instance" "readers" {
  count = var.reader_count

  identifier         = "${var.cluster_name}-reader-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version

  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.rds_monitoring.arn
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.aurora.arn

  publicly_accessible = false

  tags = merge(var.tags, { role = "reader" })
}
```

## Master Password in Secrets Manager

```hcl
resource "random_password" "master" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "aurora_master" {
  name                    = "/${var.environment}/${var.cluster_name}/master-password"
  kms_key_id              = aws_kms_key.aurora.id
  recovery_window_in_days = 30
}

resource "aws_secretsmanager_secret_version" "aurora_master" {
  secret_id = aws_secretsmanager_secret.aurora_master.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.master.result
    host     = aws_rds_cluster.main.endpoint
    port     = 5432
    dbname   = var.database_name
  })
}
```

## KMS Encryption

```hcl
resource "aws_kms_key" "aurora" {
  description             = "Aurora cluster ${var.cluster_name} encryption"
  deletion_window_in_days = 14
  enable_key_rotation     = true

  tags = merge(var.tags, { Name = "${var.cluster_name}-aurora-key" })
}
```

## Enhanced Monitoring IAM

```hcl
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.cluster_name}-rds-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
```

## CloudWatch Alarms

```hcl
resource "aws_cloudwatch_metric_alarm" "aurora_cpu" {
  alarm_name          = "${var.cluster_name}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Aurora CPU above 80% for 15 minutes"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.main.cluster_identifier
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "aurora_connections" {
  alarm_name          = "${var.cluster_name}-high-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 800
  alarm_description   = "Aurora connections above 800"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.main.cluster_identifier
  }

  alarm_actions = [var.sns_topic_arn]
}
```

## Outputs

```hcl
output "cluster_endpoint" {
  value = aws_rds_cluster.main.endpoint
}

output "reader_endpoint" {
  value = aws_rds_cluster.main.reader_endpoint
}

output "cluster_id" {
  value = aws_rds_cluster.main.cluster_identifier
}

output "secret_arn" {
  value = aws_secretsmanager_secret.aurora_master.arn
}
```

## Production Checklist

- [ ] Serverless v2 scaling configured (min/max ACUs)
- [ ] Storage encryption with customer-managed KMS key
- [ ] Enhanced monitoring at 60-second intervals
- [ ] Performance Insights enabled with 7-day retention
- [ ] Automated backups with 30-day retention
- [ ] Master password rotated via Secrets Manager
- [ ] Deletion protection enabled in production
- [ ] CloudWatch alarms for CPU and connections
- [ ] Private subnets only (publicly_accessible = false)
- [ ] PostgreSQL audit logs to CloudWatch

Aurora Serverless v2 with this configuration gives you a database that scales ACUs in fine-grained increments (0.5 ACU steps), encrypts everything, and auto-fails over in under 30 seconds — production-grade at any scale.
