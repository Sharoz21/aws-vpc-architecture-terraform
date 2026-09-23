terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket                      = "tf-test-bucket"
    key                         = "terraform.tfstate"
    region                      = "us-east-1"
    access_key                  = "mock_access_key"
    secret_key                  = "mock_secret_key"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    skip_region_validation      = true
    use_path_style               = true
    dynamodb_table                = "tf-test-lock-table"

    endpoints = {
      s3       = "http://localhost:4566"
      dynamodb = "http://localhost:4566"
    }
  }
}

provider "aws" {
  access_key                  = "mock_access_key"
  region                      = "us-east-1"
  secret_key                  = "mock_secret_key"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    dynamodb       = "http://localhost:4566"
    s3             = "http://localhost:4566"
    ec2            = "http://localhost:4566"
    elbv2          = "http://localhost:4566"
    rds            = "http://localhost:4566"
  }
}

resource "aws_vpc" "tf-test-vpc" {
    cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "tf-test-public-subnet-1" {
    vpc_id = aws_vpc.tf-test-vpc.id
    availability_zone = "us-east-1a"
    cidr_block = cidrsubnet(aws_vpc.tf-test-vpc.cidr_block, 8, 1)
    map_public_ip_on_launch = true
}

resource "aws_subnet" "tf-test-public-subnet-2" {
    vpc_id = aws_vpc.tf-test-vpc.id
    availability_zone = "us-east-1b"
    cidr_block = cidrsubnet(aws_vpc.tf-test-vpc.cidr_block, 8, 2)
    map_public_ip_on_launch = true
}


resource "aws_subnet" "tf-test-private-subnet-1" {
    vpc_id = aws_vpc.tf-test-vpc.id
    availability_zone = "us-east-1a"
    cidr_block = cidrsubnet(aws_vpc.tf-test-vpc.cidr_block, 8, 3)
}


resource "aws_subnet" "tf-test-private-subnet-2" {
    vpc_id = aws_vpc.tf-test-vpc.id
    availability_zone = "us-east-1b"
    cidr_block = cidrsubnet(aws_vpc.tf-test-vpc.cidr_block, 8, 4)
}

resource "aws_internet_gateway" "tf-test-internet-gateway" {
    vpc_id = aws_vpc.tf-test-vpc.id
}

resource "aws_route_table" "tf-test-public-subnet-route-table" {
  vpc_id = aws_vpc.tf-test-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.tf-test-internet-gateway.id
  }
}

resource "aws_route_table_association" "tf-test-public-subnet-route-table-association-1" {
    subnet_id = aws_subnet.tf-test-public-subnet-1.id
    route_table_id = aws_route_table.tf-test-public-subnet-route-table.id
}


resource "aws_route_table_association" "tf-test-public-subnet-route-table-association-2" {
    subnet_id = aws_subnet.tf-test-public-subnet-2.id
    route_table_id = aws_route_table.tf-test-public-subnet-route-table.id
}

resource "aws_security_group" "tf-test-alb-security-group" {
    vpc_id = aws_vpc.tf-test-vpc.id
    name = "tf-test-alb-security-group"

    ingress {
        cidr_blocks = ["0.0.0.0/0"]
        from_port = 80
        to_port = 80
        protocol = "tcp"
    }

    egress {
        cidr_blocks = ["0.0.0.0/0"]
        from_port = 0
        to_port = 0
        protocol = "-1"
    }
}


resource "aws_security_group" "tf-test-ec2-security-group" {
    vpc_id = aws_vpc.tf-test-vpc.id
    name = "tf-test-ec2-security-group"

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        security_groups = [ aws_security_group.tf-test-alb-security-group.id ]
    }

    egress {
        cidr_blocks = ["0.0.0.0/0"]
        from_port = 0
        to_port = 0
        protocol = "-1"
    }
}

