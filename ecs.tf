resource "aws_ecr_repository" "ecom_core" {
  name                 = "${var.project_name}/ecom-core"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "ai_agent" {
  name                 = "${var.project_name}/ai-agent"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_cloudwatch_log_group" "ecom_core" {
  name              = "/ecs/${var.project_name}/ecom-core"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "ai_agent" {
  name              = "/ecs/${var.project_name}/ai-agent"
  retention_in_days = 14
}

data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${var.project_name}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ai_agent_task" {
  name               = "${var.project_name}-ai-agent-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

resource "aws_iam_role_policy" "ai_agent_bedrock" {
  name = "AllowBedrockInvoke"
  role = aws_iam_role.ai_agent_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_service_discovery_http_namespace" "main" {
  name        = "${var.project_name}.local"
  description = "Internal Service Connect namespace"
}

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-${var.environment}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  service_connect_defaults {
    namespace = aws_service_discovery_http_namespace.main.arn
  }
}

resource "aws_ecs_task_definition" "ecom_core" {
  family                   = "${var.project_name}-ecom-core"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name      = "ecom-core"
      image     = var.ecom_core_image
      essential = true
      portMappings = [
        {
          name          = "http"
          containerPort = 8080
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "SERVER_PORT", value = "8080" },
        { name = "JAVA_TOOL_OPTIONS", value = "-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0" },
        { name = "SPRING_THREADS_VIRTUAL_ENABLED", value = "true" },
        { name = "SPRING_DATASOURCE_URL", value = "jdbc:postgresql://${aws_db_instance.postgres.endpoint}/ecomstore" },
        { name = "SPRING_DATASOURCE_USERNAME", value = var.db_username },
        { name = "SPRING_DATASOURCE_PASSWORD", value = var.db_password },
        { name = "SPRING_DATA_REDIS_HOST", value = aws_elasticache_replication_group.redis.primary_endpoint_address }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecom_core.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "ecom_core" {
  name            = "ecom-core-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.ecom_core.arn
  desired_count   = var.core_desired_count
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = data.aws_subnets.selected.ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ecom_core.arn
    container_name   = "ecom-core"
    container_port   = 8080
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.main.arn

    service {
      port_name      = "http"
      discovery_name = "ecom-core"
      client_alias {
        port     = 8080
        dns_name = "ecom-core"
      }
    }
  }

  depends_on = [aws_lb_listener.http]
}

resource "aws_ecs_task_definition" "ai_agent" {
  family                   = "${var.project_name}-ai-agent"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ai_agent_task.arn

  container_definitions = jsonencode([
    {
      name      = "ai-agent"
      image     = var.ai_agent_image
      essential = true
      portMappings = [
        {
          name          = "http"
          containerPort = 8081
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "SERVER_PORT", value = "8081" },
        { name = "JAVA_TOOL_OPTIONS", value = "-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0" },
        { name = "SPRING_THREADS_VIRTUAL_ENABLED", value = "true" },
        { name = "AWS_REGION", value = var.aws_region },
        { name = "ECOM_CORE_BASE_URL", value = "http://ecom-core:8080" },
        { name = "SPRING_DATASOURCE_URL", value = "jdbc:postgresql://${aws_db_instance.postgres.endpoint}/ecomstore" },
        { name = "SPRING_DATASOURCE_USERNAME", value = var.db_username },
        { name = "SPRING_DATASOURCE_PASSWORD", value = var.db_password },
        { name = "SPRING_DATA_REDIS_HOST", value = aws_elasticache_replication_group.redis.primary_endpoint_address }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ai_agent.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "ai_agent" {
  name            = "ai-agent-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.ai_agent.arn
  desired_count   = var.agent_desired_count
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = data.aws_subnets.selected.ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ai_agent.arn
    container_name   = "ai-agent"
    container_port   = 8081
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.main.arn
  }

  depends_on = [aws_lb_listener.http]
}

resource "aws_appautoscaling_target" "ecom_core" {
  max_capacity       = 6
  min_capacity       = var.core_desired_count
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.ecom_core.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ecom_core_cpu" {
  name               = "${var.project_name}-core-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecom_core.resource_id
  scalable_dimension = aws_appautoscaling_target.ecom_core.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecom_core.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70.0
  }
}