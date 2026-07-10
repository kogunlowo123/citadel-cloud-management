# AWS Cognito User Pools with Terraform: Authentication for Production Apps

**Pillar:** AWS Infrastructure
**SEO Target:** aws cognito user pool terraform mfa social login oauth production
**Word Count:** ~1500

AWS Cognito handles user registration, authentication, MFA, and token management. This guide deploys production Cognito with MFA enforcement, social login, and Lambda triggers.

## User Pool

```hcl
resource "aws_cognito_user_pool" "main" {
  name = "${var.prefix}-users"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  mfa_configuration = "ON"

  software_token_mfa_configuration {
    enabled = true
  }

  sms_authentication_message = "Your verification code is {####}"

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  schema {
    name                     = "tenant_id"
    attribute_data_type      = "String"
    mutable                  = false
    required                 = false
    string_attribute_constraints {
      min_length = 1
      max_length = 64
    }
  }

  lambda_config {
    pre_sign_up   = aws_lambda_function.pre_signup_trigger.arn
    post_confirmation = aws_lambda_function.post_confirm_trigger.arn
    pre_token_generation = aws_lambda_function.pre_token_trigger.arn
  }

  tags = var.tags
}
```

## App Client with OAuth

```hcl
resource "aws_cognito_user_pool_client" "web" {
  name         = "web-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  callback_urls                        = var.callback_urls
  logout_urls                          = var.logout_urls
  supported_identity_providers         = ["COGNITO", "Google"]

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH"
  ]

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  prevent_user_existence_errors = "ENABLED"
}
```

## Google Identity Provider

```hcl
resource "aws_cognito_identity_provider" "google" {
  user_pool_id  = aws_cognito_user_pool.main.id
  provider_name = "Google"
  provider_type = "Google"

  provider_details = {
    client_id                     = var.google_client_id
    client_secret                 = var.google_client_secret
    authorize_scopes              = "email profile openid"
    attributes_url                = "https://people.googleapis.com/v1/people/me?personFields="
    attributes_url_add_attributes = "true"
    authorize_url                 = "https://accounts.google.com/o/oauth2/v2/auth"
    oidc_issuer                   = "https://accounts.google.com"
    token_request_method          = "POST"
    token_url                     = "https://www.googleapis.com/oauth2/v4/token"
  }

  attribute_mapping = {
    email    = "email"
    username = "sub"
    name     = "name"
    picture  = "picture"
  }
}
```

## Production Checklist

- [ ] MFA=ON enforced (not OPTIONAL) for production user pools
- [ ] TOTP software token MFA (no SMS dependency)
- [ ] Custom attributes for tenant_id (multi-tenant isolation)
- [ ] Pre-token-generation Lambda to inject custom claims
- [ ] prevent_user_existence_errors=ENABLED (prevents user enumeration)
- [ ] Access/ID tokens 1 hour; refresh tokens 30 days
- [ ] Callback URLs restricted to your domains only
- [ ] Google/Facebook social login via Identity Provider config
