variable "project_name" {
  description = "Project name used as a prefix for resource naming"
  type        = string
  default     = "ecomstore"
}

variable "environment" {
  description = "Deployment environment (lab, staging, prod)"
  type        = string
  default     = "lab"
}

variable "aws_region" {
  description = "AWS deployment region"
  type        = string
  default     = "us-east-2"
}

variable "vpc_id" {
  description = "Existing VPC ID to deploy into (leave null to automatically use the Default VPC)"
  type        = string
  default     = null
}

variable "db_username" {
  description = "Master username for RDS PostgreSQL"
  type        = string
  default     = "ecom_admin"
}

variable "db_password" {
  description = "Master password for RDS PostgreSQL"
  type        = string
  sensitive   = true
}

variable "ecom_core_image" {
  description = "Docker image URI for ecom-core-service (Java 21)"
  type        = string
  default     = "528657840844.dkr.ecr.us-east-2.amazonaws.com/ecomstore/ecom-core:latest"
}

variable "ai_agent_image" {
  description = "Docker image URI for ai-agent-service (Java 21)"
  type        = string
  default     = "528657840844.dkr.ecr.us-east-2.amazonaws.com/ecomstore/ai-agent:latest"
}

variable "core_desired_count" {
  description = "Minimum number of tasks for Ecom Core"
  type        = number
  default     = 2
}

variable "agent_desired_count" {
  description = "Minimum number of tasks for AI Agent"
  type        = number
  default     = 2
}