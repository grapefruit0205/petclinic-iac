# petclinic-iac — PetClinic 3티어 AWS 인프라 as-built

콘솔로 구축돼 돌고 있는 인프라를 **코드로 옮긴** 레포입니다. 두 층으로 되어 있습니다.

| 층 | 파일 | 역할 |
|---|---|---|
| 조회 | `data.tf` · `outputs.tf` · `variables.tf` | 실물을 읽어 출력한다. 아무것도 소유하지 않는다. |
| 소유(import) | `network.tf` · `security.tf` · `entry.tf` · `compute.tf` · `iam.tf` · `database.tf` · `storage.tf` · `edge.tf` · `monitoring.tf` + `import.tf` | 실물 87개에 대응하는 `resource` 블록과, 그것을 실물에 연결하는 `import` 블록 |

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
| 네트워크 | `network.tf` | VPC, 서브넷 8, IGW, NAT 2 + EIP 2, 라우트 테이블 5 + 기본 테이블, 연결 8 (EC2 Instance Connect Endpoint 는 2026-09-21 저녁 정리 — 코드·state 제거) |
| 보안 | `security.tf` | 보안 그룹 6 (규칙 인라인; `eice-sg` 는 2026-09-21 저녁 정리). `alb-public-sg` 443 은 CloudFront 프리픽스 리스트만 허용 |
| 진입 | `entry.tf` | ALB 2, 타깃 그룹 2, 리스너 3 (443 ACM · 80 · internal 80), 443 `superheader` 리스너 규칙, ALB 인증서 |
| 컴퓨트 | `compute.tf` | 골든 AMI `web-appache` · `was-goldenImage-test` · `was-goldenImage-test-v2`, 시작 템플릿 `web` · `was-lt`(latest v2, default 1), ASG `web-test`(CPU 60% 목표추적 + 요청수 단계 정책) · `was-asg`(CPU 60%, `$Latest`), 단독 인스턴스 5(골든 이미지 v2 원본 `was-gg2` 포함; v1 원본 `was-goldenImage` 는 9/22 종료), WAS 데이터 볼륨 + 연결 |
| IAM | `iam.tf` | 역할 4 (`mc-ec2-role` · `was-test-iam` · `bastion-role` · `rds-monitoring-role`), 프로파일 3, 정책 연결 5, 인라인 정책 1 (`was-test-iam` 의 `PetclinicReadRdsSecret`) |
| 데이터 | `database.tf` | RDS `database-1`, 파라미터 그룹, 서브넷 그룹 (RDS Proxy 는 2026-09-22 제거 결정 — 코드·state 에서 뺌) |
| 스토리지·로그 | `storage.tf` | S3 `mc-static-image` + 정책 · 퍼블릭 차단 · 암호화 · 버전 관리, 중앙 로그 버킷 `mc-logs-petclinic`(CloudFront `petclinic/prod/edge/` + ALB `petclinic/prod/entry/`) + 정책 · 퍼블릭 차단 · 수명주기(entry 90일), WAF 로그 버킷 `aws-waf-logs-petclinic-block`(us-east-1) + 정책, 로그 그룹 8 (web 4 · 베스천 2 · RDS 2) |
| 모니터링 | `monitoring.tf` | SNS 토픽 `mc-alerts` → Slack `#petclinic-alerts` (Amazon Q Developer in chat applications; 이메일 구독은 9/23 해제), 알람 `alarm-web-reqcount-high-20000` (Public ALB 타깃당 요청수 → web 단계 정책 + Slack) |
| 엣지 | `edge.tf` | CloudFront 분포 + OAC + Function(`petclinic-home-to-landing`, 코드는 `cloudfront/`), WAF 웹 ACL + 로깅 설정(S3, BLOCK 만), CloudFront 표준 로그 v2 전송 3종(소스·목적지·전송, us-east-1), CloudFront 인증서, Route53 존 + 레코드 3 (A · AAAA · ACM 검증) |

시작 템플릿(v6)과 `web-ami` 인스턴스의 user data 는 `userdata/` 에, CloudFront Function 코드는 `cloudfront/` 에 원문 그대로 있습니다. **바이트가 바뀌면 plan 에 변경으로 잡히니** 손대지 마세요 — 바꾸려면 콘솔에서 새 버전/게시를 만들고 그 원문을 다시 복사합니다.

### 콘솔에 있지만 코드에 없는 것

