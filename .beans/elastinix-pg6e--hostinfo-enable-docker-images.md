---
# elastinix-pg6e
title: 'hostinfo: enableDockerImages option and docker-inventory service'
status: completed
type: task
priority: normal
created_at: 2026-07-27T00:00:00Z
updated_at: 2026-07-27T00:00:00Z
parent: elastinix-p9gu
---

Add an `enableDockerImages` option to the hostinfo service, so the central scanner
can fetch the running Docker images per host over HTTP.

## What

A new `elastinix.services.hostinfo.enableDockerImages` option that:

1. Creates a systemd service `elastinix-docker-inventory` querying the Docker
   socket and writing the resulting list to
   `/var/lib/docker-inventory/images.json`
2. Adds a daily systemd timer triggering that service
3. Symlinks `/var/lib/hostinfo/docker-images.json` to
   `/var/lib/docker-inventory/images.json`, so hostinfo serves it

## docker-images.json format

```json
[
  {"image": "twentyhq/twenty-server", "tag": "v0.32.0", "digest": "sha256:abc..."},
  {"image": "gotenberg/gotenberg",    "tag": "8.2",     "digest": "sha256:def..."}
]
```

Generated through the Docker socket API:

```bash
curl --unix-socket /var/run/docker.sock http://localhost/containers/json \
  | jq '[.[] | {image: .Image, digest: .ImageID}]'
```

## Security

The service needs access to `/var/run/docker.sock`, which grants effectively
root-level access. That is the standard Docker trade-off; the service runs as a
member of the `docker` group.

## Use in this repo

`hostinfo.enableDockerImages = true` on compute1 (Twenty, Gotenberg) and compute3
(Zammad, Elasticsearch).
