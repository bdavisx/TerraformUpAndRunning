provider "aws" {
  region = "us-east-1"
}

resource "aws_ecs_task_definition" "bd-ecs-task-definition-test" {
  family                = "service"
  container_definitions = "${file("./task-definition.json")}"

  placement_constraints {
    type       = "memberOf"
    expression = "attribute:ecs.availability-zone in [us-east-1a, us-east-1b]"
  }
}

resource "aws_ecs_cluster" "bd-ecs-cluster-test" {
  name = "bd-ecs-cluster-test"
}

//resource "aws_ecs_service" "bd-ecs-service-test" {
//  name = "bd-ecs-service-test"
//  cluster = "${aws_ecs_cluster.bd-ecs-cluster-test.id}"
//  task_definition = "${aws_ecs_task_definition.bd-ecs-task-definition-test.arn}"
//
//  desired_count = 2
//
//  placement_constraints {
//    type       = "memberOf"
//    expression = "attribute:ecs.availability-zone in [us-east-1a, us-east-1b]"
//  }
//}

resource "aws_launch_configuration" "bd-ecs-launch-configuration" {
  name_prefix = "bd-ecs-cluster"
  image_id = "ami-07eb698ce660402d2"
  instance_type = "t2.micro"

//  associate_public_ip_address = "true"

//  depends_on = [
//    "null_resource.iam_wait"
//  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "bd-ecs-autoscaling-group" {
  name                 = "bd-ecs-autoscaling-group"
  max_size             = "3"
  min_size             = "2"
  force_delete         = true
  launch_configuration = "${aws_launch_configuration.bd-ecs-launch-configuration.id}"

  availability_zones =  ["us-east-1a", "us-east-1b"]
}
