---
# elastinix-pg6e
title: hostinfo — enableDockerImages optie en docker-inventory service
status: completed
type: task
priority: normal
created_at: 2026-07-27T00:00:00Z
updated_at: 2026-07-27T00:00:00Z
parent: elastinix-p9gu
---

Voeg `enableDockerImages` optie toe aan de hostinfo service zodat de centrale scanner de draaiende Docker images per host kan ophalen via HTTP.

## Wat

Nieuwe `elastinix.services.hostinfo.enableDockerImages` optie die:

1. Een systemd service `elastinix-docker-inventory` aanmaakt die de Docker socket bevraagt en de resulterende lijst schrijft naar `/var/lib/docker-inventory/images.json`
2. Een systemd timer (dagelijks) die de service triggert
3. Via hostinfo een symlink maakt: `/var/lib/hostinfo/docker-images.json` → `/var/lib/docker-inventory/images.json`

## docker-images.json formaat

```json
[
  {"image": "twentyhq/twenty-server", "tag": "v0.32.0", "digest": "sha256:abc..."},
  {"image": "gotenberg/gotenberg",    "tag": "8.2",     "digest": "sha256:def..."}
]
```

Gegenereerd via Docker socket API:
```bash
curl --unix-socket /var/run/docker.sock http://localhost/containers/json \
  | jq '[.[] | {image: .Image, digest: .ImageID}]'
```

## Beveiliging

De service heeft toegang tot `/var/run/docker.sock` nodig. Dit geeft effectief root-niveau toegang — dit is de standaard Docker trade-off. De service draait als lid van de `docker` group.

## Gebruik in deze repo

`hostinfo.enableDockerImages = true` op compute1 (Twenty, Gotenberg) en compute3 (Zammad, Elasticsearch).
