# petclinic-iac — PetClinic 3티어 AWS 인프라 as-built

**조회 전용 레포입니다. `resource` 블록이 하나도 없고 `data` 와 `output` 만 있습니다.**
`terraform apply` 를 실행해도 **아무것도 생성·수정·삭제되지 않습니다.**

기존에 콘솔로 구축돼 돌고 있는 인프라를 코드로 읽어낼 수 있게만 해둔 상태입니다.
관리(import)로 넘어가는 방법은 아래 「관리로 전환」 절을 보세요.

- 계정: `723165663216` · 리전: `ap-northeast-2` (서울)
- 조회 기준일: **2026-09-19**

## 사용법

```bash
terraform init

# `aws login` 자격증명은 provider 가 직접 못 읽는다 — 환경변수로 넘긴다
eval "$(aws configure export-credentials --profile default --format env)"

terraform plan      # data 소스만 읽는다 — "No changes" 가 정상
terraform output    # 아래 as-built 표에 해당하는 값이 나온다
```

`apply` 는 쓰지 마세요. 써도 아무 일도 없지만, 이 레포의 전제는 "읽기만" 입니다.

## 이 레포가 조회하는 것

| 계층 | 리소스 | 코드 |
|---|---|---|
| 엣지 | CloudFront 분포 `E1F6M0QDUUT8AG` — 도메인·별칭·상태·WAF | `data.tf` |
| 네트워크 | VPC `test-vpc`, 서브넷 8개(public 2 · private 6) | `data.tf` |
| 네트워크 | IGW 1 · NAT 2 · 라우트 테이블 6 · VPC 엔드포인트 1 | `data.tf` |
| 진입 | ALB `test-Public-ALB`, `alb-internal-test` | `data.tf` |
| 진입 | 타깃 그룹 `Targetgroup-web`(HTTP 80 · /health.html), `tg-internal-alb`(HTTP 8080 · /petclinic/) | `data.tf` |
| 컴퓨트 | ASG `web-test` (min 2 · max 4 · desired 2, 시작 템플 `web` **v5 고정**) | `data.tf` |
| 컴퓨트 | 시작 템플릿 `web` | `data.tf` |
| 컴퓨트 | 단독 인스턴스 `WAS-test-a` · `WEB-test-a` · `bas-server` · `web-ami` | `data.tf` |
| 컴퓨트 | 보안 그룹 7개, IAM 역할 `mc-ec2-role`, 인스턴스 프로파일 2개 | `data.tf` |
| 데이터 | RDS `database-1`, RDS Proxy `pet-proxy`, DB 서브넷 그룹 `petclinic-db-subnet-group` | `data.tf` |
| 스토리지 | S3 `mc-static-image` + 버킷 정책(CloudFront OAC) | `data.tf` |
| 로그 | CloudWatch 로그 그룹 5개 | `data.tf` |

이름·ID 는 전부 `variables.tf` 의 `default` 로 빠져 있습니다. 값이 바뀌면 거기만 고치면 됩니다.

## 조회 시 확인된 사실 (2026-09-19)

- **엣지** — CloudFront `E1F6M0QDUUT8AG` · `d3q5zkso8oivib.cloudfront.net` · 상태 `Deployed` · 별칭 `24petclinic.mission-critical.site` · CloudFront 가 만든 WAF 연결.
  - Route53 에 이 별칭의 A 레코드는 **없습니다** — 별칭만 분포에 남아 있습니다.
  - **오리진·캐시 동작은 데이터 소스가 노출하지 않습니다.** 실측 구성: 오리진 2개(Public ALB `https-only`, S3 `mc-static-image` + OAC), 캐시 동작 `/petclinic/resources/*` → S3, 기본 동작 → ALB.
- **ASG 안에 인스턴스 2대, 밖에 단독 WEB/WAS 1대** — ASG `web-test` 와 단독 `WEB-test-a` 가 공존합니다.
- **ASG 는 시작 템플릿을 `$Latest` 가 아니라 버전 `5` 로 고정**해 씁니다. 템플릿의 `default_version` 은 `4` 라서, 버전을 지정하지 않고 인스턴스를 띄우면 **구버전(t2.small)** 이 나옵니다.
- **시작 템플릿 v5 = `t3.small`**, v4 = `t2.small`. 둘 다 IAM `mc-ec2-role`, SG `web-instance-sg`.
  - v5 user data 에는 httpd 기본 `CustomLog` 를 끄는 `sed` 가 들어 있습니다 — 헬스체크 로그 오염 방지.
