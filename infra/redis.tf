# Shared session store so any auth task can validate a session created by any
# other task. Private subnets only, encrypted at rest and in transit.
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.project_name}-redis"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "${var.project_name}-redis"
  description          = "Session store for the auth service"

  engine               = "redis"
  engine_version       = "7.1"
  parameter_group_name = "default.redis7"
  node_type            = var.redis_node_type
  port                 = 6379

  num_cache_clusters         = 1 # single node for the demo; use 2+ with automatic failover in production
  automatic_failover_enabled = false

  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  apply_immediately = true
}
