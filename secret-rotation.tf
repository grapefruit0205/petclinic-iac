# DB 비밀번호 자동 교체 + 교체 뒤 WAS Tomcat 재시작 — 2026-09-28 19:29~21:43 KST semin 콘솔 작업.
#
# ① 교체(rotation) — Secrets Manager 콘솔의 "호스팅 교체"가 CloudFormation 스택으로 만든다. 그래서 Terraform 으로 관리하지 않는다:
#    스택 SecretsManagerRDSMySQLRotationSingleUsere9cdb245-07f4-40c4-8d3b-fbbabd345ede (+ 중첩 스택 …HostedRotationLambda-4F6P61T2SXMF)
#      - 교체 일정 RDS-Secret-key: cron(0 0 ? * 1#2,1#4 *) = 둘째 · 넷째 일요일 09:00 KST, 첫 교체 2026-09-28 21:47 KST
#      - Lambda SecretsManagerlambda-rds-password-change (python3.12, 단일 사용자 방식, 32자) — VPC 안(WAS 서브넷 2a·2c),
#        보안 그룹 lambda-secret-rotation-sg(security.tf, 이건 콘솔에서 따로 만들어 코드로 관리)
#      - 역할 SecretsManagerRDSMySQLRot-SecretsManagerRDSMySQLRot-mmqoRHQQo4p3 · 호출 권한
#    aws_secretsmanager_secret.rds_app(database.tf)에 교체 설정을 코드로 붙이지 않는 것도 같은 이유(스택의 RotationSchedule 이 가진다).
#
# ② 재시작 — 교체로 AWSCURRENT 가 바뀌면 EventBridge 규칙이 Lambda PetclinicTomcatSecretRefresh 를 부르고,
#    Lambda 가 was-asg 의 정상 WAS 를 한 대씩 SSM 명령(PetclinicRestartAfterSecretRotation)으로 Tomcat 재시작 → 주 DB · 복제본 접속 확인
#    → ASG 에서 다시 Healthy 가 될 때까지 기다린 뒤 다음 대. 정상 WAS 가 2대 미만이거나 하나라도 비정상이면 시작하지 않는다.
#    코드는 콘솔에 올라간 그대로 lambda/ · ssm/ 에 두었다(zip 은 배포본 그대로라 해시가 실물과 같다).

# --- ① 교체 Lambda 의 로그 그룹 (Lambda 가 처음 돌 때 만듦, 스택 밖) ---
resource "aws_cloudwatch_log_group" "lambda_rds_password_change" {
  name              = "/aws/lambda/SecretsManagerlambda-rds-password-change"
  retention_in_days = 0
  log_group_class   = "STANDARD"
}

# 2026-09-28 19:29 KST 콘솔 생성 — 교체 Lambda 를 직접 만들려던 첫 시도로 보인다. 어디에도 붙어 있지 않다(마지막 사용 없음).
# 실제 교체 Lambda 는 위 스택의 역할을 쓴다. 지울지는 담당(semin) 결정.
resource "aws_iam_role" "rds_pwch" {
  name        = "rds-pwch-role"
  description = "RDS Password Change Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "rds_pwch" {
  name = "rds-pwch-rolePolicy"
  role = aws_iam_role.rds_pwch.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RotateOnlyThisSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage",
        ]
        Resource = aws_secretsmanager_secret.rds_app.arn
      },
      {
        Sid      = "GeneratePassword"
        Effect   = "Allow"
        Action   = "secretsmanager:GetRandomPassword"
        Resource = "*"
      },
    ]
  })
}

# --- ② 교체 뒤 WAS 재시작 ---
resource "aws_ssm_document" "petclinic_restart_after_secret_rotation" {
  name            = "PetclinicRestartAfterSecretRotation"
  document_type   = "Command"
  document_format = "JSON"
  target_type     = "/AWS::EC2::Instance"
  content         = file("${path.module}/ssm/petclinic-restart-after-secret-rotation.json")

  tags = {
    Purpose = "PetclinicSecretRefresh"
  }
}

