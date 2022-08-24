provider "aws" {
   region = var.region
}

locals {
  instance_name = "${terraform.workspace}-test"
}

resource "random_id" "id" {
  byte_length = 8
}

data "archive_file" "file_zip" {
    type          = "zip"
    source_file   = "functions/lambda_function.py"
    output_path   = "lambda_function.zip"
}

data "archive_file" "authentication_zip" {
    type          = "zip"
    source_file   = "functions/lambda_authentication.py"
    output_path   = "lambda_authentication.zip"
}


resource "aws_lambda_function" "lambda" {
	function_name = "cw356_lambda_function-${terraform.workspace}"
  filename         = "lambda_function.zip"

   source_code_hash = "${data.archive_file.file_zip.output_base64sha256}"
   
   handler = "lambda_function.handler"
   runtime = "python3.7"

   role = aws_iam_role.lambda_role.arn
}

resource "aws_lambda_function" "authentication" {
  function_name = "cw356_lambda_authentication-${terraform.workspace}"
  filename         = "lambda_authentication.zip"

  source_code_hash = "${data.archive_file.authentication_zip.output_base64sha256}"
   
  handler = "lambda_authentication.lambda_handler"
  runtime = "python3.7"

  role = aws_iam_role.lambda_role.arn

  environment {
    variables = {
      token = "token-${random_id.id.hex}"
    }
  }
}

resource "aws_iam_role" "lambda_role" {
   name = "cw356_lambda_role-${terraform.workspace}"
   
   managed_policy_arns = [ aws_iam_policy.log_policy.arn ]
   assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": [ "lambda.amazonaws.com" ]
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

}

resource "aws_iam_policy" "log_policy" {
  name = "cw356_lambda_policy-${terraform.workspace}"


  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["logs:*", "s3:*"]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role" "APIGLambdaAllowRole" {
  name = "cw356_api_gateway_lambda_iam_role-${terraform.workspace}"

  managed_policy_arns = [ aws_iam_policy.APIGLambdaAllowPolicy.arn ]
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "apigateway.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

}

resource "aws_iam_policy" "APIGLambdaAllowPolicy" {
  name = "cw356_apigateway_policy-${terraform.workspace}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["lambda:InvokeFunction"]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}


resource "aws_api_gateway_rest_api" "apiLambda" {
  name        = "cw356_api_gateway-${terraform.workspace}"
}

resource "aws_api_gateway_authorizer" "authorizer" {
  name                   = "cw356_authorizer-${terraform.workspace}"
  rest_api_id            = aws_api_gateway_rest_api.apiLambda.id
  authorizer_uri         = aws_lambda_function.authentication.invoke_arn
  type                   = "TOKEN"
  authorizer_result_ttl_in_seconds = 0
  authorizer_credentials = aws_iam_role.APIGLambdaAllowRole.arn
}

resource "aws_api_gateway_resource" "proxy" {
   rest_api_id = aws_api_gateway_rest_api.apiLambda.id
   parent_id   = aws_api_gateway_rest_api.apiLambda.root_resource_id
   path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxyMethod" {
   rest_api_id   = aws_api_gateway_rest_api.apiLambda.id
   resource_id   = aws_api_gateway_resource.proxy.id
   authorizer_id = aws_api_gateway_authorizer.authorizer.id
   http_method   = "ANY"
   authorization = "CUSTOM"
}

resource "aws_api_gateway_integration" "lambda" {
   rest_api_id = aws_api_gateway_rest_api.apiLambda.id
   resource_id = aws_api_gateway_method.proxyMethod.resource_id
   http_method = aws_api_gateway_method.proxyMethod.http_method

   integration_http_method = "POST"
   type                    = "AWS_PROXY"
   uri                     = aws_lambda_function.lambda.invoke_arn
}

resource "aws_api_gateway_deployment" "apideploy" {
   depends_on = [
     aws_api_gateway_integration.lambda,
   ]

   rest_api_id = aws_api_gateway_rest_api.apiLambda.id
   stage_name  = var.api_gateway_stage_name
}


resource "aws_lambda_permission" "apigw" {
   statement_id  = "AllowAPIGatewayInvoke"
   action        = "lambda:InvokeFunction"
   function_name = aws_lambda_function.lambda.function_name
   principal     = "apigateway.amazonaws.com"

   source_arn = "${aws_api_gateway_rest_api.apiLambda.execution_arn}/*/*"
}


output "base_url" {
  value = aws_api_gateway_deployment.apideploy.invoke_url
}

output "api_token" {
  value = "token-${random_id.id.hex}"
}


//------------------------------Updated Code----------------------------------//

resource "aws_acm_certificate" "api" {
  domain_name       = "${terraform.workspace}.benthonlabs.com"
  validation_method = "DNS"
}

data "aws_route53_zone" "public" {
  name         = "benthonlabs.com"
  private_zone = false
}

resource "aws_route53_record" "api_validation" {
  for_each = {
    for dvo in aws_acm_certificate.api.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.public.zone_id
}

resource "aws_acm_certificate_validation" "api" {
  certificate_arn         = aws_acm_certificate.api.arn
  validation_record_fqdns = [for record in aws_route53_record.api_validation : record.fqdn]
}




resource "aws_apigatewayv2_domain_name" "api" {
  domain_name = "${terraform.workspace}.benthonlabs.com"

  domain_name_configuration {
    certificate_arn = aws_acm_certificate.api.arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }

  depends_on = [aws_acm_certificate_validation.api]
}

resource "aws_route53_record" "api" {
  name    = aws_apigatewayv2_domain_name.api.domain_name
  type    = "A"
  zone_id = data.aws_route53_zone.public.zone_id

  alias {
    name                   = aws_apigatewayv2_domain_name.api.domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.api.domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_apigatewayv2_api_mapping" "api_custom_config" {
  api_id      = aws_api_gateway_deployment.apideploy.rest_api_id
  domain_name = aws_apigatewayv2_domain_name.api.domain_name
  stage       = aws_api_gateway_deployment.apideploy.stage_name
}


output "name" {
  value = aws_apigatewayv2_domain_name.api.domain_name_configuration[0].target_domain_name
}

output "zone_id" {
  value = aws_apigatewayv2_domain_name.api.domain_name_configuration[0].hosted_zone_id
}

output "api_gateway" {
  value = aws_api_gateway_rest_api.apiLambda.name
}


output "api_gateway_stage_name" {
  value = aws_api_gateway_deployment.apideploy.stage_name
}
    
