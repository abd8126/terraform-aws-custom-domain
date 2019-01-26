# AWS API Gateway Custom Domain

Add a custom domain for API Gateway REST API.

## Usage

```hcl
module domain {
  source          = "amancevice/custom-domain/aws"
  api_id          = "<api-gateway-rest-api-id>"
  api_stage_name  = "<api-gateway-deployment-stage>"
  domain_name     = "my.example.com"
  certificate_arn = "<acm-certificate-arn>"
  route53_zone_id = "<route53-hosted-zone-id>"
}
```
