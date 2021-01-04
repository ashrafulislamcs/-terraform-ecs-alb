provider "aws" {
  region = var.region
}

data "aws_iam_role" "ecr" {
  name = "AWSServiceRoleForECRReplication"
}

module "label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=master"
  namespace  = "everlook"
  stage      = "dev"
  name       = "node-ecs"
  attributes = ["public"]
  delimiter  = "-"
}

module "ecr" {
  source                 = "git::https://github.com/cloudposse/terraform-aws-ecr.git?ref=master"
  namespace              = module.label.namespace
  stage                  = module.label.stage
  name                   = module.label.name
  principals_full_access = [data.aws_iam_role.ecr.arn]
}

data "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
}

resource "aws_ecs_task_definition" "node" {
  family                   = "node-ecs"
  network_mode             = var.network_mode
  requires_compatibilities = [var.ecs_launch_type]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = data.aws_iam_role.ecs_task_execution_role.arn

  container_definitions    = <<DEFINITION
[
  {
    "cpu": ${var.task_cpu},
    "environment": [{
      "name": "DEBUG",
      "value": "api*"
    }],
    "essential": true,
    "image": "${module.ecr.repository_url}:latest",
    "memory": ${var.task_memory},
    "name": "node-ecs",
    "portMappings": [
      {
        "containerPort": 8080,
        "hostPort": 8080
      }
    ]
  }
]
DEFINITION
}

resource "aws_ecs_cluster" "default" {
  name = module.label.id
}

resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
  }
}

resource "aws_default_subnet" "az1" {
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "Default subnet for us-east-1a"
  }
}

resource "aws_default_subnet" "az2" {
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "Default subnet for us-east-1b"
  }
}

resource "aws_default_security_group" "lb_sg" {
  vpc_id = aws_default_vpc.default.id

  ingress {
    protocol  = -1
    self      = true
    from_port = 0
    to_port   = 0
  }
}

resource "aws_lb" "ecs" {
  name               = "ecs-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_default_security_group.lb_sg.id]
  subnets            = [aws_default_subnet.az1.id, aws_default_subnet.az2.id]
}

resource "aws_lb_target_group" "ecs" {
  name        = "node-ecs-lb-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_default_vpc.default.id
  target_type = "ip"

  depends_on = [aws_lb.ecs]
}

resource "aws_lb_listener" "default" {
  load_balancer_arn = aws_lb.ecs.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs.arn
  }
}

resource "aws_ecs_service" "node" {
  name                               = module.label.name
  cluster                            = aws_ecs_cluster.default.id
  task_definition                    = aws_ecs_task_definition.node.arn
  deployment_maximum_percent         = var.deployment_maximum_percent
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent 
  desired_count                      = 2
  launch_type                        = var.ecs_launch_type
  depends_on                         = [aws_lb_target_group.ecs]

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs.arn
    container_name   = "node-ecs"
    container_port   = 8080
  }

  network_configuration {
    subnets = [aws_default_subnet.az1.id]
  }
}
