provider "aws" {
  region = var.region
}

# CloudFront 에 붙는 글로벌 리소스(WAF · 뷰어 인증서)는 us-east-1 에만 존재한다
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
