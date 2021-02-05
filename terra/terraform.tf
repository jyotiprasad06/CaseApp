provider "aws" {
  region  = var.region
  version = ">=3.7,<=3.11"
}

variable "region" {
  default = "ap-south-1"
}
variable "key_name" {
  default = "SonarQube"
}
variable "security_id" {
  default = "CaseApp"
}
variable "pvt_key_name" {
  default = "/home/silent/.ssh/SonarQube.pem"
}
variable "instances" {
  default = 2
}

data "aws_availability_zones" "zone_east" {}

data "aws_ami" "ubuntu_ami" {
  most_recent = "true"
  owners      = ["099720109477"]
  
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04*"]
  }

}

data "aws_vpc" "selected" {
  default = true
}

data "aws_subnet_ids" "subnets" {
  vpc_id = data.aws_vpc.selected.id
}

data "aws_security_groups" "ELB" {
    filter {
        name = "group-name"
        values = ["ELB"]
    }
}

resource "aws_instance" "backend" {
  ami               = data.aws_ami.ubuntu_ami.id
  instance_type     = "t2.micro"
  key_name    = var.key_name
  vpc_security_group_ids = [var.security_id]
  availability_zone = data.aws_availability_zones.zone_east.names[count.index]
  count             = var.instances
  lifecycle {
    prevent_destroy = false
  }
  tags = {
    Name = "Backend-App"
  }
  connection { 
    type = "ssh"
    user = "ubuntu"
    private_key = file(var.pvt_key_name)
    host  = self.public_ip 
  }

  provisioner "remote-exec" {
    inline = [
      "sleep 20",
      "python3 --version",
      "sudo apt-get update",
      "sudo apt-get install python3-wheel build-essential python3-dev python3-pip -y",
      "sudo ufw allow 9090",
      "export PATH=$PATH:/home/ubuntu/.local/bin",
      "git clone https://github.com/SilentEntity/CaseApp.git",
      "cd CaseApp",
      "pip3 install -r requirements.txt",
      "sudo cp terra/AWS_WSGI.service /etc/systemd/system/",
      "sudo systemctl daemon-reload",
      "sudo systemctl start AWS_WSGI.service",
      "sudo systemctl enable AWS_WSGI.service"
    ]
  }
}

resource "aws_lb" "ELB_CaseApp" {
  name               = "ELBCaseApp"
  load_balancer_type = "application"
  internal           = false
  security_groups    = data.aws_security_groups.ELB.ids
  subnets            = data.aws_subnet_ids.subnets.ids
  tags = {
    Name = "ELBCaseApp"
  }
  depends_on = [aws_instance.backend]
}

resource "aws_lb_target_group" "backbendCase-lb-tg" {
  name     = "backbendCase-lb-tg"
  port     = 9090
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.selected.id
  depends_on = [aws_lb.ELB_CaseApp]
}

resource "aws_lb_target_group_attachment" "backend_attachment" {

  count = length(aws_instance.backend)
  target_group_arn = aws_lb_target_group.backbendCase-lb-tg.arn
  target_id        = aws_instance.backend[count.index].id
  depends_on = [aws_lb_target_group.backbendCase-lb-tg]
}
resource "aws_lb_listener" "LB_listener" {
  load_balancer_arn = aws_lb.ELB_CaseApp.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backbendCase-lb-tg.arn
  }
  depends_on = [aws_lb_target_group_attachment.backend_attachment]
}

output "backend_public_ips" {
  value = aws_instance.backend.*.public_ip
}
output "backend_public_dns" {
  value = aws_instance.backend.*.public_dns
}
output "ELB_DNS" {
  value = aws_lb.ELB_CaseApp
}