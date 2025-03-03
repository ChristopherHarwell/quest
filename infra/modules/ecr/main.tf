####################################################
# ECR module main.tf
####################################################

resource "aws_ecr_repository" "this" {
  name = var.repo_name
}

# Optional ECR repository policy granting access to a single IAM role.
# If you want to grant access to multiple roles or additional actions,
# adjust the policy logic or pass a JSON object from the root module.
resource "aws_ecr_repository_policy" "policy" {
  count = var.enable_repository_policy ? 1 : 0

  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    Version  = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { "AWS" : var.execution_role_arn }
        Action    = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:DescribeRepositories",
          "ecr:GetRepositoryPolicy"
        ]
      }
    ]
  })
}
