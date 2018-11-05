# Update your region
provider "aws" {
  region = "us-east-1"
}

resource "aws_ecs_cluster" "ecs_cluster" {
  name = "test-cluster"
}

#
# ECS Instance Section
#

#
# It is assumed you already have a VPC setup, you should replace the values called out
#

# Update your vpc_id
resource "aws_security_group" "internal_only_docker" {
  name = "internal_only_docker"
  description = "Allow internal traffic to docker servers"
  vpc_id = "vpc-f158818b"

  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    self = true
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "internal_only_docker"
  }
}

resource "aws_iam_instance_profile" "ecsInstanceProfile" {
  name = "${aws_iam_role.ecsInstanceRole.name}"
  role = "${aws_iam_role.ecsInstanceRole.name}"
}

resource "aws_iam_role" "ecsInstanceRole" {
  name = "ecsInstanceRole"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ecsInstanceRole" {
  role = "${aws_iam_role.ecsInstanceRole.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}


data "template_file" "cluster_ecs_config_data" {
  template = "${file("cluster_ecs_config_data.sh")}"
  vars {
    ecs_cluster = "${aws_ecs_cluster.ecs_cluster.name}"
  }
}

# Grab AMI from http://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-optimized_AMI.html
# Update our key_name
resource "aws_launch_configuration" "docker_launch_cfg" {
  image_id = "ami-07eb698ce660402d2"
  instance_type = "t2.small"
//  key_name = "${var.key_name}"
  security_groups = ["${aws_security_group.internal_only_docker.id}"]
  associate_public_ip_address = true
  enable_monitoring = false
  ebs_optimized = "false"
  user_data = "${data.template_file.cluster_ecs_config_data.rendered}"

  iam_instance_profile = "${aws_iam_role.ecsInstanceRole.name}"

  root_block_device {
    volume_size = "20"
    volume_type = "gp2"
    delete_on_termination = true
  }
}

# Update subnets
resource "aws_autoscaling_group" "docker_asg" {
  name = "docker-test-asg"

  min_size = "1"
  max_size = "1"

  vpc_zone_identifier = ["subnet-23dc0c1d", "subnet-f236bb95"]

  health_check_grace_period = 300
  health_check_type = "EC2"
  termination_policies = ["OldestInstance"]

  launch_configuration = "${aws_launch_configuration.docker_launch_cfg.id}"
}

#
# ECS Service Section
#

# Update your vpc_id
resource "aws_security_group" "external_web" {
  name = "external_web"
  description = "Allow external traffic to port 80 & 443"
  vpc_id = "vpc-f158818b"

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "external_web"
  }
}

resource "aws_iam_role" "ecsServiceRole" {
  name = "ecsServiceRole"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ecs.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ecsServiceRole" {
  role = "${aws_iam_role.ecsServiceRole.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole"
}

data "template_file" "web_task_definition" {
  template = "${file("web.json")}"
}

resource "aws_ecs_task_definition" "web" {
  family = "web"
  container_definitions = "${data.template_file.web_task_definition.rendered}"
}

resource "aws_ecs_service" "web" {
  name = "web"
  cluster = "${aws_ecs_cluster.ecs_cluster.id}"
  task_definition = "${aws_ecs_task_definition.web.arn}"
  desired_count = "1"
  iam_role = "${aws_iam_role.ecsServiceRole.name}"

  load_balancer {
    elb_name = "${aws_elb.web.id}"
    container_name = "customContainer"
    container_port = 8000
  }
}

# Update subnets
resource "aws_elb" "web" {
  name = "web"
  subnets = ["subnet-23dc0c1d", "subnet-f236bb95"]
  security_groups = ["${aws_security_group.internal_only_docker.id}", "${aws_security_group.external_web.id}"]

  listener {
    instance_port = 80
    instance_protocol = "http"
    lb_port = 80
    lb_protocol = "http"
  }

  # Exercise to reader to setup 443

  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 5
    target = "HTTP:80/"
    interval = 30
  }

  cross_zone_load_balancing = true
  idle_timeout = 60
}