| 리소스 | 이유 |
|---|---|
| 키페어 `test-key` | 퍼블릭 키를 API 로 못 읽어 import 불가. 이름만 문자열로 참조 |
| Public ALB 의 EIP 2개 (`52.78.70.34` · `3.38.76.227`) | ELB 가 관리 |
| RDS 관리형 시크릿 `rds!db-…` | RDS 가 소유. `aws_db_instance.main.master_user_secret` 로 참조 |
| 알람 `TargetTracking-web-test-AlarmHigh/Low` | 목표추적 정책이 소유 |
| `default` SG · 기본 NACL | VPC 기본값 (SG 는 `data.tf` 에서 조회만) |
| 고아 OAC `E32W5M7BHL5ZBD`(`oac-mylab-junseok…`), 없는 분포 `E2KEFN428TOT1G` 용 CloudFront 로그 전송 소스, EFS 자동 백업 플랜(2021), 서비스 연결 역할, `Bespin-Academy-Support_DO_NOT_DELETE` | 이 스택과 무관하거나 정리 대상 |
| S3 객체 | 코드 범위 밖 |

### 코드로 표현할 수 없어 무시하는 것 (`lifecycle.ignore_changes`)

- ASG `force_delete` · `force_delete_warm_pool` · `ignore_failed_scaling_activities` · `wait_for_capacity_timeout` — Terraform 전용 인자. import 로 state 에 들어오지 않아 변경으로 잡히기 때문에 무시한다.
- 리스너 3개의 `default_action[0].forward` — 실물의 stickiness duration 이 0 인데 provider 는 1 이상만 받는다. 단일 타깃 그룹 forward 는 `target_group_arn` 이 전부.
- CloudFront Function `publish` — Terraform 전용 인자. 코드 변경은 콘솔에서 게시하고 `cloudfront/` 에 원문을 복사하는 운영.
- RDS `manage_master_user_password` 는 코드에 **넣지 않았다** — provider 가 import 시 이 값을 읽지 않아, 넣으면 변경으로 잡힌다.

## 실물 구조 (2026-09-19 실측)

```
Route53 24petclinic.mission-critical.site (A/AAAA alias)
  → CloudFront E1F6M0QDUUT8AG (WAF: 관리형 룰 3개, 전부 Count)
      ├ 기본(*)                → S3 mc-static-image (OAC)  랜딩 사이트: index.html · css/ · images/hero/hero.mp4
      ├ /petclinic/resources/* → S3 mc-static-image (OAC)  WAR 페이지용 css·폰트·이미지
      └ /petclinic/*           → Public ALB :443 (CachingDisabled + AllViewer, https-only, Host 헤더 전달)
              → Targetgroup-web :80 = ASG web-test 2대(t3.small) + WEB-test-a
                  httpd 리버스프록시 /petclinic/ → Internal ALB :80
                      → tg-internal-alb :8080 = ASG was-asg (was-lt v1 · t3.medium ×2~4, 2026-09-21) — 옛 WAS-test-a 는 등록 해제(아직 running)
                          → RDS database-1 직결 (MySQL 8.0.44, db.t3.small, Multi-AZ, 200GB)
                            ※ RDS Proxy pet-proxy 는 아무도 안 써서(ClientConnections 0) 2026-09-22 삭제
```

랜딩(`/`)은 WEB 파트가 S3 로 배포하고, 버튼(보호자 찾기·등록, 수의사)만 WAS 의 기능 페이지로 간다. WAS 의 옛 홈(`/petclinic/`)은 링크하지 않는다.

- **엣지** — CloudFront `d3q5zkso8oivib.cloudfront.net` · 상태 `Deployed` · 별칭 `24petclinic.mission-critical.site` · Default root object `index.html`.
  - 동작 3개 (2026-09-19 21:00 KST 콘솔 변경, `edge.tf` 반영): 기본 → S3 · `/petclinic/resources/*` → S3 · `/petclinic/*` → ALB (`CachingDisabled` + `AllViewer`).
  - `/petclinic/*` 에 뷰어 요청 함수 `petclinic-home-to-landing` (21:19 KST): WAR 메뉴의 HOME(`/petclinic/`)을 랜딩 `/` 로 302. `/petclinic`(슬래시 없음)은 `/petclinic/*` 에 안 걸려 S3 403 — 정확 일치 동작을 만들면 해결(미적용).
  - 변경 전엔 기본 동작(`UseOriginCacheControlHeaders`, 오리진 요청 정책 없음)이 **쿼리스트링을 오리진에 안 넘겨** 보호자 검색(`/owners?lastName=`)이 전체 목록만 돌려줬다. `AllViewer` 로 해결 (`?lastName=Franklin` → 302 `/owners/1` 확인).
  - Route53 존 `Z08667423LQZPT6BSL30W` 에 **A + AAAA alias 레코드가 있고** 공개 DNS 로 풀린다 (`https://24petclinic.mission-critical.site/` → 200, S3 랜딩).
  - `d3q5zkso8oivib.cloudfront.net` 으로 직접 오면 `/petclinic/*` 는 **502** — Host 헤더가 ALB 인증서(`*.mission-critical.site`)와 안 맞기 때문. 별칭으로만 동작한다.
  - ALB 오리진에 커스텀 헤더 `superheader` 가 붙고, **Public ALB 443 리스너가 이를 검사한다** (2026-09-21: 기본 동작 403 고정 응답 + 우선순위 1 규칙 `superheader` 일치 시 forward, `entry.tf` `aws_lb_listener_rule.public_https_superheader`).
  - WAF `CreatedByCloudFront-2407cc5b`: 관리형 룰 3개 전부 **Count** — 차단하지 않는다. 로깅 없음.
  - ACM `*.mission-critical.site` 2장 (ap-northeast-2 = ALB, us-east-1 = CloudFront), DNS 검증, 2027-04 만료.
