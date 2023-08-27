
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

  # 強制削除（一時的に有効化）
  force_destroy = true
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
    Name = "tf_vpc"
  }
}

# パブリックサブネット
resource "aws_subnet" "public_0" {
  vpc_id = aws_vpc.example.id
  # CIDRブロックはとくにこだわりがなければVPCでは/16、サブネットでは/24にするとわかりやすい
  cidr_block = "10.0.1.0/24"
  # そのサブネットで起動したインスタンスにパブリックIPアドレスを自動的に割り当てる
  map_public_ip_on_launch = true
  availability_zone       = "ap-northeast-1a"

  tags = {
    Name = "tf_public_subnet_0"
  }
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-northeast-1c"

  tags = {
    Name = "tf_public_subnet_1"
  }
}

# igw
# VPCとインターネット間で通信できるようにする
resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.example.id

  tags = {
    Name = "tf_igw"
  }
}

# igwだけではネットに接続できない。ネットワークにデータを流すためルーティング情報を管理するルートテーブルを用意
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.example.id

  tags = {
    Name = "tf_route_table"
  }
}

# ルート
resource "aws_route" "public" {
  route_table_id         = aws_route_table.public.id
  gateway_id             = aws_internet_gateway.example.id
  destination_cidr_block = "0.0.0.0/0"
}

# ルートテーブルの関連付け
resource "aws_route_table_association" "public_0" {
  subnet_id      = aws_subnet.public_0.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

# プライベートネットワーク
# DBサーバーのようにネットからアクセスしないものを置く

# システムをセキュアにするため、パブリックネットワークには最小限のリソースのみ配置し、それ以外はプライベートネットワークにおくのが定石

# プライベートサブネット
resource "aws_subnet" "private_0" {
  vpc_id            = aws_vpc.example.id
  cidr_block        = "10.0.65.0/24"
  availability_zone = "ap-northeast-1a"
  # パブリックIPアドレスは不要
  map_public_ip_on_launch = false

  tags = {
    Name = "tf_private_subnet_0"
  }
}

resource "aws_subnet" "private_1" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.66.0/24"
  availability_zone       = "ap-northeast-1c"
  map_public_ip_on_launch = false

  tags = {
    Name = "tf_private_subnet_1"
  }
}

# ルートテーブルと関連付け
resource "aws_route_table" "private_0" {
  vpc_id = aws_vpc.example.id
}

resource "aws_route_table" "private_1" {
  vpc_id = aws_vpc.example.id
}

# ルート
# プライベートネットワークからネットへ通信するためにルートを定義
resource "aws_route" "private_0" {
  route_table_id         = aws_route_table.private_0.id
  nat_gateway_id         = aws_nat_gateway.nat_gateway_0.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route" "private_1" {
  route_table_id         = aws_route_table.private_1.id
  nat_gateway_id         = aws_nat_gateway.nat_gateway_1.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route_table_association" "private_0" {
  subnet_id      = aws_subnet.private_0.id
  route_table_id = aws_route_table.private_0.id
}

resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private_1.id
}

# NATサーバーを導入するとプライベートネットワークからインターネットへアクセス可能になる
# NATゲートウェイにはEIPが必要
resource "aws_eip" "nat_gateway_0" {
  vpc        = true
  depends_on = [aws_internet_gateway.example]

  tags = {
    Name = "tf_eip_0"
  }
}

resource "aws_eip" "nat_gateway_1" {
  vpc        = true
  depends_on = [aws_internet_gateway.example]

  tags = {
    Name = "tf_eip_1"
  }
}

# NATゲートウェイ
resource "aws_nat_gateway" "nat_gateway_0" {
  allocation_id = aws_eip.nat_gateway_0.id
  subnet_id     = aws_subnet.public_0.id
  depends_on    = [aws_internet_gateway.example]

  tags = {
    Name = "tf_nat_gateway_0"
  }
}

resource "aws_nat_gateway" "nat_gateway_1" {
  allocation_id = aws_eip.nat_gateway_1.id
  subnet_id     = aws_subnet.public_1.id
  depends_on    = [aws_internet_gateway.example]

  tags = {
    Name = "tf_nat_gateway_1"
  }
}

