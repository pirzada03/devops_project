terraform {
  required_version = ">= 0.12"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}
provider "aws" {
  region = "us-east-1"
}
# Create a new VPC
resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "MyTerraformVpc"
  }
}
# Create a subnet within the VPC
resource "aws_subnet" "my_subnet" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = true
  tags = {
    Name = "PublicSubnet"
  }
}
# Create an Internet Gateway
resource "aws_internet_gateway" "my_gateway" {
  vpc_id = aws_vpc.my_vpc.id
}
# Create a Route Table
resource "aws_route_table" "my_route_table" {
  vpc_id = aws_vpc.my_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_gateway.id
  }
}
# Associate Route Table with Subnet
resource "aws_route_table_association" "my_route_table_association" {
  subnet_id      = aws_subnet.my_subnet.id
  route_table_id = aws_route_table.my_route_table.id
}
# Generate Private Key
resource "tls_private_key" "rsa_4096" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
# Create Key Pair for SSH access
resource "aws_key_pair" "key_pair" {
  key_name   = "terraform-key"
  public_key = tls_private_key.rsa_4096.public_key_openssh
}
# Save the private key locally
resource "local_file" "private_key" {
  content  = tls_private_key.rsa_4096.private_key_pem
  filename = "terraform-key.pem"
  provisioner "local-exec" {
    command = "chmod 400 ${self.filename}"
  }
}
# Create a Security Group
resource "aws_security_group" "sg_ec2" {
  name        = "sg_ec2"
  description = "Security group for EC2 instances in VPC"
  vpc_id      = aws_vpc.my_vpc.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
# Create an EC2 instance
resource "aws_instance" "my_instance" {
  ami                    = "ami-04a81a99f5ec58529"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.my_subnet.id
  key_name               = aws_key_pair.key_pair.key_name
  vpc_security_group_ids = [aws_security_group.sg_ec2.id]
  associate_public_ip_address = true
  tags = {
    Name = "MyEC2Instance"
  }

  provisioner "local-exec" {
    command = "touch inventory.ini"
  }

  provisioner "remote-exec" {
      inline = [
        "echo 'EC2 instance is ready.'"
      ]

      connection {
        type        = "ssh"
        host        = aws_instance.my_instance.public_ip
        user        = "ubuntu"
        private_key = tls_private_key.rsa_4096.private_key_pem
      }
  }
}


# Output Instance IP
output "instance_ip" {
  value = aws_instance.my_instance.public_ip
}



resource "local_file" "inventory" {
  depends_on = [aws_instance.my_instance]

  filename = "${path.module}/inventory.ini"
  content = templatefile("${path.module}/inventory.tmpl", {
    instance_ip = aws_instance.my_instance.public_ip,
    key_path = "${path.module}/terraform-key.pem"
  })

  provisioner "local-exec" {
    command = "chmod 400 ${self.filename}"
  }
}


resource "null_resource" "run_ansible" {
  depends_on = [local_file.inventory]

  provisioner "local-exec" {
    command = "ansible-playbook -i inventory.ini docker-install.yml"
    working_dir = path.module
  }
}