# CloudWatch cross-account observability (PLAN 9.1). One sink in the observability account, one link per source
# account and region. Sinks and links are regional: a link only reaches a sink in the same region.

locals {
  is_sink = var.mode == "sink"
  is_link = var.mode == "link"
}

resource "aws_oam_sink" "this" {
  count = local.is_sink ? 1 : 0

  name = var.sink_name
  tags = var.tags
}

# Only accounts of this organization may link, and only for the resource types we chose.
resource "aws_oam_sink_policy" "this" {
  count = local.is_sink ? 1 : 0

  sink_identifier = aws_oam_sink.this[0].arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "*" }
      Action    = ["oam:CreateLink", "oam:UpdateLink"]
      Resource  = "*"
      Condition = {
        "ForAllValues:StringEquals" = { "oam:ResourceTypes" = var.resource_types }
        StringEquals                = { "aws:PrincipalOrgID" = var.organization_id }
      }
    }]
  })
}

resource "aws_oam_link" "this" {
  count = local.is_link ? 1 : 0

  label_template  = var.label_template
  resource_types  = var.resource_types
  sink_identifier = var.sink_arn
  tags            = var.tags
}

resource "aws_prometheus_workspace" "this" {
  count = local.is_sink && var.enable_prometheus ? 1 : 0

  alias = var.prometheus_alias
  tags  = var.tags
}
