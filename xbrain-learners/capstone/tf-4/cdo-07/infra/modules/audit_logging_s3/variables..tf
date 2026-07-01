variable "environment" {
  type        = string
  default     = "capstone"
  description = "Môi trường triển khai hệ thống"
}

variable "kms_key_alias" {
  type        = string
  default     = "alias/tf4-cdo07-audit-cmk"
  description = "Alias của Customer Managed Key dùng để mã hóa S3"
}

variable "vpc_endpoint_id" {
  type        = string
  description = "ID của S3 VPC Gateway Endpoint dùng để giới hạn vùng mạng truy cập"
}

variable "default_tags" {
  type        = map(string)
  default     = {
    Project     = "foresight-lens"
    Team        = "CDO-07"
    Environment = "capstone"
    ManagedBy   = "terraform"
  }
  description = "Bộ tag tiêu chuẩn bắt buộc của dự án"
}