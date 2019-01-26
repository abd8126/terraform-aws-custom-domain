resource aws_api_gateway_domain_name domain {
  domain_name     = "${var.domain_name}"
  certificate_arn = "${var.certificate_arn}"
}

resource aws_api_gateway_base_path_mapping base_path {
  api_id      = "${var.api_id}"
  domain_name = "${aws_api_gateway_domain_name.domain.domain_name}"
  stage_name  = "${var.api_stage_name}"
}

resource aws_route53_record a {
  type     = "A"
  name     = "${aws_api_gateway_domain_name.domain.domain_name}"
  zone_id  = "${var.route53_zone_id}"

  alias {
    evaluate_target_health = false
    name                   = "${aws_api_gateway_domain_name.domain.cloudfront_domain_name}"
    zone_id                = "${aws_api_gateway_domain_name.domain.cloudfront_zone_id}"
  }
}
