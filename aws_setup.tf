
##################################################################################
# VARIABLES
##################################################################################

variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "environment_tag" {}
variable "project_tag" {}
variable "key_name" {}
#variable "shared_credentials" {}
variable "private_key_path" {}

variable "instance_count" {
  default = 2
}

variable "subnet_count" {
  default = 2
}

variable "network_address_space" {
  default = "10.1.0.0/16"
}

variable "region" {
  default = "us-west-2"
}

variable "instance_type" {
  default = "t2.micro"
}

variable "amis" {
  type = "map"
  default = {
    us-west-1 = "ami-0bce08e823ed38bdd"
    us-west-2 = "ami-08d489468314a58df"
  }
}

variable "lb_listener_port" { default = 80 }
variable "lb_listener_protocol" { default = "HTTP" }
variable "target_group_sticky" { default = "true" }
variable "instance_port" { default = 80 }

###################################################################################
# PROVIDERS
###################################################################################

provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  #shared_credentials_file = "${var.shared_credentials}"
  profile = "default"
  region  = "${var.region}"
}


##################################################################################
# DATA
##################################################################################

data "aws_availability_zones" "available" {}


###################################################################################
# RESOURCES
###################################################################################

# NETWORKING #

# Create VPC
resource "aws_vpc" "vpc" {
  cidr_block = "${var.network_address_space}"
  tags = {
    Name        = "${var.project_tag}-${var.environment_tag}-vpc"
    Environment = "${var.environment_tag}"
    Project     = "${var.project_tag}"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.vpc.id}"
  tags = {
    Name        = "${var.project_tag}-${var.environment_tag}-igw"
    Environment = "${var.environment_tag}"
    Project     = "${var.project_tag}"
  }
}

# Create Subnet
resource "aws_subnet" "subnet" {
  count                   = "${var.subnet_count}"
  cidr_block              = "${cidrsubnet(var.network_address_space, 8, count.index + 1)}"
  vpc_id                  = "${aws_vpc.vpc.id}"
  availability_zone       = "${data.aws_availability_zones.available.names[count.index]}"
  map_public_ip_on_launch = "true"
  tags = {
    Name        = "${var.project_tag}-${var.environment_tag}-subnet-${count.index + 1}"
    Environment = "${var.environment_tag}"
    Project     = "${var.project_tag}"
  }
}

# ROUTING #
resource "aws_route_table" "rtb" {
  vpc_id = "${aws_vpc.vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.igw.id}"
  }
  tags = {
    Name        = "${var.project_tag}-${var.environment_tag}-rtb"
    Environment = "${var.environment_tag}"
    Project     = "${var.project_tag}"
  }
}

resource "aws_route_table_association" "rta-subnet" {
  count          = "${var.subnet_count}"
  subnet_id      = "${element(aws_subnet.subnet.*.id, count.index)}"
  route_table_id = "${aws_route_table.rtb.id}"
}


# SECURITY GROUPS #

resource "aws_security_group" "lb-sg" {
  name   = "${var.project_tag}-${var.environment_tag}-lb-sg"
  vpc_id = "${aws_vpc.vpc.id}"

  # Allow HTTP from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All HTTP from anywhere"
  }
  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }
  tags = {
    Name        = "${var.project_tag}-${var.environment_tag}-lb-sg"
    Environment = "${var.environment_tag}"
    Project     = "${var.project_tag}"
  }
}

resource "aws_security_group" "instance-sg" {
  name   = "${var.project_tag}-${var.environment_tag}-ins-sg"
  vpc_id = "${aws_vpc.vpc.id}"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow SSH from anywhere"
  }

  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    #cidr_blocks = ["${var.network_address_space}"]
    #description = "Allow HTTP only from other instances internally"
    security_groups = ["${aws_security_group.lb-sg.id}"]
    description     = "Allow load balancer security rules on instances"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name        = "${var.project_tag}-${var.environment_tag}-ins-sg"
    Environment = "${var.environment_tag}"
    Project     = "${var.project_tag}"
  }
}

# LOAD BALANCER #

resource "aws_lb" "web-lb" {
  name = "${var.project_tag}-${var.environment_tag}-web-lb"

  subnets = "${aws_subnet.subnet.*.id}"
  #instances = "${aws_instance.instance.*.id}"
  security_groups = ["${aws_security_group.lb-sg.id}"]
  tags = {
    Name        = "${var.project_tag}-${var.environment_tag}-web-lb"
    Environment = "${var.environment_tag}"
    Project     = "${var.project_tag}"
  }
}

resource "aws_lb_listener" "lb_listener" {
  load_balancer_arn = "${aws_lb.web-lb.arn}"
  port              = "${var.lb_listener_port}"
  protocol          = "${var.lb_listener_protocol}"
  default_action {
    target_group_arn = "${aws_lb_target_group.lb_target_group.arn}"
    type             = "forward"
  }
}

resource "aws_lb_target_group" "lb_target_group" {
  name     = "${var.project_tag}-${var.environment_tag}-lb-target-group"
  port     = "${var.instance_port}"
  protocol = "HTTP"
  vpc_id   = "${aws_vpc.vpc.id}"
  tags = {
    name = "${var.project_tag}-${var.environment_tag}-lb-target-group"
  }
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 1800
    enabled         = "${var.target_group_sticky}"
  }
}

resource "aws_lb_target_group_attachment" "lb_tg_attachment" {
  count            = "${var.instance_count}"
  target_group_arn = "${aws_lb_target_group.lb_target_group.arn}"
  target_id        = "${element(aws_instance.instance.*.id, count.index)}"
  port             = 80
}

# INSTANCES #

resource "aws_instance" "instance" {
  count                  = "${var.instance_count}"
  ami                    = "${lookup(var.amis, var.region)}"
  instance_type          = "${var.instance_type}"
  key_name               = "${var.key_name}"
  subnet_id              = "${element(aws_subnet.subnet.*.id, count.index % var.subnet_count)}"
  vpc_security_group_ids = ["${aws_security_group.instance-sg.id}"]


  provisioner "remote-exec" {
    connection {
      user        = "ec2-user"
      host        = "${self.public_ip}"
      private_key = "${file(var.private_key_path)}"
    }

    inline = [
      "sudo yum install nginx -y",
      "sudo service nginx start"
    ]
  }

  tags = {
    Name        = "${var.project_tag}-${var.environment_tag}-instance-${count.index + 1}"
    Environment = "${var.environment_tag}"
    Project     = "${var.project_tag}"
  }
}


###################################################################################
# OUTPUT
###################################################################################

output "aws_lb_public_dns" {
  value = "${aws_lb.web-lb.dns_name}"
}