module "example_sg" {
  source      = "./security_group"
  name        = "module-sg"
  vpc_id      = aws_vpc.example.id
  port        = 80
  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_lb" "example" {
  name               = "example"
  load_balancer_type = "application"
  internal           = false
  idle_timeout       = 60
  # 基本はtrueだが、削除したい時だけfalseにしてapplyしてからdestroyする
  # enable_deletion_protection = true
  # 基本はtrueだが一時的にfalseにしてる
  enable_deletion_protection = false

  subnets = [
    aws_subnet.public_0.id,
    aws_subnet.public_1.id,
  ]

  access_logs {
    bucket  = aws_s3_bucket.alb_log.id
    enabled = true
  }

  security_groups = [
    module.http_sg.security_group_id,
    module.https_sg.security_group_id,
    module.http_redirect_sg.security_group_id,
  ]
}

output "alb_dns_name" {
  value = aws_lb.example.dns_name
}

module "http_sg" {
  source      = "./security_group"
  name        = "http-sg"
  vpc_id      = aws_vpc.example.id
  port        = 80
  cidr_blocks = ["0.0.0.0/0"]
}

module "https_sg" {
  source      = "./security_group"
  name        = "https-sg"
  vpc_id      = aws_vpc.example.id
  port        = 443
  cidr_blocks = ["0.0.0.0/0"]
}

module "http_redirect_sg" {
  source      = "./security_group"
  name        = "http-redirect-sg"
  vpc_id      = aws_vpc.example.id
  port        = 8080
  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "これは「HTTP」です"
      status_code  = "200"
    }
  }
}

# ホストゾーン
# DNSレコードを束ねるリソース
# Route53でドメイン登録した場合は自動的に作成される
# そのホストゾーンは以下で参照する
data "aws_route53_zone" "example" {
  name = "goal-app.net"
}

# ホストゾーンを新規に作成
resource "aws_route53_zone" "test_example" {
  name = "test.goal-app.net"
}

# DNSレコードの定義
# これで、設定したドメインでALBにアクセスできるようになる
resource "aws_route53_record" "example" {
  zone_id = data.aws_route53_zone.example.zone_id
  name    = data.aws_route53_zone.example.name
  type    = "A"

  alias {
    name                   = aws_lb.example.dns_name
    zone_id                = aws_lb.example.zone_id
    evaluate_target_health = true
  }
}

output "domain_name" {
  value = aws_route53_record.example.name
}

# SSL証明書の作成
resource "aws_acm_certificate" "example" {
  domain_name = aws_route53_record.example.name

  # ドメイン名を追加したい場合、以下に追加する。例えば["test.example.com"]
  subject_alternative_names = []

  # ドメインの所有権の検証方法を指定
  # DNS検証かメール検証を選択できる
  # SSL証明書を自動更新したい場合、DNS検証を選択
  validation_method = "DNS"

  lifecycle {
    # 新しい証明書を作ってから古いものと差し替える
    # これによって証明書の再作成時の影響を小さくできる
    create_before_destroy = true
  }
}

# SSL証明書の検証
# DNS検証用のDNSレコードを追加
resource "aws_route53_record" "example_certificate" {
  for_each = {
    for dvo in aws_acm_certificate.example.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  zone_id = data.aws_route53_zone.example.id
  ttl     = 60
}

resource "aws_acm_certificate_validation" "example" {
  certificate_arn         = aws_acm_certificate.example.arn
  validation_record_fqdns = [for record in aws_route53_record.example_certificate : record.fqdn]
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.example.arn
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.example.arn
  ssl_policy        = "ELBSecurityPolicy-2016-08"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "これはHTTPSですよ"
      status_code  = "200"
    }
  }
}

