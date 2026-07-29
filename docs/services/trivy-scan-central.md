# Trivy Scan Central (Removed)

> **This service has been removed.** The `elastinix.services.trivy-scan-central` module no longer exists.
>
> Use **[Vulnerability Scan Central](vulnerability-scan-central.md)** instead — a combined service where Docker image scanning is enabled per host via `enableDockerScan = true`.

## Migration

```nix
# Before
elastinix.services.trivy-scan-central = {
  enable = true;
  hosts = [
    { name = "compute1"; url = "http://10.0.1.10:3333"; }
    { name = "compute3"; url = "http://10.0.1.12:3333"; }
  ];
};

# After — add these hosts to vulnerability-scan-central with enableDockerScan = true
elastinix.services.vulnerability-scan-central = {
  enable = true;
  hosts = [
    { name = "compute1"; url = "http://10.0.1.10:3333"; enableDockerScan = true; }
    { name = "compute2"; url = "http://10.0.1.11:3333"; }               # vulnix only
    { name = "compute3"; url = "http://10.0.1.12:3333"; enableDockerScan = true; }
  ];
};
```

See [vulnerability-scan-central.md](vulnerability-scan-central.md) for full documentation.
