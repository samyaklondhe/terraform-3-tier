output "web_public_ip" {
  value = module.web_ec2.public_ip
}

output "app_private_ip" {
  value = module.app_ec2.private_ip
}

output "rds_endpoint" {
  value = module.rds.rds_endpoint
}