resource "aws_instance" "tf-test-ec2-1" {
    ami = "al2023-ami"
    instance_type = "t2.micro"
    vpc_security_group_ids = [aws_security_group.tf-test-ec2-security-group.id]
    subnet_id = aws_subnet.tf-test-private-subnet-1.id
    user_data = <<-EOF
              #!/bin/bash
              echo "Hello World from server 1" > index.html
              python3 -m http.server 80
              EOF
}

resource "aws_instance" "tf-test-ec2-2" {
    ami = "al2023-ami"
    instance_type = "t2.micro"
    vpc_security_group_ids = [aws_security_group.tf-test-ec2-security-group.id]
    subnet_id = aws_subnet.tf-test-private-subnet-2.id
    user_data = <<-EOF
              #!/bin/bash
              echo "Hello World from server 2" > index.html
              python3 -m http.server 80
              EOF
}

resource "aws_lb" "tf-test-alb" {
  name = "tf-test-alb"
  load_balancer_type = "application"
  security_groups = [aws_security_group.tf-test-alb-security-group.id]

  subnets = [
    aws_subnet.tf-test-public-subnet-1.id,
    aws_subnet.tf-test-public-subnet-2.id
  ]
}

resource "aws_lb_target_group" "tf-test-alb-target-group" {
   vpc_id = aws_vpc.tf-test-vpc.id
   name     = "tf-test-alb-target-group"
   port     = 80
   protocol = "HTTP"
}

resource "aws_lb_target_group_attachment" "tf-test-alb-target-group-attachment-1" {
    target_group_arn = aws_lb_target_group.tf-test-alb-target-group.arn
    target_id        = aws_instance.tf-test-ec2-1.id
    port             = 80
}

resource "aws_lb_target_group_attachment" "tf-test-alb-target-group-attachment-2" {
    target_group_arn = aws_lb_target_group.tf-test-alb-target-group.arn
    target_id        = aws_instance.tf-test-ec2-2.id
    port             = 80
}

resource "aws_lb_listener" "tf-test-alb-listener" {
    load_balancer_arn = aws_lb.tf-test-alb.arn
    port = "80"
    protocol = "HTTP"
    
    default_action {
        type = "forward"
        target_group_arn = aws_lb_target_group.tf-test-alb-target-group.arn
    }
}

resource "aws_eip" "tf-test-nat-eip" {
    domain = "vpc"
}

resource "aws_nat_gateway" "tf-test-nat" {
    allocation_id = aws_eip.tf-test-nat-eip.id
    subnet_id = aws_subnet.tf-test-public-subnet-1.id
}

resource "aws_route_table" "tf-test-private-subnet-route-table" {
    vpc_id = aws_vpc.tf-test-vpc.id

    route {
        cidr_block = "0.0.0.0/0"
        nat_gateway_id = aws_nat_gateway.tf-test-nat.id
    }
}

resource "aws_route_table_association" "tf-test-private-subnet-route-table-association-2" {
    subnet_id = aws_subnet.tf-test-private-subnet-1.id
    route_table_id = aws_route_table.tf-test-private-subnet-route-table.id
}

resource "aws_route_table_association" "tf-test-private-subnet-route-table-association-1" {
    subnet_id = aws_subnet.tf-test-private-subnet-2.id
    route_table_id = aws_route_table.tf-test-private-subnet-route-table.id
}


resource "aws_db_subnet_group" "tf-rds-subnet-group" {
  subnet_ids = [aws_subnet.tf-test-private-subnet-1.id, aws_subnet.tf-test-private-subnet-2.id]
}

resource "aws_security_group" "tf-rds-security-group" {
    vpc_id = aws_vpc.tf-test-vpc.id

    ingress {
        from_port = 5432
        to_port = 5432
        security_groups = [aws_security_group.tf-test-ec2-security-group.id]
        protocol = "tcp"
    }
  
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_db_instance" "tf-test-rds" {
    instance_class = "db.t3.micro"
    vpc_security_group_ids = [ aws_security_group.tf-rds-security-group.id ]
    db_subnet_group_name = aws_db_subnet_group.tf-rds-subnet-group.name
    engine = "postgres"
    db_name = "tf_test"
    username = "admin"
    password = "admin"
    allocated_storage = 10
}

