# Connect to this host once everything is working
output "web_elb" {
  value = "${aws_elb.web.dns_name}"
}

#
# There may be some delays once terraform apply completes as the ECS service waits for
# the docker instance to be up and running to start the container.
#