resource "aws_lb_listener" "redirect_http_to_https" {
  load_balancer_arn = aws_lb.example.arn
  port              = "8080"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# ターゲットグループ
# ALBがリクエストをフォワードする対象が「ターゲットグループ」
resource "aws_lb_target_group" "example" {
  name                 = "example"
  target_type          = "ip"
  vpc_id               = aws_vpc.example.id
  port                 = 80
  protocol             = "HTTP"
  deregistration_delay = 300

  health_check {
    path = "/"
    # 正常判定を行うまでのヘルスチェック実行回数
    healthy_threshold = 5
    # 異常判定を行うまでのヘルスチェック実行回数
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    # 正常判定を行うために使用するHTTPステータスコード
    matcher = 200
    # ヘルスチェックで使用するポート
    port     = "traffic-port"
    protocol = "HTTP"
  }

  depends_on = [aws_lb.example]
}

# リスナールール
# ターゲットグループにリクエストをフォワードするルール
resource "aws_lb_listener_rule" "example" {
  listener_arn = aws_lb_listener.https.arn
  # 優先順位を指定。数字が小さいほど優先度が高い
  priority = 100

  action {
    type = "forward"
    # フォワード先のtg
    target_group_arn = aws_lb_target_group.example.arn
  }
  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}

# # クラスタ: Dockerコンテナを実行するサーバーを束ねるリソース
resource "aws_ecs_cluster" "example" {
  name = "example"
}

# ECSサービスは起動するタスクの数を定義でき、指定した数のタスクを維持する
# 何らかの理由でタスクが終了しても自動で新しいタスクを起動する
resource "aws_ecs_service" "example" {
  name            = "example"
  cluster         = aws_ecs_cluster.example.arn
  task_definition = aws_ecs_task_definition.example.arn

  # ECSサービスが維持するタスク数
  # ここで1を指定すると、コンテナが以上終了するとECSサービスがタスクを再起動するまでアクセスできなくなる。なので2以上を指定
  desired_count = 2

  launch_type      = "FARGATE"
  platform_version = "1.3.0"

  # タスク起動時のヘルスチェック猶予期間を設定
  # タスク起動に時間がかかる場合、十分な時間を用意しないとヘルスチェックに引っかかり、タスクの起動と終了が無限に続いてしまう。なので0以上を指定する
  health_check_grace_period_seconds = 60

  network_configuration {
    assign_public_ip = false
    security_groups  = [module.nginx_sg.security_group_id]

    subnets = [
      aws_subnet.private_0.id,
      aws_subnet.private_1.id,
    ]
  }

  load_balancer {
    # TODO:これはroute53でドメインとるのとその後の八章やる必要ありそうなのでそのあとやる
    target_group_arn = aws_lb_target_group.example.arn
    container_name   = "example"
    container_port   = 80
  }

  lifecycle {
    ignore_changes = [task_definition]
  }
}

module "nginx_sg" {
  source      = "./security_group"
  name        = "nginx-sg"
  vpc_id      = aws_vpc.example.id
  port        = 80
  cidr_blocks = [aws_vpc.example.cidr_block]
}

# cloudwatch ログ
# Fargateではホストサーバーにログインできず、コンテナのログを直接確認できない。なのでログで確認できるようにする
resource "aws_cloudwatch_log_group" "for_ecs" {
  name              = "/ecs/example"
  retention_in_days = 180
}

# ECSタスク実行IAMロールを作成
# IAMポリシーデータソース
data "aws_iam_policy" "ecs_task_execution_role_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ポリシードキュメント
data "aws_iam_policy_document" "ecs_task_execution" {
  # 既存のポリシー（AmazonECSTaskExecutionRolePolicy）を継承
  source_policy_documents = [data.aws_iam_policy.ecs_task_execution_role_policy.policy]

  statement {
    effect    = "Allow"
    actions   = ["ssm:GetParameters", "kms:Decrypt"]
    resources = ["*"]
  }
}

# # ECSタスク実行IAMロールの定義
module "ecs_task_execution_role" {
  source     = "./iam_role"
  name       = "ecs-task-execution"
  identifier = "ecs-tasks.amazonaws.com"
  policy     = data.aws_iam_policy_document.ecs_task_execution.json
}

# タスク：コンテナの実行単位
# タスクはタスク定義で作られる
resource "aws_ecs_task_definition" "example" {
  # タスク定義名のプレフィックス
  family                   = "example"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  container_definitions    = file("./container_definitions.json")
  execution_role_arn       = module.ecs_task_execution_role.iam_role_arn
}

# バッチ用cloudwatch logs
resource "aws_cloudwatch_log_group" "for_ecs_scheduled_tasks" {
  name              = "/ecs-scheduled-tasks/example"
  retention_in_days = 180
}

# バッチ用タスク定義
resource "aws_ecs_task_definition" "example_batch" {
  family                   = "example-batch"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  container_definitions    = file("./batch_container_definitions.json")
  execution_role_arn       = module.ecs_task_execution_role.iam_role_arn
}

# cloudwatchイベントからECSを起動するためのIAMロールを作成する
module "ecs_events_role" {
  source     = "./iam_role"
  name       = "ecs-events"
  identifier = "events.amazonaws.com"
  policy     = data.aws_iam_policy.ecs_events_role_policy.policy
}

data "aws_iam_policy" "ecs_events_role_policy" {
  # このポリシーでは「タスクを実行する」権限と「タスクにIAMロールを渡す」権限を付与する
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceEventsRole"
}

# ジョブの実行スケジュールを定義する
resource "aws_cloudwatch_event_rule" "example_batch" {
  name                = "example-batch"
  description         = "実践TFで作成"
  schedule_expression = "cron(*/2 * * * ? *)"
}

# cloudwatchイベントターゲットで実行対象のジョブを定義
resource "aws_cloudwatch_event_target" "example_batch" {
  target_id = "example-batch"
  rule      = aws_cloudwatch_event_rule.example_batch.name
  role_arn  = module.ecs_events_role.iam_role_arn
  arn       = aws_ecs_cluster.example.arn

  ecs_target {
    launch_type         = "FARGATE"
    task_count          = 1
    platform_version    = "1.3.0"
    task_definition_arn = aws_ecs_task_definition.example_batch.arn

    network_configuration {
      assign_public_ip = "false"
      subnets          = [aws_subnet.private_0.id]
    }
  }
}

# カスタマーキー
resource "aws_kms_key" "example" {
  # 使用用途
  description         = "Customer Master Keyテストです!!"
  enable_key_rotation = true
  # キーを有効にするかどうか
  is_enabled = true
  # 削除待機期間
  deletion_window_in_days = 30
}

# カスタマーキーにはUUIDが割り当てられるが、わかりづらい。なのでエイリアスを設定し、用途をわかりやすくする
resource "aws_kms_alias" "exasmple" {
  name          = "alias/example"
  target_key_id = aws_kms_key.example.key_id
}

# SSMパラメータストア
# /db/usernameのキー名で「root」という値を平文で保存
resource "aws_ssm_parameter" "db_username" {
  name        = "/db/username"
  value       = "root"
  type        = "String"
  description = "DBのユーザー名です!!"
}

# ここでvalue指定したものを暗号化でもできるがセキュリティ的によくない。なのでダミー値を設定し後でAWS CLIで更新する

# 以下コマンドでAWS CLIで上書きする
# aws ssm put-parameter --name '/db/password' --type SecureString \
# --value 'ModifiedStrongPassword!' --overwrite

# batch-container-definitions.jsonでDB_PASSWORDをcw logsに出力してるけどこれ観れないように対策必要では
resource "aws_ssm_parameter" "db_password" {
  name        = "/db/raw_password"
  value       = "uninitialized"
  type        = "SecureString"
  description = "DBのパスワード!!"

  lifecycle {
    ignore_changes = [value]
  }
}

# MySQLを使用
# MySQLのmy.cnfファイルに定義するようなDBの設定を以下のDBパラメータグループに書く
resource "aws_db_parameter_group" "example" {
  name = "example"
  family = "mysql8.0"

  parameter {
    name  = "character_set_database"
    value = "utf8mb4"
  }

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }
}

