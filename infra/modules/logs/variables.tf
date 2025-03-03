####################################################
# Logs module variables.tf
####################################################

variable "log_group_name" {
  type        = string
  description = "Name of the CloudWatch Log Group"
}

variable "retention_in_days" {
  type        = number
  description = "Number of days to retain the logs"
  default     = 0
  # Some common retention values: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 365
}
