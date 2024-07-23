# ************************* EXAMPLE OF A SMALL PERSONAL SERVER *************************
# * CREATE RESOURCES
# * Step 0 : Configure environment variables
# ! NOTE: this configuration is only suitable for tutorial / personal purposes
# In prod, IAM roles with least privilege are preferred and are standard practice
variable "AWS_ACCESS_KEY" {
  type = string
}
variable "AWS_SECRET_KEY" {
  type = string
}

# * Step 1 : Define a Provider
# For this project, I've chosen AWS
# For a list of providers : https://registry.terraform.io/browse/providers

provider "aws" {
  region     = "us-east-2"
  access_key = var.AWS_ACCESS_KEY
  secret_key = var.AWS_SECRET_KEY
}

# * Step 2 : Create and deploy Amazon EC2 Instance
# resource "<provider>_<resource_type>" "name" { config options... key = "value" }
# Deploy EC2 Instance with Ubuntu AMI in AWS
# resource "aws_instance" "terraform-example" {
#   ami           = "ami-0862be96e41dcbf74" # AMI for Ubuntu 24.04 LTS
#   instance_type = "t2.micro"
#   tags = {
#     name = "ubuntu"
#   }
# }

# * Step 3 : Open terminal and run 'terraform init' in the project directory
# This will download any provider plugins specified i.e. lines 8 to 12

# * Step 4 : In terminal, run 'terraform plan' 
# This will perform a 'dry run' of code to see what exactly will be deployed and how

# * Step 5 : Apply Environment Variables & Create Instance
# In terminal run 'terraform apply -var AWS_ACCESS_KEY=[value] AWS_SECRET_KEY=[value]'
# This starts the main.tf script, as well as initializes the private AWS variables needed for authentication
# NOTE: Terraform will prompt you for these values on each command run. This configuration is for tutorial purposes only
# In production, IAM roles are preferred / standard practice

# After a brief wait, the instance should be running - check AWS console to confirm

# * UPDATE RESOURCES
# Simply make changes in .tf files and re-run terraform apply

# * DELETE RESOURCES
# In the CLI, run 'terraform destroy'
# Any resourses specified in this file will be marked for deletion
# Additionally, we can delete pre-defined resources and run 'terraform apply' for the same result

# ************************* PROD EXAMPLE *************************
# * CREATE VPC (Virtual Private Cloud)

resource "aws_vpc" "prod-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "production"
  }
}

# Create Internet Gateway

resource "aws_internet_gateway" "prod-gateway" {
  vpc_id = aws_vpc.prod-vpc.id
}

# Create Custom Route Table
# Internet traffic can route out from the subnet into outside internet
resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.prod-vpc.id

  route {
    cidr_block = "0.0.0.0/0" # default route : all traffic will be sent to internet gateway
    gateway_id = aws_internet_gateway.prod-gateway.id
  }

  route {
    ipv6_cidr_block = "::/0" # ipV6 default route
    gateway_id      = aws_internet_gateway.prod-gateway.id
  }

  tags = {
    Name = "prod-gateway"
  }
}

# Create Subnet

resource "aws_subnet" "subnet-1" {
  vpc_id            = aws_vpc.prod-vpc.id
  cidr_block        = "10.0.0.0/24" # Subnet
  availability_zone = "us-east-2a"  # Optional : Availability zone

  tags = {
    Name = "prod-subnet"
  }
}

# Associate Subnet with Route Table
resource "aws_route_table_association" "prod-association" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.prod-route-table.id
}

# Create Security Group to allow web traffic through ports 22, 80, and 443

resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow web inbound traffic"
  vpc_id      = aws_vpc.prod-vpc.id

  ingress {
    description = "HTTPS traffic"
    from_port   = 443
    to_port     = 443 # can be a range : here, just a single port is allowed
    protocol    = "tcp"
    # cidr_blocks : specifies which devices can reach this (in the case of a webserver, we change to default route)
    cidr_blocks = ["0.0.0.0/0"] # can specify which subnets w/ [aws_vpc.prod-vpc.cidr_block] or even specific IP of machine
  }

  ingress {
    description = "HTTP traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # any protocol
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_web"
  }
}

# Create Network Interface 

# Provides private IP address
resource "aws_network_interface" "webserver-nic" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]

  # will speficy attachments later when spinning up EC2 instance
}

# Create Elastic (Public) IP Address

# Relies on the deployment of internet gateway first
resource "aws_eip" "one" {
  network_interface         = aws_network_interface.webserver-nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on                = [aws_internet_gateway.prod-gateway]
}

# Create Ubuntu Server & Install / Enable Apache2
resource "aws_instance" "web-server-instance" {
  ami               = "ami-0862be96e41dcbf74" # Ubuntu 24.04 LTS
  instance_type     = "t2.micro"
  availability_zone = "us-east-2a"
  key_name          = "devops"
  network_interface {
    device_index         = 0 # first network interface associated with this device
    network_interface_id = aws_network_interface.webserver-nic.id
  }

  # automatically run a command to install Apache2
  # last line copies text to index.html to confirm commands worked
  user_data = <<-EOF
                #!/bin/bash
                sudo apt update -y
                sudo apt install apache2 -y
                sudo systemctl start apache2
                sudo bash -c 'echo web server successfully deployed > /var/www/html/index.html'
                EOF

  tags = {
    Name = "web-server"
  }
}

