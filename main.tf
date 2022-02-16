provider aws {
  region = "ap-south-1"
}



##################### creating a layer for flask module##################

resource "aws_lambda_layer_version" "lambda_layer" {
  filename   = "flask_layer.zip"
  layer_name = "flasklambda"

  compatible_runtimes = ["python3.6"]
}

################ creating a lambda role ####################

resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda1"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}



########### creating a lambda function


resource "aws_lambda_function" "test_lambda" {
  filename      = "lambda_function_payload.zip"
  function_name = "my_flask"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "app.pretend"

  # The filebase64sha256() function is available in Terraform 0.11.12 and later
  # For Terraform 0.11.11 and earlier, use the base64sha256() function and the file() function:
  # source_code_hash = "${base64sha256(file("lambda_function_payload.zip"))}"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")

  runtime = "python3.6"
  layers = [aws_lambda_layer_version.lambda_layer.arn]
  depends_on = [aws_lambda_layer_version.lambda_layer]
}

################## integrating with api######################
####################################### creating a api to integrate with above lambda function #####################

resource "aws_api_gateway_rest_api" "example" {
  name = "example"
  endpoint_configuration {
    types = ["REGIONAL"]  ##############EDGE, REGIONAL or PRIVATE###########
  }
  depends_on = [aws_lambda_function.test_lambda]
}


################################# creating a resource in api ############################
resource "aws_api_gateway_resource" "MyDemoResource" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  parent_id   = aws_api_gateway_rest_api.example.root_resource_id
  path_part   = "mydemoresource"
}


############################## creating a method in api under above resource  #########################

resource "aws_api_gateway_method" "MyDemoMethod" {
  rest_api_id   = aws_api_gateway_rest_api.example.id
  resource_id   = aws_api_gateway_resource.MyDemoResource.id
  http_method   = "GET"     
  authorization = "NONE"
}


###################### api is integrating with lambda function ####################################

resource "aws_api_gateway_integration" "integration" {
  rest_api_id             = aws_api_gateway_rest_api.example.id  
  resource_id             = aws_api_gateway_resource.MyDemoResource.id  
  http_method             = aws_api_gateway_method.MyDemoMethod.http_method 
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "${aws_lambda_function.test_lambda.invoke_arn}"
}




##################### deployment


########################################## creating a stage for deploy a lambda or invoke lambda function #####################



################# permission###########

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.test_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.example.execution_arn}/*/*/*"
}


















############################# integration response####################
resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  resource_id = aws_api_gateway_resource.MyDemoResource.id
  http_method = aws_api_gateway_method.MyDemoMethod.http_method
  status_code = "200"

}




####################### response#################
resource "aws_api_gateway_integration_response" "example" {
    http_method         = "GET"
    resource_id         = aws_api_gateway_resource.MyDemoResource.id
    response_parameters = {}
    response_templates  = {
        "application/json" = ""
    }
    rest_api_id         = aws_api_gateway_rest_api.example.id
    status_code         = "200"
    depends_on = [aws_api_gateway_method_response.response_200]
}

##############deployment


resource "aws_api_gateway_deployment" "example" {
  rest_api_id = aws_api_gateway_rest_api.example.id

  triggers = {
    # NOTE: The configuration below will satisfy ordering considerations,
    #       but not pick up all future REST API changes. More advanced patterns
    #       are possible, such as using the filesha1() function against the
    #       Terraform configuration file(s) or removing the .id references to
    #       calculate a hash against whole resources. Be aware that using whole
    #       resources will show a difference after the initial implementation.
    #       It will stabilize to only change when resources change afterwards.
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.MyDemoResource.id,
      aws_api_gateway_method.MyDemoMethod,
      aws_api_gateway_integration.integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
  depends_on = [aws_api_gateway_method.MyDemoMethod]
}


################# deployment stage#############


resource "aws_api_gateway_stage" "example" {
  deployment_id = aws_api_gateway_deployment.example.id
  rest_api_id   = aws_api_gateway_rest_api.example.id
  stage_name    = "example"

}


####################################outputs####################

output "stage_invoke_url" {
  description = "The URL to invoke the API pointing to the stage"
  value       = element(concat(aws_api_gateway_stage.example.*.invoke_url, [""]), 0)
}