# DBオプショングループ（DBエンジンにオプションを追加できる）
# 以下ではMariaDB監査プラグインを追加している
# ユーザーのログインや実行したクエリなどのアクティビティを記録できる
resource "aws_db_option_group" "example" {
  name        = "example"
  engine_name = "mysql"
  major_engine_version = "8.0"

  option {
    option_name = "MARIADB_AUDIT_PLUGIN"
  }
}

# DBを駆動させるサブネット
resource "aws_db_subnet_group" "example" {
  name = "example"
  # マルチAZの設定をするため、異なるアベイラビリティゾーンを含める
  subnet_ids = [aws_subnet.private_0.id, aws_subnet.private_1.id]
}

# DBインスタンス
resource "aws_db_instance" "example" {
  identifier = "example"

  engine = "mysql"
  engine_version = "8.0.33"

  instance_class = "db.t3.small"

  allocated_storage     = 20
  max_allocated_storage = 100
  # gp2は汎用SSD
  storage_type      = "gp2"
  storage_encrypted = true

  kms_key_id = aws_kms_key.example.arn

  username = "admin"
  password = "VeryStrongPassword!"

  multi_az = true
  # falseでVPC外からのアクセスを遮断する
  publicly_accessible = false

  # バックアップの時間
  backup_window = "09:10-09:40"
  # バックアップ期間
  backup_retention_period = 30

  maintenance_window         = "mon:10:10-mon:10:40"
  auto_minor_version_upgrade = false

  # DB削除可能にする（一時的）
  deletion_protection = false
  skip_final_snapshot = true
  # DBを削除しない時だけ以下をコメント解除する
  # deletion_protection = true
  # skip_final_snapshot = false

  port = 3306

  # 設定変更のタイミング
  # RDSでは一部の設定に再起動が伴い、予期せぬダウンタイムが起こりえる。なのでfalseにして即時反映させない
  apply_immediately = false

  vpc_security_group_ids = [module.mysql_sg.security_group_id]

  parameter_group_name = aws_db_option_group.example.name
  option_group_name    = aws_db_option_group.example.name
  db_subnet_group_name = aws_db_subnet_group.example.name

  lifecycle {
    ignore_changes = [password]
  }
}

