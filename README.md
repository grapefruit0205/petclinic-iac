# petclinic-iac — PetClinic 3티어 AWS 인프라 as-built

콘솔로 구축돼 돌고 있는 인프라를 **코드로 옮긴** 레포입니다. 두 층으로 되어 있습니다.

| 층 | 파일 | 역할 |
|---|---|---|
| 조회 | `data.tf` · `outputs.tf` · `variables.tf` | 실물을 읽어 출력한다. 아무것도 소유하지 않는다. |
| 소유(import) | `network.tf` · `security.tf` · `entry.tf` · `compute.tf` · `iam.tf` · `database.tf` · `storage.tf` · `edge.tf` + `import.tf` | 실물 87개에 대응하는 `resource` 블록과, 그것을 실물에 연결하는 `import` 블록 |

**2026-09-19 20:01 KST 에 import apply 를 1회 실행했습니다** — `Apply complete! Resources: 87 imported, 0 added, 0 changed, 0 destroyed.`
그 결과 로컬 `terraform.tfstate`(git 무시)에 리소스 87개가 기록돼 있고, 이 시점의 코드는 실물과 정확히 일치합니다.

**이후 운영 방침: 인프라 변경은 콘솔에서 수동으로 하고, Terraform 은 `plan` 으로 "코드 대비 콘솔이 뭐가 달라졌나" 를 보는 드리프트 리포트로만 쓴다.**

- 계정: `723165663216` · 리전: `ap-northeast-2` (서울) · 글로벌 리소스(WAF · CloudFront 인증서)는 `us-east-1`
- 조회 기준일: **2026-09-19**

## 사용법

```bash
terraform init

# `aws login` 자격증명은 provider 가 직접 못 읽는다 — 환경변수로 넘긴다
eval "$(aws configure export-credentials --profile default --format env)"

terraform plan      # "No changes" 가 정상. 콘솔에서 뭔가 바꿨으면 여기서 "~ update" 로 잡힌다 (읽기만, 실물 영향 없음)
terraform output    # data 소스 조회 결과
```

### plan 은 드리프트 리포트다 — apply 는 하지 않는다

state 가 있으므로 이제 `terraform plan` 은 **코드(2026-09-19 스냅샷) 와 콘솔의 차이**를 보여 줍니다.
콘솔을 만진 뒤 plan 을 돌리면 바뀐 속성이 `~` 로, 지운 리소스가 `+`(다시 만들려 함) 로 나옵니다. 보기만 하세요.

**apply 는 콘솔 변경을 코드 쪽으로 되돌립니다.** 콘솔 변경을 코드에도 남기고 싶다면 순서는 이렇습니다.

1. 코드를 콘솔에 맞게 고친다.
2. `terraform plan` 이 `No changes` 가 될 때까지 반복한다.
3. 그래도 apply 는 필요 없다 — plan 이 0 이면 코드와 콘솔이 이미 같다.

`terraform destroy` 는 실물을 지웁니다. RDS 만 `prevent_destroy` 로 막혀 있고 나머지는 막혀 있지 않습니다.
`import.tf` 는 이미 state 에 들어간 리소스에 대해 아무 일도 하지 않으므로 두어도 되고 지워도 됩니다.

## 코드가 소유하는 것 (import 87개)

| 계층 | 파일 | 리소스 |
|---|---|---|
| 네트워크 | `network.tf` | VPC, 서브넷 8, IGW, NAT 2 + EIP 2, 라우트 테이블 5 + 기본 테이블, 연결 8 |
| 보안 | `security.tf` | 보안 그룹 6 (규칙 인라인) |
| 진입 | `entry.tf` | ALB 2, 타깃 그룹 2, 리스너 3 (443 ACM · 80 · internal 80), ALB 인증서 |
| 컴퓨트 | `compute.tf` | 골든 AMI `web-appache`, 시작 템플릿 `web`, ASG `web-test` + CPU 60% 목표추적 정책, 단독 인스턴스 4, WAS 데이터 볼륨 + 연결 |
| IAM | `iam.tf` | 역할 4 (`mc-ec2-role` · `was-test-iam` · `rds-monitoring-role` · RDS Proxy 역할), 프로파일 2, 고객 정책 1, 정책 연결 5 |
| 데이터 | `database.tf` | RDS `database-1`, 파라미터 그룹, 서브넷 그룹, RDS Proxy + 기본 타깃 그룹 + 타깃 |
| 스토리지·로그 | `storage.tf` | S3 `mc-static-image` + 정책 · 퍼블릭 차단 · 암호화, 로그 그룹 5 |
| 엣지 | `edge.tf` | CloudFront 분포 + OAC, WAF 웹 ACL, CloudFront 인증서, Route53 존 + 레코드 3 (A · AAAA · ACM 검증) |

