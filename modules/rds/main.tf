resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-subnet-group"
  subnet_ids = var.subnet_ids
  tags = {
    Name = "RDS Subnet Group"
  }
}

resource "aws_security_group" "db_sg" {
  name        = "rds-security-group"
  description = "Security group for RDS"
  vpc_id      = var.vpc_id # Use passed vpc_id instead of data source

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [var.security_group_id] # Allow from app tier SG
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "RDS Security Group"
  }
}

resource "aws_db_instance" "rds_instance" {
  engine            = "mysql"
  engine_version    = "5.7"
  instance_class    = var.instance_class
  allocated_storage = 20
  db_name           = "mydb"
  username          = var.db_username
  password          = var.db_password
  db_subnet_group_name = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  skip_final_snapshot = true
  publicly_accessible = false
  tags = {
    Name = "RDS MySQL Instance"
  }
}
