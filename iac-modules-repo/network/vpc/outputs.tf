output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "List of IDs of public subnets"
  value       = module.vpc.public_subnets
}

output "database_subnets" {
  description = "List of IDs of database subnets"
  value       = module.vpc.database_subnets
}

output "database_subnet_group_name" {
  description = "Name of database subnet group"
  value       = module.vpc.database_subnet_group_name
}

output "nat_public_ips" {
  description = "List of public Elastic IP addresses created for HTTP Load Balancing"
  value       = module.vpc.nat_public_ips
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "ssm_vpc_id_parameter" {
  description = "SSM Parameter Store name for VPC ID"
  value       = try(aws_ssm_parameter.vpc_id[0].name, null)
}

output "ssm_database_subnets_parameter" {
  description = "SSM Parameter Store name for database subnets"
  value       = try(aws_ssm_parameter.database_subnets[0].name, null)
}