시작 템플릿과 `web-ami` 인스턴스의 user data 는 `userdata/` 에 스크립트 원문으로 있습니다. **바이트가 바뀌면 plan 에 변경으로 잡히니** 손대지 마세요.

### 콘솔에 있지만 코드에 없는 것

| 리소스 | 이유 |
|---|---|
| `Targetgroup-web` ← `WEB-test-a`, `tg-internal-alb` ← `WAS-test-a` 수동 타깃 등록 | `aws_lb_target_group_attachment` 가 import 미지원 |
| 키페어 `test-key` | 퍼블릭 키를 API 로 못 읽어 import 불가. 이름만 문자열로 참조 |
| VPC 엔드포인트 `vpce-0bc81ff97ecbceb74` | RDS Proxy 가 만든 AWS 관리 엔드포인트 — 사용자 리소스가 아님 |
| Public ALB 의 EIP 2개 (`52.78.70.34` · `3.38.76.227`) | ELB 가 관리 |
| RDS 관리형 시크릿 `rds!db-…` | RDS 가 소유. `aws_db_instance.main.master_user_secret` 로 참조 |
| 알람 `TargetTracking-web-test-AlarmHigh/Low` | 목표추적 정책이 소유 |
| `default` SG · 기본 NACL | VPC 기본값 (SG 는 `data.tf` 에서 조회만) |
| 고아 OAC `E32W5M7BHL5ZBD`(`oac-mylab-junseok…`), 없는 분포 `E2KEFN428TOT1G` 용 CloudFront 로그 전송 소스, EFS 자동 백업 플랜(2021), 서비스 연결 역할, `Bespin-Academy-Support_DO_NOT_DELETE` | 이 스택과 무관하거나 정리 대상 |
| S3 객체 | 코드 범위 밖 |

### 코드로 표현할 수 없어 무시하는 것 (`lifecycle.ignore_changes`)

- ASG `force_delete` · `force_delete_warm_pool` · `ignore_failed_scaling_activities` · `wait_for_capacity_timeout` — Terraform 전용 인자. import 로 state 에 들어오지 않아 변경으로 잡히기 때문에 무시한다.
- 리스너 3개의 `default_action[0].forward` — 실물의 stickiness duration 이 0 인데 provider 는 1 이상만 받는다. 단일 타깃 그룹 forward 는 `target_group_arn` 이 전부.
- RDS `manage_master_user_password` 는 코드에 **넣지 않았다** — provider 가 import 시 이 값을 읽지 않아, 넣으면 변경으로 잡힌다.

## 실물 구조 (2026-09-19 실측)

```
Route53 24petclinic.mission-critical.site (A/AAAA alias)
  → CloudFront E1F6M0QDUUT8AG (WAF: 관리형 룰 3개, 전부 Count)
      ├ 기본 동작 → Public ALB :443 (https-only, Host 헤더 전달)
      │     → Targetgroup-web :80 = ASG web-test 2대(t3.small) + WEB-test-a
      │         httpd 리버스프록시 /petclinic/ → Internal ALB :80
      │             → tg-internal-alb :8080 = WAS-test-a (t3.medium, 1대)
      │                 → RDS Proxy pet-proxy → RDS database-1 (MySQL 8.0.44, db.t3.small, Multi-AZ, 200GB)
      └ /petclinic/resources/* → S3 mc-static-image (OAC)
```

- **엣지** — CloudFront `d3q5zkso8oivib.cloudfront.net` · 상태 `Deployed` · 별칭 `24petclinic.mission-critical.site`.
  - Route53 존 `Z08667423LQZPT6BSL30W` 에 **A + AAAA alias 레코드가 있고** 공개 DNS 로 풀린다 (`https://24petclinic.mission-critical.site/petclinic/` → 200).
  - `d3q5zkso8oivib.cloudfront.net` 으로 직접 오면 **502** — Host 헤더가 ALB 인증서(`*.mission-critical.site`)와 안 맞기 때문. 별칭으로만 동작한다.
  - ALB 오리진에 커스텀 헤더 `superheader` 가 붙어 있지만 ALB 리스너에 이를 검사하는 규칙은 없다.
  - WAF `CreatedByCloudFront-2407cc5b`: 관리형 룰 3개 전부 **Count** — 차단하지 않는다. 로깅 없음.
  - ACM `*.mission-critical.site` 2장 (ap-northeast-2 = ALB, us-east-1 = CloudFront), DNS 검증, 2027-04 만료.
