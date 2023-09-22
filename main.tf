provider "aws" {
  region = "us-east-1"  # Modify this with your desired region
}

# Create VPC, Subnets, IGW, and NAT Gateway
module "vpc" {
  source = "./modules/vpc"
}
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"  # Modify CIDR block as needed
}

resource "aws_subnet" "public" {
  count                  = 1
  vpc_id                 = aws_vpc.main.id
  cidr_block             = "10.0.1.${count.index}/24"
  availability_zone      = "us-east-1a"  # Modify AZs as needed
  map_public_ip_on_launch = true

  tags = {
    Name = "public-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count                  = 1
  vpc_id                 = aws_vpc.main.id
  cidr_block             = "10.0.2.${count.index}/24"
  availability_zone      = "us-east-1a"  # Modify AZs as needed

  tags = {
    Name = "private-${count.index + 1}"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table_association" "public" {
  count          = 1
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
  depends_on     = [aws_subnet.public]
}

resource "aws_nat_gateway" "main" {
  count                 = 1
  allocation_id         = aws_eip.main[count.index].id
  subnet_id             = aws_subnet.public[count.index].id
  depends_on            = [aws_subnet.public]
}

resource "aws_eip" "main" {
  count = 1
}


# Create CMK Key
resource "aws_kms_key" "cmk_key" {
  description             = "CMK Key for encryption"
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.cmk_policy.json
}

data "aws_iam_policy_document" "cmk_policy" {
  # Define the policy for the CMK key
  # Modify this according to your security requirements
  statement {
    actions   = ["kms:*"]
    resources = ["*"]
    effect    = "Allow"
  }
}

# Create EC2 Instance
module "ec2_instance" {
  source        = "./modules/ec2_instance"
  subnet_id     = module.vpc.private_subnet_ids[0]  # Adjust this according to your subnet setup
  key_name      = "terraform"
  cmk_key_arn   = aws_kms_key.cmk_key.arn
}

resource "aws_instance" "example" {
  ami           = "ami-03a6eaae9938c858c"  # Specify your desired AMI
  instance_type = "t2.micro"          # Modify instance type as needed
  subnet_id     = var.subnet_id
  key_name      = var.key_name

  root_block_device {
    volume_type           = "gp2"
    encrypted             = true
    kms_key_id            = var.cmk_key_arn
  }

  tags = {
    Name = "example-ec2"
  }
}

# Create RDS Instance
module "rds_instance" {
  source        = "./modules/rds_instance"
  subnet_ids    = module.vpc.private_subnet_ids  # Use all private subnets
  cmk_key_arn   = aws_kms_key.cmk_key.arn
}

resource "aws_db_instance" "example" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"  # Modify this according to your database engine
  engine_version       = "5.7"
  instance_class       = "db.t2.micro"  # Modify instance type as needed
  name                 = "example-db"
  username             = "db_user"  # Specify your database username
  password             = "db_password"  # Specify your database password
  subnet_group_name    = "default"
  vpc_security_group_ids = [aws_security_group.default.id]
  skip_final_snapshot  = true
  backup_retention_period = 7
  multi_az             = false
  db_subnet_group_name = aws_db_subnet_group.default.name
  kms_key_id           = var.cmk_key_arn
}

resource "aws_security_group" "default" {
  name        = "default"
  description = "Default security group for RDS"
  vpc_id      = aws_vpc.main.id
}

resource "aws_db_subnet_group" "default" {
  name       = "default"
  subnet_ids = var.subnet_ids
}