- **진입** — Public ALB 리스너 443(ACM, `TLS13-1-2-Res-PQ-2025-09`) + 80 은 443 으로 301 (2026-09-21). 직접 접근 차단 3겹: **`alb-public-sg` 443 이 CloudFront 프리픽스 리스트만 허용**(2026-09-21 20:59 yena — ALB 주소 직접 호출은 TCP 타임아웃) → 443 리스너 `superheader` 규칙 → 웹 httpd `superheader` 검사(v6). ⚠️ 같은 SG 에 "22 ← 베스천" 규칙이 있는데 ALB 는 22 를 안 듣는다 — 의도 확인.
  - `Targetgroup-web` 타깃 = ASG 2대뿐 (`WEB-test-a` 는 21:45 KST 등록 해제). `tg-internal-alb` 타깃 = ASG `was-asg` 2대 (2026-09-21, `WAS-test-a` 등록 해제 — SPOF 해소; 18:46~18:52 KST 시작 템플릿 v2 = AMI v2 로 교체, ASG 는 `$Latest`). ⚠️ `was-asg` 프로파일 `was-test-iam` 엔 SSM·CloudWatch 정책이 없어 WAS 로그는 아직 안 올라간다.
- **컴퓨트** — ASG `web-test` (min 2 · max 4 · desired 2, 시작 템플릿 `web` **v7 고정**(9/22 리프레시 `482197d8`), ELB 헬스체크 유예 120, CPU 60% 목표추적 + 요청수 단계 정책(워밍업 300)).
  - 시작 템플릿 v6 = v5(`t3.small`) + user data 에 `superheader` 검사(`/health.html` 예외). default_version 도 6 (2026-09-20 콘솔에서 4→6 — 버전 미지정 시 구버전 t2.small 이 뜨던 함정 해소). 인스턴스 리프레시 `cfe16cb8`(9/19 21:40~21:52 KST)로 2대 교체 완료.
  - 전 버전이 골든 AMI `web-appache`(`ami-081f6180df874677d`, 9/15 `web-ami` 인스턴스에서 CreateImage)를 쓴다. v6 부터 설정은 user data 에 있어 AMI 를 다시 굽는 일은 패키지 갱신 때만.
  - 단독: `WAS-test-a`(10.0.20.235, 프로파일 `was-test-iam`, 타깃 해제, **9/22 중지**) · `was-gg2`(10.0.30.167, DB 서브넷, **running** — 골든 AMI `was-goldenImage-test-v2` 의 원본, 9/21 20:58 재시작) · `WEB-test-a`(10.0.10.51, **중지됨**, `mc-ec2-role` 부착, 타깃 해제 — WEB 계층 실험용) · `bas-server`(10.0.0.196, 퍼블릭 IP, 프로파일 없음) · `web-ami`(10.0.0.133, t2.medium, `mc-ec2-role`, **중지됨** — 골든 AMI `web-appache` 의 원본, 역할 종료).
  - **WAS-test-a 실측 (SSH, 2026-09-19)** — user data 없이 **수동 설치**. AL2023 · Corretto **1.8.0_504**(JDK devel 포함) · Tomcat **9.0.121** `/opt/tomcat`, systemd `tomcat.service`(User=tomcat, `-Xms512m -Xmx1024m`, 힙덤프 `/data/dump`) · 포트 8080(HTTP), 8005(shutdown, localhost).
    - `/data` = 추가 20GB 암호화 볼륨(`/dev/sdf`): `logs/tomcat`(`/opt/tomcat/logs` 심볼릭 링크) · `dump` · `temp`.
    - 앱은 `/opt/tomcat/webapps/petclinic.war`(42.7MB, 9/16 10:19 복사, Tomcat 자동 배포). 서버에 소스 없음 → **밖에서 빌드해 WAR 만 복사**하는 방식. `-P MySQL` 로 빌드되어 `jdbc:mysql://database-1.c6vk…:3306/petclinic` **직결**, 사용자 `admin`(RDS 마스터).
    - Tomcat 기본 앱(`ROOT`·`docs`·`examples`·`manager`·`host-manager`)이 그대로 배포돼 있다. `mariadb105` 클라이언트 설치됨.
    - 재배포 = 새 WAR 를 `/tmp` 로 scp → `tomcat` 정지 → `webapps/petclinic{,.war}` 삭제 → 복사·chown → 시작. 1대뿐이라 그동안 502.
  - SSM 관리 노드는 `mc-ec2-role` 이 붙은 인스턴스뿐 (ASG 2 + 시작하면 `web-ami` · `WEB-test-a`).