- **진입** — Public ALB 리스너 443(ACM, `TLS13-1-2-Res-PQ-2025-09`) + **80 은 리다이렉트가 아니라 forward**. `alb-public-sg` 가 80·443 을 전체 개방이라 CloudFront·WAF 를 우회해 ALB 로 직접 접근 가능.
  - `Targetgroup-web` 타깃 3개 = ASG 2대 + `WEB-test-a`(수동 등록). `tg-internal-alb` 는 `WAS-test-a` 1대뿐 (SPOF).
- **컴퓨트** — ASG `web-test` (min 2 · max 4 · desired 2, 시작 템플릿 `web` **v5 고정**, ELB 헬스체크, CPU 60% 목표추적).
  - 시작 템플릿 v5 = `t3.small`, default_version 은 4(`t2.small`). 버전을 지정하지 않고 띄우면 구버전이 나온다.
  - 전 버전이 골든 AMI `web-appache`(`ami-081f6180df874677d`, `web-ami` 인스턴스에서 생성)를 쓴다.
  - 단독: `WAS-test-a`(10.0.20.235, 프로파일 `was-test-iam`) · `WEB-test-a`(10.0.10.51, 프로파일 없음) · `bas-server`(10.0.0.196, 퍼블릭 IP, 프로파일 없음) · `web-ami`(10.0.0.133, 퍼블릭 IP, t2.medium, `mc-ec2-role`).
  - SSM 관리 노드는 `mc-ec2-role` 이 붙은 3대뿐 (ASG 2 + `web-ami`).
- **보안 그룹** — `web-instance-sg` 는 `0.0.0.0/0` 규칙 없음. ⚠️ `SG-bastion` 은 **22·80·443** 을, `was-instance-sg` 는 **80·443·8080** 을 `0.0.0.0/0` 에 개방 (WAS 는 프라이빗 서브넷이라 VPC 안에서만 닿는다).
- **IAM** — `mc-ec2-role` = `CloudWatchAgentServerPolicy` + `AmazonSSMManagedInstanceCore`. ⚠️ `was-test-iam` = `AmazonRDSFullAccess` (과잉). `rds-monitoring-role` 은 만들어져 있지만 미사용.
- **데이터** — RDS `mysql 8.0.44` · `db.t3.small` · Multi-AZ · gp3 200GB(최대 1000) · 암호화 · 파라미터 그룹 `petclinic-mysql-log`(슬로우 쿼리 2초). ⚠️ **자동 백업 0일, 수동 스냅샷 0개.** 향상된 모니터링·PI 꺼짐.
  - RDS Proxy: Secrets Manager 인증, IAM 인증 꺼짐, `RequireTLS=false`.
- **스토리지** — 버킷은 `mc-static-image` 하나뿐 → ALB·CloudFront 로그 버킷 없음. ALB 2대 모두 액세스 로깅 꺼짐.
  - ⚠️ 2026-09-19 18:46 KST 업로드된 객체 20개가 전부 `petclinic/resources/resources/…`(경로 중복)이고 `css/` 가 없다. CloudFront 경유 `/petclinic/resources/css/petclinic.css` 는 **403**. ALB 직접 접근은 200.
- **로그** — 로그 그룹 5개. `/petclinic/web/access`(30일) · `/petclinic/web/error`(90일), RDS 쪽 3개는 보존기간 없음. `audit` 내보내기가 켜져 있지만 옵션 그룹에 플러그인이 없어 로그 그룹이 생기지 않는다.
- **알림** — SNS 토픽 없음, 알람은 목표추적용 2개뿐, 리전 CloudTrail 없음.

## 범위 밖

계정에 있는 SageMaker 리소스, 서비스 연결 역할, 2021년 EFS 백업 플랜, `Bespin-Academy-Support_DO_NOT_DELETE` 역할.
