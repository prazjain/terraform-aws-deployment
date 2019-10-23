
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
variable "bucket_name" {}

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
variable "lb_logs_prefix" { default = "web-lb" }

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
data "aws_elb_service_account" "lb-service-account" {}
resource "aws_lb" "web-lb" {
  name = "${var.project_tag}-${var.environment_tag}-web-lb"

  subnets         = "${aws_subnet.subnet.*.id}"
  security_groups = ["${aws_security_group.lb-sg.id}"]
  access_logs {
    bucket  = "${aws_s3_bucket.web_bucket.bucket}"
    prefix  = "${var.lb_logs_prefix}"
    enabled = true
  }
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

# INSTANCES #

resource "aws_instance" "template-instance" {
  ami                    = "${lookup(var.amis, var.region)}"
  instance_type          = "${var.instance_type}"
  key_name               = "${var.key_name}"
  subnet_id              = "${element(aws_subnet.subnet.*.id, 0)}" /* Get 1st subnet id, for this template instance */
  vpc_security_group_ids = ["${aws_security_group.instance-sg.id}"]

  provisioner "file" {
    connection {
      user        = "ec2-user"
      host        = "${self.public_ip}"
      private_key = "${file(var.private_key_path)}"
    }
    content = <<EOF
access_key = ${aws_iam_access_key.write_user.id}
secret_key = ${aws_iam_access_key.write_user.secret}
use_https = True
bucket_location = US

EOF

    destination = "/home/ec2-user/.s3cfg"
  }

  provisioner "file" {
    connection {
      user        = "ec2-user"
      host        = "${self.public_ip}"
      private_key = "${file(var.private_key_path)}"
    }

    content = <<EOF
/var/log/nginx/*log {
    daily
    rotate 10
    missingok
    compress
    sharedscripts
    postrotate
      INSTANCE_ID=`curl --silent http://169.254.169.254/latest/meta-data/instance-id`
      /usr/local/bin/s3cmd sync /var/log/nginx/access.log-* s3://${aws_s3_bucket.web_bucket.id}/$INSTANCE_ID/nginx/
      /usr/local/bin/s3cmd sync /var/log/nginx/error.log-* s3://${aws_s3_bucket.web_bucket.id}/$INSTANCE_ID/nginx/    
    endscript
}

EOF

    destination = "/home/ec2-user/nginx"
  }

  provisioner "remote-exec" {
    connection {
      user        = "ec2-user"
      host        = "${self.public_ip}"
      private_key = "${file(var.private_key_path)}"
    }

    inline = [
      "sudo cp /home/ec2-user/.s3cfg /root/.s3cfg",
      "sudo cp /home/ec2-user/nginx /etc/logrotate.d/nginx",
      "sudo pip install s3cmd",
      "sudo logrotate -f /etc/logrotate.conf",
      "sudo yum install nginx -y",
      "sudo chkconfig nginx on",
      "sudo service nginx start",
    ]
  }

  tags = {
    Name        = "${var.project_tag}-${var.environment_tag}-template-${var.region}"
    Environment = "${var.environment_tag}"
    Project     = "${var.project_tag}"
  }
}

# S3 Bucket config#
resource "aws_iam_user" "write_user" {
  name          = "${var.environment_tag}-s3-write-user"
  force_destroy = true
}

resource "aws_iam_access_key" "write_user" {
  user = "${aws_iam_user.write_user.name}"
}

resource "aws_iam_user_policy" "write_user_pol" {
  name = "write"
  user = "${aws_iam_user.write_user.name}"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::${var.environment_tag}-${var.bucket_name}",
                "arn:aws:s3:::${var.environment_tag}-${var.bucket_name}/*"
            ]
        }
   ]
}
EOF
}

resource "aws_s3_bucket" "web_bucket" {
  bucket        = "${var.environment_tag}-${var.bucket_name}"
  acl           = "private"
  force_destroy = true

  policy = <<EOF
{
    "Version": "2008-10-17",
    "Statement": [
        {
            "Sid": "PublicReadForGetBucketObjects",
            "Effect": "Allow",
            "Principal": {
                "AWS": "*"
            },
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::${var.environment_tag}-${var.bucket_name}/*"
        },
        {
            "Sid": "",
            "Effect": "Allow",
            "Principal": {
                "AWS": "${aws_iam_user.write_user.arn}"
            },
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::${var.environment_tag}-${var.bucket_name}",
                "arn:aws:s3:::${var.environment_tag}-${var.bucket_name}/*"
            ]
        },
        {
            "Sid": "",
            "Effect": "Allow",
            "Principal": {
                "AWS": "${data.aws_elb_service_account.lb-service-account.arn}"
            },
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::${var.environment_tag}-${var.bucket_name}/${var.lb_logs_prefix}",
                "arn:aws:s3:::${var.environment_tag}-${var.bucket_name}/${var.lb_logs_prefix}/*"
            ]
        }        
    ]
}
EOF

  tags = {
    Name        = "${var.environment_tag}-web_bucket"
    Environment = "${var.environment_tag}"
    Project     = "${var.project_tag}"
  }
}


# Create AMI Image from our EC2 instance 
resource "aws_ami_from_instance" "template-image" {
  name               = "template-image"
  source_instance_id = "${aws_instance.template-instance.id}"
  tags = {
    Name        = "${var.project_tag}-${var.environment_tag}-template-image"
    Environment = "${var.environment_tag}"
    Project     = "${var.project_tag}"
  }
}

###################################################################################
# Autoscaling
###################################################################################

resource "aws_launch_configuration" "launch-configuration" {
  image_id        = "${aws_ami_from_instance.template-image.id}"
  instance_type   = "${var.instance_type}"
  security_groups = [aws_security_group.instance-sg.id]
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "asg" {
  launch_configuration = aws_launch_configuration.launch-configuration.id
  vpc_zone_identifier  = "${aws_subnet.subnet.*.id}"
  target_group_arns = ["${aws_lb_target_group.lb_target_group.arn}"]
  min_size          = 2
  max_size          = 10
  tags = [
    {
      key                 = "Name"
      value               = "${var.project_tag}-${var.environment_tag}-asg"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = "${var.environment_tag}"
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = "${var.project_tag}"
      propagate_at_launch = true
    },
  ]
}

###################################################################################
# OUTPUT
###################################################################################

output "aws_lb_public_dns" {
  value = "${aws_lb.web-lb.dns_name}"
}