- **보안 그룹** — `web-instance-sg` 는 `0.0.0.0/0` 규칙 없음. ⚠️ `SG-bastion` 은 **22·80·443** 을, `was-instance-sg` 는 **80·443·8080** 을 `0.0.0.0/0` 에 개방 (WAS 는 프라이빗 서브넷이라 VPC 안에서만 닿는다).
- **IAM** — `mc-ec2-role` = `CloudWatchAgentServerPolicy` + `AmazonSSMManagedInstanceCore`. ⚠️ `was-test-iam` = `AmazonRDSFullAccess` (과잉). `rds-monitoring-role` 은 만들어져 있지만 미사용.
- **데이터** — RDS `mysql 8.0.44` · `db.t3.small` · Multi-AZ · gp3 200GB(최대 1000) · 암호화 · 파라미터 그룹 `petclinic-mysql-log`(슬로우 쿼리 2초). ⚠️ **자동 백업 0일, 수동 스냅샷 0개.** 향상된 모니터링·PI 꺼짐.
  - RDS Proxy `pet-proxy`: WAS 가 프록시를 거치지 않고 RDS 에 직결(`ClientConnections` 0)해 **2026-09-22 08:55 KST 삭제** (역할 `rds-proxy-role-…`·정책·로그 그룹 `/aws/rds/proxy/pet-proxy` 도 09:00 같이 삭제). 코드·state 에 흔적 없음.
  - ⚠️ WAR 에 박힌 `admin` 비밀번호는 RDS 관리형 시크릿이라 **자동 교체가 켜져 있다** — 교체되는 순간 앱 DB 접속이 끊긴다. 전용 앱 사용자 + 교체 없는 시크릿으로 바꿔야 한다.
- **스토리지** — 버킷은 `mc-static-image` 하나뿐 → ALB·CloudFront 로그 버킷 없음. ALB 2대 모두 액세스 로깅 꺼짐.
  - 버킷 구조 (2026-09-19 21:10 KST): 루트에 랜딩(`index.html` · `css/mc-site.css` · `images/hero-poster.jpg` · `images/hero/hero.mp4`), `petclinic/resources/{css,fonts,images,js}` 에 WAR 페이지용 정적 파일 22개. 원본은 `middleproject` 의 `docs/site-static/` 과 `src/main/webapp/resources/`(`less/` 제외).
  - 정적 파일을 바꾸면 S3 업로드 + CloudFront 무효화(`/*` 또는 바뀐 경로). 무효화 안 하면 하루(CachingOptimized 기본 TTL) 동안 옛것이 보인다.
- **로그** — 로그 그룹 8개. `/petclinic/prod/web/apache/{access,error}` · `…/web/ssh/access` · `…/web/bootstrap`(v7, 9/22) + `/petclinic/prod/bastion/ssh/secure`(베스천, 9/22) + `/petclinic/prod/bastion/system/messages`(9/22 생성, 에이전트 설정엔 미포함 — 선택) + RDS 2개(보존 없음). 옛 `/petclinic/web/*` 는 v7 리프레시와 함께 삭제. `audit` 내보내기가 켜져 있지만 옵션 그룹에 플러그인이 없어 로그 그룹이 생기지 않는다.
- **알림** — SNS 토픽 없음, 알람은 목표추적용 2개뿐, 리전 CloudTrail 없음.

## 범위 밖

계정에 있는 SageMaker 리소스, 서비스 연결 역할, 2021년 EFS 백업 플랜, `Bespin-Academy-Support_DO_NOT_DELETE` 역할.
