# Configure the AWS provider
provider "aws" {
  region = "ap-south-1" # Update with your desired region
}

# Create a new key pair
#resource "aws_key_pair" "new_key_pair" {
#  key_name   = "my-keypair"
#  public_key = file("~/.ssh/my-keypair.pub") # Update with the path to your public key
#}

# Create a VPC
resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"

 tags = {
    Name = "tvp-vpc"
  }
}
# Retrieve availability zones
data "aws_availability_zones" "available" {}

# Create public subnets
resource "aws_subnet" "tvp-public_subnet" {
  count                  = 2
  vpc_id                 = aws_vpc.my_vpc.id
  cidr_block             = "10.0.${count.index}.0/24"
  map_public_ip_on_launch = true
  availability_zone      = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "tvp-public subnets"
  }
}

# Create private subnets
resource "aws_subnet" "private_subnet" {
  count                  = 2
  vpc_id                 = aws_vpc.my_vpc.id
  cidr_block             = "10.0.${count.index + 2}.0/24"
  map_public_ip_on_launch = false
  availability_zone      = element(data.aws_availability_zones.available.names, count.index)
   tags = {
    Name = "tvp-private subnets"
  }

}
resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id
}

# Create a security group for the EC2 instance
resource "aws_security_group" "instance_sg" {
  vpc_id = aws_vpc.my_vpc.id

  # Allow SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    #cidr_blocks = [aws_subnet.public_subnet[0].cidr_block, aws_subnet.public_subnet[1].cidr_block]
  }
    ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  
    #cidr_blocks = [aws_subnet.public_subnet[0].cidr_block, aws_subnet.public_subnet[1].cidr_block]
  }

  // Egress rule (Allow all outbound traffic)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
   tags = {
    Name = "tvp-instance-security group"
  }
}

resource "tls_private_key" "oskey" {
  algorithm = "RSA"
}

resource "local_file" "myterrakey" {
  content  = tls_private_key.oskey.private_key_pem
  filename = "myterrakey.pem"
}

resource "aws_key_pair" "key121" {
  key_name   = "myterrakey"
  public_key = tls_private_key.oskey.public_key_openssh
}

resource "aws_instance" "my_instance" {
  ami           = "ami-03f4878755434977f"
  instance_type = "t2.micro"
  key_name      = aws_key_pair.key121.key_name
  #subnet_id     = aws_subnet.tvp-public_subnet[0].id
  #security_groups = [aws_security_group.instance_sg.id]
  #security_groups   =  [aws_security_group.instance_sg.id]
  vpc_security_group_ids = [aws_security_group.instance_sg.id]
  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install nginx -y
              sudo systemctl start nginx
              EOF

  tags = {
    Name = "my_ec2_instance_with_nginx"
  }

}


# Create a target group for the load balancer
resource "aws_lb_target_group" "my_target_group" {
  name     = "my-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.my_vpc.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
  }
  #for_each = toset(aws_instance.web_server.*.id)
  #targets {
  #  id = each.key
  #  port = 80
 # }
  tags = {
    Name = "tvp-target group"
  }
}

# Register EC2 instances as targets with the target group
#resource "aws_lb_target_group_attachment" "ec2_target_attachment" {
 # count            = length(aws_instance.my_instances[*].id)
#  target_group_arn = aws_lb_target_group.my_target_group.arn
#  target_id        = [aws_instance.my_instances.id]
#}
resource "aws_lb_target_group_attachment" "my_target_group" {
  for_each = toset([aws_instance.my_instance.id])
  target_group_arn = aws_lb_target_group.my_target_group.arn
  target_id        = each.key
  port             = 80
}


# Create an Application Load Balancer
resource "aws_lb" "my_alb" {
  name               = "tvp-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.instance_sg.id]
  subnets            = [aws_subnet.tvp-public_subnet[0].id, aws_subnet.tvp-public_subnet[1].id]

  tags = {
    Name = "tvp-alb"
  }
}

# Create a listener for the ALB
resource "aws_lb_listener" "my_listener" {
  load_balancer_arn = aws_lb.my_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_target_group.arn
  }
}
# Create a DB subnet group
resource "aws_db_subnet_group" "my_db_subnet_group" {
  name       = "my-rds-subnet-group"
  subnet_ids = [aws_subnet.private_subnet[0].id, aws_subnet.private_subnet[1].id]
}

# Create a PostgreSQL RDS instance
resource "aws_db_instance" "demo1_rds" {
  identifier           = "my-rds"
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "postgres"
  engine_version       = "15.5"
  instance_class       = "db.t3.micro"
 # name                 = "mydatabase"
  username             = "jaimahadev"
  password             = "password"
  publicly_accessible = false
  db_subnet_group_name = "my-rds-subnet-group"
}

# Create a Route53 hosted zone
resource "aws_route53_zone" "my_zone" {
  name = "test.engineersmind.com"
}

# Create a Route53 record for the ALB
resource "aws_route53_record" "alb_record" {
  zone_id = aws_route53_zone.my_zone.zone_id
  name    = "my-alb.test.engineersmind.com"
  type    = "A"
  alias {
    name                   = aws_lb.my_alb.dns_name
    zone_id                = aws_lb.my_alb.zone_id
    evaluate_target_health = true
  }
}

# Create two route tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.my_vpc.id
  tags = {
    Name = "tvp-public_route_table"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.my_vpc.id
   tags = {
    Name = "tvp-public_route_table"
  }
}

# Associate public subnets with the public route table
resource "aws_route_table_association" "public_route_table_association" {
  count          = 2
  subnet_id      = aws_subnet.tvp-public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
  
}

# Associate private subnets with the private route table
resource "aws_route_table_association" "private_route_table_association" {
  count          = 2
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_route_table.id
  
}

# Create a NAT Gateway
resource "aws_nat_gateway" "my_nat_gateway" {
  allocation_id = aws_eip.my_eip.id
  subnet_id     = aws_subnet.tvp-public_subnet[0].id # Choose one of your public subnets
}

# Create a new Elastic IP address
resource "aws_eip" "my_eip" {
  vpc = true
}

# Update the route table for the private subnets to route internet-bound traffic through the NAT Gateway
resource "aws_route" "private_route_to_nat" {
  route_table_id            = aws_route_table.private_route_table.id
  destination_cidr_block    = "0.0.0.0/0"
  nat_gateway_id            = aws_nat_gateway.my_nat_gateway.id
}

# Update the route table for the public subnets to route internet-bound traffic directly
resource "aws_route" "public_route_to_internet" {
  route_table_id            = aws_route_table.public_route_table.id
  destination_cidr_block    = "0.0.0.0/0"
  gateway_id                = aws_internet_gateway.my_igw.id
}

#output "instance_key_pair" {
#  value = aws_key_pair.myterrakey.key_name
#}