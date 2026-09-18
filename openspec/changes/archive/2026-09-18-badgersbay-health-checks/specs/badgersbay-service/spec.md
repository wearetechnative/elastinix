## ADDED Requirements

### Requirement: Declare a health check that measures something

The module SHALL declare a health check for the service, against the
unauthenticated `/health` endpoint on the loopback interface at the configured
port, expecting a 200 response.

The check SHALL read the response body and SHALL fail when the server reports
its storage location as inaccessible. A status code alone is not sufficient:
the server answers 200 with `storage.accessible` false when the directory it
writes submissions to has gone, and a check that only reads the code would
call that healthy.

The module SHALL NOT direct a check at the dashboard. The dashboard is behind
basic auth, so an unauthenticated request to it answers 401 in every state the
service can be in, and a check that cannot distinguish healthy from broken is
not a check.

#### Scenario: A healthy server
- **WHEN** the service is running and its storage location exists
- **THEN** the declared checks pass: `/health` answers 200 and reports
  `storage.accessible` true

#### Scenario: Storage gone
- **WHEN** the storage location is missing or unreadable
- **THEN** `/health` still answers 200, and the check fails anyway, on the
  `storage.accessible` value it carries

#### Scenario: Server not answering
- **WHEN** the service is down, crash-looping, or not listening on the
  configured port
- **THEN** the checks fail on the request rather than reporting a state they
  could not observe

#### Scenario: The endpoint a probe is pointed at
- **WHEN** a monitoring probe is configured for this service, in this
  repository or in a host configuration
- **THEN** it targets `/health`, which needs no credentials, and never `/`,
  which answers 401 without them regardless of the service's state

#### Scenario: The port the check follows
- **WHEN** `port` is set to something other than the default
- **THEN** the checks address that port, as the firewall rule and the nginx
  proxy do
