# Service discovery: tasks register themselves in a private DNS namespace, so
# orders can call http://auth.local:3000 without knowing any IP address.
resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = var.namespace_name
  description = "Private DNS for service-to-service calls"
  vpc         = aws_vpc.main.id
}

resource "aws_service_discovery_service" "svc" {
  for_each = local.services

  name = each.key

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.main.id
    routing_policy = "MULTIVALUE"

    dns_records {
      type = "A"
      ttl  = 10
    }
  }

  health_check_custom_config {}
}
