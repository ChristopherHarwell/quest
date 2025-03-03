####################################################
# ECR module variables.tf
####################################################

variable "repo_name" {
  type        = string
  description = "Name of the ECR repository"
  default     = "quest-container-repository"
}

variable "execution_role_arn" {
  type        = string
  description = "IAM role ARN to be granted ECR permissions"
  default     = ""
}

variable "enable_repository_policy" {
  type        = bool
  description = "Whether to enable a repository policy granting access to the specified role"
  default     = true
}
