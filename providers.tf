provider "aws" {
  region = var.region
}

# CloudFront 에 붙는 글로벌 리소스(WAF · 뷰어 인증서)는 us-east-1 에만 존재한다
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# AWS Chatbot(Amazon Q Developer in chat applications) API 는 서울 엔드포인트가 없다 — 콘솔이 만든 구성도 us-east-2 에 있다.
provider "aws" {
  alias  = "us_east_2"
  region = "us-east-2"
}
