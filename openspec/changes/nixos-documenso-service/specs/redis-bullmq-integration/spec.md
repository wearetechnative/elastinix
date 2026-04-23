## ADDED Requirements

### Requirement: Auto-enable Redis when BullMQ selected
The module SHALL automatically enable Redis service when jobs.provider is "bullmq".

#### Scenario: BullMQ enables Redis
- **WHEN** jobs.provider = "bullmq"
- **THEN** services.redis.servers.documenso.enable = true

#### Scenario: Redis persistence configured
- **WHEN** Redis is auto-enabled
- **THEN** RDB and AOF persistence are configured for job durability

### Requirement: Redis connection configuration
The module SHALL configure BullMQ to connect to Redis.

#### Scenario: Redis URL generated
- **WHEN** jobs.provider = "bullmq"
- **THEN** NEXT_PRIVATE_REDIS_URL includes host, port, optional password

#### Scenario: Systemd dependency
- **WHEN** BullMQ enabled
- **THEN** documenso.service requires and starts after redis-documenso.service
