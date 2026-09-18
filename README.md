# petclinic-iac — PetClinic 3티어 AWS 인프라 as-built

**조회 전용 레포입니다. `resource` 블록이 하나도 없고 `data` 와 `output` 만 있습니다.**
`terraform apply` 를 실행해도 **아무것도 생성·수정·삭제되지 않습니다.**

기존에 콘솔로 구축돼 돌고 있는 인프라를 코드로 읽어낼 수 있게만 해둔 상태입니다.
관리(import)로 넘어가는 방법은 아래 「관리로 전환」 절을 보세요.

- 계정: `723165663216` · 리전: `ap-northeast-2` (서울)
- 조회 기준일: 2026-09-18

## 사용법

```bash
terraform init      # 프로바이더 내려받기
terraform plan      # data 소스만 읽는다 — "No changes" 가 정상
terraform output    # 아래 as-built 표에 해당하는 값이 나온다
```

`apply` 는 쓰지 마세요. 써도 아무 일도 없지만, 이 레포의 전제는 "읽기만" 입니다.

## 이 레포가 조회하는 것

| 계층 | 리소스 | 코드 |
|---|---|---|
| 네트워크 | VPC `test-vpc`, 서브넷 8개(public 2 · private 6) | `data.tf` |
| 네트워크 | IGW 1 · NAT 2 · 라우트 테이블 6 · VPC 엔드포인트 1 | `data.tf` |
| 진입 | ALB `test-Public-ALB`, `alb-internal-test` | `data.tf` |
| 진입 | 타깃 그룹 `Targetgroup-web`(HTTP 80 · /health.html), `tg-internal-alb`(HTTP 8080 · /petclinic/) | `data.tf` |
| 컴퓨트 | ASG `web-test` (min 2 · max 4 · desired 2, 시작 템플릿 `web`) | `data.tf` |
| 컴퓨트 | 시작 템플릿 `web` | `data.tf` |
| 컴퓨트 | 단독 인스턴스 `WAS-test-a` · `WEB-test-a` · `bas-server` · `web-ami` | `data.tf` |
| 컴퓨트 | 보안 그룹 7개, IAM 역할 `mc-ec2-role`, 인스턴스 프로파일 2개 | `data.tf` |
| 데이터 | RDS `database-1`, RDS Proxy `pet-proxy`, DB 서브넷 그룹 `petclinic-db-subnet-group` | `data.tf` |
| 스토리지 | S3 `mc-static-image` | `data.tf` |
| 로그 | CloudWatch 로그 그룹 `/aws/rds/instance/database-1/error` · `/aws/rds/proxy/pet-proxy` | `data.tf` |

이름·ID 는 전부 `variables.tf` 의 `default` 로 빠져 있습니다. 값이 바뀌면 거기만 고치면 됩니다.

## 조회 시 확인된 사실 (2026-09-18)

- **ASG 안에 인스턴스 2대, 밖에 단독 WEB/WAS 1대** — ASG `web-test` 와 단독 `WEB-test-a` 가 공존합니다.
- **S3 버킷이 `mc-static-image` 하나뿐** — 로그 버킷이 없습니다. 즉 ALB 액세스 로그·CloudFront 로그·CloudWatch Logs → S3 아카이브가 **전부 미배포**입니다.
- **ALB 2대 모두 액세스 로깅 꺼**(`AccessLogs: null`).
- **CloudWatch 로그 그룹 2개뿐, 둘 다 보존기간 없음(만료 없음)**. `/petclinic/*` 로 시작하는 그룹은 0개라 CloudWatch Agent 가 어느 인스턴스에서도 돌지 않습니다.
- **RDS 파라미터 그룹은 기본값** — 커스텀 파라미터 그룹이 없습니다.
- RDS 자격증명은 Secrets Manager 의 RDS 관리형 시크릿(`rds!db-…`)을 씁니다.
- **WEB·배스천·web-ami 인스턴스에는 IAM 인스턴스 프로파일이 붙어 있지 않습니다** (빈 문자열). `was-test-iam` 이 붙은 `WAS-test-a` 만 예외입니다. → 이 인스턴스들은 SSM 관리 노드가 아니라서 CloudWatch Agent 를 SSM 으로 배포할 수 없고, 이것이 `/petclinic/*` 로그 그룹이 0개인 이유와 맞물립니다.
- 계층별 배치: ASG `web-test` 와 `WEB-test-a` 는 web 서브넷(10.0.10.x·10.0.11.x), `WAS-test-a` 는 WAS 서브넷(10.0.20.235), `bas-server`(10.0.0.196)와 `web-ami`(10.0.0.133)는 **public 서브넷**에 있습니다.
- 시작 템플릿 `web` 은 `default_version = 1`, `latest_version = 2` 입니다 — ASG 가 어느 버전을 쓰는지는 별도 확인이 필요합니다.
- RDS: `mysql 8.0.44` · `db.t3.small` · `multi_az = true` · 200GB.

> 위 값은 `terraform plan` 이 계정에서 실제로 data 소스를 읽어 확인한 것입니다 (2026-09-18). 플랜 결과는 "인프라 변경 없음, 출력값만 저장" 이었습니다.

## 범위  (이 레포에 없음)

CloudFront · Route53 · ACM · WAF · Secrets Manager · CloudWatch 알람은 3티어 본체가 아니라서 넣지 않았습니다.
계정에 있는 SageMaker 리소스도 범위 밖입니다.

## 관리(import)로 전환하려면

이 레포는 "읽기"만 하므로, 실제로 코드가 인프라를 소유하게 만들려면 별도 절차가 필요합니다.

1. 대상 리소스에 대응하는 `resource` 블록을 **새 파일**(예: `imported.tf`)에 다.
2. `terraform import <주소> <실제 ID>` 로 상태에 가져온다.
   ID 는 `terraform output` 으로 저 확인할 수 있다.
3. `terraform plan` 을 돌려 **변경이 0 인지** 확인한다.
   - 여기서 `replace`(강제 교체)가 뜨면 **절대 apply 하지 말 것.** 코드가 실물과 다르다는 뜻이다.
   - 차이가 사라질 때까지 코드를 실물에 맞춘다.
4. 변경이 0 이 된 다음에야 관리 대상으로 삼는다.

`data` 블록과 `resource` 블록은 같은 이름을 써도 충돌하지 않으므로, 전환 중에도 조회용 코드는 그대로  수 있습니다.