resource "aws_iam_role" "secret_refresh_lambda" {
  name        = "PetclinicSecretRefreshLambdaRole"
  description = "Restart Tomcat sequentially after the Petclinic RDS secret changes"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "secret_refresh_lambda_basic" {
  role       = aws_iam_role.secret_refresh_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# 시크릿은 메타데이터만(값은 못 읽음), SSM 명령은 이 문서 하나 · was-asg 의 WAS 에만.
resource "aws_iam_role_policy" "secret_refresh_lambda" {
  name = "PetclinicWASRefresh"
  role = aws_iam_role.secret_refresh_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DescribeOnlyPetclinicCredentialMetadata"
        Effect   = "Allow"
        Action   = "secretsmanager:DescribeSecret"
        Resource = aws_secretsmanager_secret.rds_app.arn
      },
      {
        Sid      = "FindInstancesInTheWASGroup"
        Effect   = "Allow"
        Action   = "autoscaling:DescribeAutoScalingGroups"
        Resource = "*"
      },
      {
        Sid      = "SendOnlyTheTomcatRestartDocument"
        Effect   = "Allow"
        Action   = "ssm:SendCommand"
        Resource = aws_ssm_document.petclinic_restart_after_secret_rotation.arn
      },
      {
        Sid      = "SendRestartOnlyToWASASGInstances"
        Effect   = "Allow"
        Action   = "ssm:SendCommand"
        Resource = "arn:aws:ec2:ap-northeast-2:723165663216:instance/*"
        Condition = {
          StringEquals = {
            "ssm:resourceTag/aws:autoscaling:groupName" = "was-asg"
            "ssm:resourceTag/Name"                      = "ASG-Was"
          }
        }
      },
      {
        Sid      = "ReadRestartCommandStatus"
        Effect   = "Allow"
        Action   = "ssm:GetCommandInvocation"
        Resource = "*"
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "secret_refresh_lambda" {
  name              = "/aws/lambda/PetclinicTomcatSecretRefresh"
  retention_in_days = 30
  log_group_class   = "STANDARD"
}

# 15분(최대) — WAS 1대당 SSM 명령 최대 5분 + Healthy 대기 1분 반.
resource "aws_lambda_function" "secret_refresh" {
  function_name    = "PetclinicTomcatSecretRefresh"
  description      = "Sequentially restart healthy WAS instances when the Petclinic AWSCURRENT database secret changes"
  role             = aws_iam_role.secret_refresh_lambda.arn
  runtime          = "python3.12"
  handler          = "lambda_function.handler"
  filename         = "${path.module}/lambda/petclinic-tomcat-secret-refresh.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda/petclinic-tomcat-secret-refresh.zip")
  timeout          = 900
  memory_size      = 256

  # 동시 실행 1 — 교체 이벤트가 겹쳐도 재시작이 두 갈래로 돌지 않게(WAS 가 한꺼번에 내려가지 않게).
  reserved_concurrent_executions = 1

  environment {
    variables = {
      SECRET_ARN    = aws_secretsmanager_secret.rds_app.arn
      SECRET_NAME   = aws_secretsmanager_secret.rds_app.name
      ASG_NAME      = aws_autoscaling_group.was.name
      SSM_DOCUMENT  = aws_ssm_document.petclinic_restart_after_secret_rotation.name
      MIN_INSTANCES = "2"
    }
  }

  # AWS 는 올린 zip 의 경로 · 해시 입력값을 돌려주지 않아 import 뒤 plan 에 "변경"으로 잡힌다(zip 해시는 실물 CodeSha256 과 같음).
  # 코드를 바꿔 Terraform 으로 올리려면 zip 을 새로 만들고 이 ignore 를 뺀 뒤 plan.
  lifecycle {
    ignore_changes = [filename, source_code_hash, publish]
  }
}

resource "aws_cloudwatch_event_rule" "secret_current_restart_was" {
  name        = "petclinic-secret-current-restart-was"
  description = "Restart WAS when RDS-Secret-key AWSCURRENT changes"

  # 콘솔에 저장된 글자 그대로(줄바꿈 · 공백 포함) — jsonencode 로 바꾸면 내용이 같아도 plan 에 차이로 잡힌다.
  event_pattern = <<-EOT
    {
      "source": ["aws.secretsmanager"],
      "detail-type": ["Secret Label Updated"],
      "detail": {
        "name": ["RDS-Secret-key"],
        "labelUpdated": ["AWSCURRENT"]
      }
    }
  EOT
}

resource "aws_cloudwatch_event_target" "secret_current_restart_was" {
  rule      = aws_cloudwatch_event_rule.secret_current_restart_was.name
  target_id = "restart-was"
  arn       = aws_lambda_function.secret_refresh.arn
}

resource "aws_lambda_permission" "secret_refresh_events" {
  statement_id  = "AllowSecretsRotationEvent"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.secret_refresh.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.secret_current_restart_was.arn
}
