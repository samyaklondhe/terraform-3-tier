# 3-Tier Infrastructure Deployment Using Terraform Modules

## Project 5: Internship Task

### Objective
Design and deploy a 3-tier web application architecture on AWS using Terraform modules and Ansible for automation.

### Prerequisites
- AWS account with credentials configured (~/.aws/credentials).
- Terraform installed.
- Ansible installed.
- SSH key pair (project-key) created in AWS and available locally as /home/ubuntu/.ssh/project.pem.
- Ubuntu 22.04 AMI (ami-0c55b159cbfafe1f0) or equivalent.

### Steps to Deploy
1. Clone the repository:
   ```bash
   git clone https://github.com/samyaklondhe/terraform-3-tier.git
   cd terraform-3-tier