# DBインスタンスのsgの定義
# DBはVPC内からの通信のみ許可する

# 以下コマンドでマスタマスターパスワードを変更する
# aws rds modifiy-db-instance --db-instance-identifier 'example' \
# --master-user-password 'マスターパスワード'
module "mysql_sg" {
  source      = "./security_group"
  name        = "mysql-sg"
  vpc_id      = aws_vpc.example.id
  port        = 3306
  cidr_blocks = [aws_vpc.example.cidr_block]
}

# ElastiCacheパラメータグループ
resource "aws_elasticache_parameter_group" "example" {
  name   = "example"
  family = "redis5.0"

  parameter {
    name  = "cluster-enabled"
    value = "no"
  }
}

# ElastiCacheサブネットグループ
# プライベートサブネットを指定し、異なるアベイラビリティゾーンのものを含める
resource "aws_elasticache_subnet_group" "example" {
  name       = "example"
  subnet_ids = [aws_subnet.private_0.id, aws_subnet.private_1.id]
}

# ElastiCacheレプリケーショングループ
# Redisサーバーを作成
resource "aws_elasticache_replication_group" "example" {
  replication_group_id = "example"

  # 日本語入ってたらエラーになった
  description = "Cluster Disabled"

  engine         = "redis"
  engine_version = "5.0.4"

  num_cache_clusters = 3
  node_type             = "cache.t3.medium"

  snapshot_window          = "09:10-10:10"
  snapshot_retention_limit = 7

  maintenance_window = "mon:10:40-mon:11:40"

  # フェイルオーバー；システムが停止した時に自動的に待機システムに切り替える仕組み
  automatic_failover_enabled = true

  port = 6379

  apply_immediately = false

  security_group_ids = [module.redis_sg.security_group_id]

  parameter_group_name = aws_elasticache_parameter_group.example.name
  subnet_group_name    = aws_elasticache_subnet_group.example.name
}

# ElastiCacheレプリケーショングループのsgの定義
module "redis_sg" {
  source      = "./security_group"
  name        = "redis-sg"
  vpc_id      = aws_vpc.example.id
  port        = 6379
  cidr_blocks = [aws_vpc.example.cidr_block]
}

# ECRリポジトリ
resource "aws_ecr_repository" "example" {
  name = "example"
}

# ECRライフサイクルポリシー
resource "aws_ecr_lifecycle_policy" "example" {
  repository = aws_ecr_repository.example.name

  policy = <<EOF
  {
    "rules":[
      {
        "rulePriority":1,
        "description":"keep last 30 release tagged images",
        "selection":{
          "tagStatus":"tagged",
          "tagPrefixList":["release"],
          "countType":"imageCountMoreThan",
          "countNumber":30
        },
        "action":{
          "type":"expire"
        }
      }
    ]
  }
  EOF
}