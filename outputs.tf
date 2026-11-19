output "alb_dns_name" {
  description = "Public access URL for EcomStore & AI Agent"
  value       = "http://${aws_lb.main.dns_name}"
}

output "ecr_ecom_core_url" {
  description = "ECR repository URL for ecom-core-service"
  value       = aws_ecr_repository.ecom_core.repository_url
}

output "ecr_ai_agent_url" {
  description = "ECR repository URL for ai-agent-service"
  value       = aws_ecr_repository.ai_agent.repository_url
}

output "rds_endpoint" {
  description = "Connection endpoint for Multi-AZ RDS PostgreSQL"
  value       = aws_db_instance.postgres.endpoint
}

output "redis_primary_endpoint" {
  description = "Primary connection endpoint for Multi-AZ ElastiCache Redis"
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}