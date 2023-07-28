terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  # チュートリアルはus-west-2だったが東京にした
  region = "ap-northeast-1"
}

resource "aws_instance" "app_server" {
  # チュートリアルのamiはnot foundだったので無料枠の物を調べて指定
  ami = "ami-0947c48ae0aaf6781"
  # アップデート用
  # ami           = "ami-09bad682e5ae72267"
  instance_type = "t2.micro"

  tags = {
    # Name = "TfTutorialInstance"
    Name = var.instance_name
  }
}