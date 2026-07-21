---
# elastinix-0r1b
title: OptScale FinOps appliance service
status: completed
type: epic
priority: normal
openspec-link: openspec/changes/archive/2026-07-21-optscale-service
created_at: 2026-07-21T12:54:29Z
updated_at: 2026-07-21T13:04:39Z
---

Integrate the OptScale FinOps appliance (github:wearetechnative/optscale-nixified) as an elastinix service.

OptScale is a full appliance: ~20 native systemd services + 6 datastores (etcd, MariaDB, MongoDB, ClickHouse, RabbitMQ, MinIO) + a React UI (ngui, :4000), bootstrapped by a configurator oneshot. optscale-nixified exposes nixosModules.optscale-appliance (self-contained: wires optscaleSrc/Ngui/Venvs internally; master services.optscale.enable; x86_64 + aarch64) and overlays.default (substrate version pins).

Scope: one appliance per environment/customer on a single EC2 instance (not multi-tenant).

Deliver elastinix.services.optscale with:
- flake input optscale-nixified (nixpkgs.follows)
- the appliance nixosModule wired into the system
- secrets via agenix -> services.optscale.secrets.environmentFile (the EnvironmentFile productionization already in optscale-nixified)
- the substrate-pins overlay + allowUnfree(mongodb)/allowInsecure(minio) applied to the machine's pkgs, gated by enable
- TLS-fronted UI (traefik/nginx) with domain from tfvars
- nixos-healthchecks

Prerequisites (done, pushed to optscale-nixified main): nixosModules.optscale-appliance + overlays.default.
