output "stream_arn" {
  description = "ARN of the Kinesis Data Stream — used for IAM policies and event source mappings."
  value       = aws_kinesis_stream.telemetry.arn
}

output "stream_name" {
  description = "Name of the Kinesis Data Stream."
  value       = aws_kinesis_stream.telemetry.name
}
