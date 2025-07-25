module "vpc" {
  source              = "./modules/vpc"
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidrs = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones  = var.availability_zones
}

module "web_ec2" {
  source            = "./modules/ec2"
  ami_id            = var.ami_id
  instance_type     = var.instance_type
  subnet_id         = module.vpc.public_subnet_ids[0]
  security_group_id = module.vpc.web_sg_id
  user_data         = file("ansible/web_user_data.sh")
  instance_name     = "web-tier"
  key_name          = var.key_name
}

module "app_ec2" {
  source            = "./modules/ec2"
  ami_id            = var.ami_id
  instance_type     = var.instance_type
  subnet_id         = module.vpc.private_subnet_ids[0]
  security_group_id = module.vpc.app_sg_id
  user_data         = file("ansible/app_user_data.sh")
  instance_name     = "app-tier"
  key_name          = var.key_name
}

module "rds" {
  source            = "./modules/rds"
  subnet_ids        = module.vpc.private_subnet_ids
  security_group_id = module.vpc.app_sg_id
  instance_class    = "db.t3.micro"
  db_username       = var.db_username
  db_password       = var.db_password
  vpc_id            = module.vpc.vpc_id # Pass VPC ID
}

resource "local_file" "ansible_inventory" {
  content = <<EOT
[web]
${module.web_ec2.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=/home/ubuntu/.ssh/project.pem

[app]
${module.app_ec2.private_ip} ansible_user=ubuntu ansible_ssh_private_key_file=/home/ubuntu/.ssh/project.pem ansible_ssh_extra_args='-o ProxyCommand="ssh -i /home/ubuntu/.ssh/project.pem -W %h:%p ubuntu@${module.web_ec2.public_ip}"'
EOT
  filename = "ansible/inventory.ini"
}

resource "local_file" "web_setup_yml" {
  content = <<EOT
- hosts: web
  become: yes
  tasks:
    - name: Install Nginx
      apt:
        name: nginx
        state: present
        update_cache: yes
    - name: Start and enable Nginx
      systemd:
        name: nginx
        enabled: yes
        state: started
    - name: Create registration form
      copy:
        content: |
          <!DOCTYPE html>
          <html>
          <body>
            <h2>Registration Form</h2>
            <form action="/submit.php" method="post">
              Name: <input type="text" name="name"><br>
              Email: <input type="text" name="email"><br>
              <input type="submit">
            </form>
          </body>
          </html>
        dest: /var/www/html/index.html
        owner: www-data
        group: www-data
        mode: '0644'
        force: yes
    - name: Upload SSH key to web EC2
      copy:
        src: "/home/ubuntu/.ssh/project.pem"
        dest: /home/ubuntu/project.pem
        mode: '0600'
        owner: ubuntu
        group: ubuntu
    - name: Configure Nginx as proxy to app instance
      copy:
        content: |
          server {
              listen 80;
              server_name _;
              location /submit.php {
                  proxy_pass http://${module.app_ec2.private_ip}/submit.php;
                  proxy_set_header Host $host;
                  proxy_set_header X-Real-IP $remote_addr;
                  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              }
              location / {
                  root /var/www/html;
                  index index.html;
              }
          }
        dest: /etc/nginx/sites-available/default
        mode: '0644'
    - name: Test Nginx configuration
      command: nginx -t
      register: nginx_test
      failed_when: nginx_test.rc != 0
    - name: Reload Nginx
      systemd:
        name: nginx
        state: reloaded
EOT
  filename = "ansible/web_setup.yml"
}

resource "local_file" "app_setup_yml" {
  content = <<EOT
- hosts: app
  become: yes
  tasks:
    - name: Install Apache and PHP
      apt:
        name:
          - apache2
          - php
          - libapache2-mod-php
          - php-mysql
        state: present
        update_cache: yes
    - name: Start and enable Apache
      systemd:
        name: apache2
        enabled: yes
        state: started
    - name: Ensure /var/www/html directory exists
      file:
        path: /var/www/html
        state: directory
        owner: www-data
        group: www-data
        mode: '0755'
    - name: Create submit.php
      copy:
        content: |
          <?php
          $name = $_POST['name'];
          $email = $_POST['email'];
          $host = "${split(":", module.rds.rds_endpoint)[0]}";
          $username = "${var.db_username}";
          $password = "${var.db_password}";
          $dbname = "mydb";

          $conn = new mysqli($host, $username, $password, $dbname);
          if ($conn->connect_error) {
              die("Connection failed: " . $conn->connect_error);
          }

          $sql = "CREATE TABLE IF NOT EXISTS users (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(50), email VARCHAR(50))";
          $conn->query($sql);

          $sql = "INSERT INTO users (name, email) VALUES ('$name', '$email')";
          if ($conn->query($sql) === TRUE) {
              echo "Registration successful!";
          } else {
              echo "Error: " . $sql . "<br>" . $conn->error;
          }
          $conn->close();
          ?>
        dest: /var/www/html/submit.php
        owner: www-data
        group: www-data
        mode: '0644'
    - name: Install MySQL client
      apt:
        name: mysql-client
        state: present
    - name: Create database
      command: mysql -h ${split(":", module.rds.rds_endpoint)[0]} -u ${var.db_username} -p${var.db_password} -e "CREATE DATABASE IF NOT EXISTS mydb"
EOT
  filename = "ansible/app_setup.yml"
}

resource "null_resource" "ansible_playbooks" {
  depends_on = [
    module.web_ec2,
    module.app_ec2,
    module.rds,
    local_file.ansible_inventory,
    local_file.web_setup_yml,
    local_file.app_setup_yml
  ]
  provisioner "local-exec" {
    command = <<-EOT
      sleep 120
      ansible-playbook -i ansible/inventory.ini ansible/web_setup.yml
      ansible-playbook -i ansible/inventory.ini ansible/app_setup.yml
    EOT
  }
}
