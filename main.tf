
module "describe_regions_for_ec2" {
  source     = "./iam_role"
  name       = "describe-regions-for-ec2"
  identifier = "ec2.amazonaws.com"
  policy     = module.describe_regions_for_ec2.allow_describe_regions_policy
}

resource "aws_s3_bucket" "private" {
  bucket = "private-tf-practice-bucket-yus"

  versioning {
    enabled = true
  }
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

# ブロックパブリックアクセス
# 予期しないオブジェクトの公開を抑止できる。特に理由がなければ全ての設定を有効にする
resource "aws_s3_bucket_public_access_block" "private" {
  bucket                  = aws_s3_bucket.private.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# パブリックバケット
resource "aws_s3_bucket" "public" {
  bucket = "public-tf-practice-bucket-yus"

  cors_rule {
    allowed_origins = ["https://example.com"]
    allowed_methods = ["GET"]
    allowed_headers = ["*"]
    max_age_seconds = 3000
  }
}

# ログローテーションバケット（AWS各種サービスがログを保存するバケット）
# 八章でALB使う時に使用予定
resource "aws_s3_bucket" "alb_log" {
  bucket = "alb-log-tf-practice-yus"

  lifecycle_rule {
    enabled = true

    expiration {
      days = "180"
    }
  }
}

resource "aws_s3_bucket_policy" "alb_log" {
  bucket = aws_s3_bucket.alb_log.id
  policy = data.aws_iam_policy_document.alb_log.json
}

data "aws_iam_policy_document" "alb_log" {
  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${aws_s3_bucket.alb_log.id}/*"]

    principals {
      type        = "AWS"
      identifiers = ["582318560864"]
    }
  }
}

resource "aws_vpc" "example" {
  cidr_block = "10.0.0.0/16"

  # DNSサーバーによる名前解決を有効にする
  enable_dns_support = true

  # VPC内のリソースにパブリックDNSホスト名を自動で割り当てる
  enable_dns_hostnames = true

  tags = {
    Name = "tf-vpc"
  }
}

# パブリックサブネット
resource "aws_subnet" "public" {
  vpc_id = aws_vpc.example.id
  # CIDRブロックはとくにこだわりがなければVPCでは/16、サブネットでは/24にするとわかりやすい
  cidr_block = "10.0.0.0/24"
  # そのサブネットで起動したインスタンスにパブリックIPアドレスを自動的に割り当てる
  map_public_ip_on_launch = true
  availability_zone       = "ap-northeast-1a"

  tags = {
    Name = "tf-public-subnet"
  }
}

# igw
# VPCとインターネット間で通信できるようにする
resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.example.id

  tags = {
    Name = "tf-igw"
  }
}

# igwだけではネットに接続できない。ネットワークにデータを流すためルーティング情報を管理するルートテーブルを用意
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.example.id

  tags = {
    Name = "tf-route-table"
  }
}