- **웹 인스턴스 2대는 `t3.small`** (ASG 가 v5 로 교체 완료).
- **S3 버킷이 `mc-static-image` 하나뿐** — 로그 전용 버킷이 없습니다. 즉 ALB 액세스 로그 · CloudFront 로그 · CloudWatch Logs → S3 아카이브가 **전부 미배포**입니다.
- **ALB 2대 모두 액세스 로깅 꺼**(`AccessLogs: null`).
- **CloudWatch 로그 그룹 5개** — `/petclinic/web/access`(보존 30일) · `/petclinic/web/error`(90일) · `/aws/rds/instance/database-1/error` · `/aws/rds/instance/database-1/slowquery` · `/aws/rds/proxy/pet-proxy`. **RDS 쪽 3개는 보존기간이 없어 만료되지 않습니다.**
- **IAM 인스턴스 프로파일** — `WAS-test-a` 는 `was-test-iam`, `web-ami` 와 ASG 웹 2대는 `mc-ec2-role`. **`bas-server` · `WEB-test-a` 에는 붙어 있지 않습니다.**
  - `mc-ec2-role` 에는 `CloudWatchAgentServerPolicy` 와 `AmazonSSMManagedInstanceCore` 가 붙어 있어, 붙은 인스턴스는 SSM 관리 노드이자 CloudWatch Agent 로그 전송이 가능합니다.
- **보안 그룹 7개** — `SG-bastion` · `alb-public-sg` · `alb-internal-sg` · `web-instance-sg` · `was-instance-sg` · `petclinic-db-sg` · `default`.
  - `web-instance-sg`: 80 ← `alb-public-sg`, 22·443·8080 ← `SG-bastion`. **`0.0.0.0/0` 규칙은 없습니다.**
  - ⚠️ `SG-bastion` 자체는 22 를 `0.0.0.0/0` 에 열어 둔 상태입니다.
- 계층별 배치: ASG `web-test` 와 `WEB-test-a` 는 web 서브넷(10.0.10.x · 10.0.11.x), `WAS-test-a` 는 WAS 서브넷(10.0.20.235), `bas-server`(10.0.0.196) 와 `web-ami`(10.0.0.133) 는 **public 서브넷**에 있습니다.
- RDS: `mysql 8.0.44` · `db.t3.small` · `multi_az = true` · 200GB.
- RDS 자격증명은 Secrets Manager 의 RDS 관리형 시크릿(`rds!db-…`)을 씁니다.

> 위 값은 `terraform plan` 이 계정에서 실제로 data 소스를 읽어 확인한 것입니다 (2026-09-19). 플랜 결과는 "인프라 변경 없음, 출력값만 저장" 이었습니다.

## 범위

**포함** — 엣지(CloudFront 메타데이터) · 네트워크 · 진입 · 컴퓨트 · 데이터 · 스토리지 · 로그.

**이 레포에 없음** — Route53 · ACM · WAF 규칙 · Secrets Manager · CloudWatch 알람 · VPC 엔드포인트 상세.
CloudFront 는 **분포 메타데이터만** 담습니다 — 오리진·캐시 동작은 AWS 데이터 소스가 제공하지 않아 코드로 표현할 수 없습니다.
계정에 있는 SageMaker 리소스도 범위 밖입니다.

## 관리(import)로 전환하려면

이 레포는 "읽기"만 하므로, 실제로 코드가 인프라를 소유하게 만들려면 별도 절차가 필요합니다.

1. 대상 리소스에 대응하는 `resource` 블록을 **새 파일**(예: `imported.tf`)에 만든다.
2. `terraform import <주소> <실제 ID>` 로 상태에 가져온다.
   ID 는 `terraform output` 으로 미리 확인할 수 있다.
3. `terraform plan` 을 돌려 **변경이 0 인지** 확인한다.
   - 여기서 `replace`(강제 교체)가 뜨면 **절대 apply 하지 말 것.** 코드가 실물과 다르다는 뜻이다.
   - 차이가 사라질 때까지 코드를 실물에 맞춘다.
4. 변경이 0 이 된 다음에야 관리 대상으로 삼는다.

`data` 블록과 `resource` 블록은 같은 이름을 써도 충돌하지 않으므로, 전환 중에도 조회용 코드는 그대로 둘 수 있습니다.