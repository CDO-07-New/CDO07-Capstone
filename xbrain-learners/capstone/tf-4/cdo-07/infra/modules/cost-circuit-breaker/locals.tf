locals {
  name_prefix        = "${var.project}-${var.environment}"
  lambda_name        = "${local.name_prefix}-cost-circuit-breaker"
  ssm_parameter_path = trimprefix(var.ssm_parameter_name, "/")
  daily_spend_cap_usd = coalesce(
    var.daily_spend_cap_usd,
    ceil(var.monthly_budget_limit_usd / 30),
  )

  common_tags = merge(var.tags, {
    Component = "cost-circuit-breaker"
  })
}
