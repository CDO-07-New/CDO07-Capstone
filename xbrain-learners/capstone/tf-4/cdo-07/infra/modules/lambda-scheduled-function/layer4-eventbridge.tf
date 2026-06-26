################################################################################
# Layer 4 - EventBridge: Window Feeder Schedule
#
# Module-ready boundary:
# - This file owns only scheduling and invoke permission.
# - Lambda implementation details stay in layer4-lambda.tf.
################################################################################

variable "window_feeder_schedule_expression" {
  description = "EventBridge schedule expression for the Window Feeder."
  type        = string
  default     = "rate(5 minutes)"
}

variable "window_feeder_schedule_enabled" {
  description = "Enable or disable the Window Feeder schedule."
  type        = bool
  default     = true
}

variable "window_feeder_event_payload" {
  description = "Static event payload sent by EventBridge to the Window Feeder."
  type        = map(string)
  default = {
    source       = "eventbridge"
    window       = "2h"
    predict_path = "/v1/predict"
  }
}

output "window_feeder_schedule_rule_name" {
  description = "EventBridge rule name for Window Feeder."
  value       = module.window_feeder.event_rule_name
}

output "window_feeder_schedule_rule_arn" {
  description = "EventBridge rule ARN for Window Feeder."
  value       = module.window_feeder.event_rule_arn
}
