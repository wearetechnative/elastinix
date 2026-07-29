# Vulnix Scan Central (Removed)

> **This service has been removed.** The `elastinix.services.vulnix-scan-central` module no longer exists.
>
> Use **[Vulnerability Scan Central](vulnerability-scan-central.md)** instead — a combined service that runs both vulnix and trivy from a single configuration.

## Migration

```nix
# Before
elastinix.services.vulnix-scan-central = {
  enable = true;
  hosts = [
    { name = "compute1"; url = "http://10.0.1.10:3333"; }
  ];
};

# After
elastinix.services.vulnerability-scan-central = {
  enable = true;
  hosts = [
    { name = "compute1"; url = "http://10.0.1.10:3333"; }
    # add enableDockerScan = true for hosts that also run Docker
  ];
};
```

See [vulnerability-scan-central.md](vulnerability-scan-central.md) for full documentation.
