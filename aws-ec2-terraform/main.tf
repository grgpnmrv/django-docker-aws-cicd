provider "aws" {
    region = "us-east-1"
}

resource "aws_s3_bucket" "state_bucket" {
    bucket = "test-project-s3bucket-20241127"
    tags = {
        Name        = "Test Bucket"
        Environment = "Dev"
    }
}

terraform {
    backend "s3" {
        bucket         = "test-project-s3bucket-20241127"
        key            = "terraform/state"
        region         = "us-east-1"
        encrypt        = true
    }
}

resource "aws_vpc" "main_vpc" {
    cidr_block = "10.0.0.0/16"
    tags = {
        Name = "main-vpc"
    }
}

resource "aws_subnet" "main_subnet" {
    vpc_id            = aws_vpc.main_vpc.id
    cidr_block        = "10.0.1.0/24"
    map_public_ip_on_launch = true
    availability_zone = "us-east-1a"

    tags = {
        Name = "main-subnet"
    }
}

resource "aws_internet_gateway" "main_igw" {
    vpc_id = aws_vpc.main_vpc.id

    tags = {
        Name = "main-internet-gateway"
    }
}

resource "aws_route_table" "main_route_table" {
    vpc_id = aws_vpc.main_vpc.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.main_igw.id
    }

    tags = {
        Name = "main-route-table"
    }
}

# Привязка таблицы маршрутизации к подсети
resource "aws_route_table_association" "main_subnet_association" {
    subnet_id      = aws_subnet.main_subnet.id
    route_table_id = aws_route_table.main_route_table.id
}

# Создание Security Group
resource "aws_security_group" "django_sg" {
    vpc_id      = aws_vpc.main_vpc.id
    description = "Allow SSH and HTTP access"

    # Разрешить SSH
    ingress {
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    # Разрешить HTTP
    ingress {
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    # Разрешить весь исходящий трафик
    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "django-security-group"
    }
}

# Создание ключа SSH
resource "aws_key_pair" "deployer_key" {
    key_name   = "deployer-key"
    public_key = file("~/.ssh/id_ed25519.pub") # Укажите путь к вашему публичному SSH-ключу
}

# Создание EC2-инстанса
resource "aws_instance" "django_server" {
    ami           = "ami-0c02fb55956c7d316" # Amazon Linux 2 (замените на ваш региональный AMI)
    instance_type = "t2.micro"

    key_name               = aws_key_pair.deployer_key.key_name
    subnet_id              = aws_subnet.main_subnet.id
    vpc_security_group_ids = [aws_security_group.django_sg.id]

    tags = {
        Name = "django-server"
    }

    # Скрипт для предварительной настройки
    user_data = <<-EOF
                #!/bin/bash
                yum update -y
                yum install docker -y
                systemctl start docker
                systemctl enable docker
                usermod -aG docker ec2-user
    EOF
}

# Вывод IP-адреса инстанса
output "instance_ip" {
    value = aws_instance.django_server.public_ip
}