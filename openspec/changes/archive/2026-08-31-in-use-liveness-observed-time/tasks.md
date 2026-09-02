## 1. Sampler: accumulate observed time

- [x] 1.1 Accumulate `observedWindowSeconds` in the runtime document, adding the gap since the previous sample when within the configured multiple of the interval, verified across three consecutive samples
- [x] 1.2 Add a single interval instead when the gap exceeds that multiple, verified by backdating the previous sample by several hours
- [x] 1.3 Start the accumulator at one interval when no previous sample exists, verified on a fresh state file
- [x] 1.4 Add an option for the gap multiple with a documented default of three, verified by building with a non-default value
- [x] 1.5 Verify a document written before the field existed gains it without losing accumulated in-use or socket history

## 2. Liveness guard on observed time

- [x] 2.1 Change the normalizer's guard to compare the sample count against `observedWindowSeconds`, verified against a fixture reproducing compute5-prod where elapsed fails and observed passes
- [x] 2.2 Fall back to the elapsed window when the field is absent, verified against a bundle predating the field
- [x] 2.3 Verify a host whose sampler stopped while the host ran is still rejected, by backdating `lastSample` well beyond the interval
- [x] 2.4 Apply the identical change to the Prometheus exporter
- [x] 2.5 Verify the exporter's `inuse` labels match the bundle's values host for host on the same input

## 3. Integration and documentation

- [x] 3.1 Build the `nixos-system` toplevel for a scanner host and a scanned host and verify evaluation succeeds
- [x] 3.2 Confirm the accumulated window tracks real elapsed time between samples — verified by controlled backdating on live `/proc` data (870s gap credited 893s, 890s credited 890s), not by wall-clock waiting
- [x] 3.3 Document the observed window and the gap multiple in `docs/services/hostinfo.md`
- [x] 3.4 Document the coverage denominator in `docs/services/vulnerability-scan-central.md` and the exporter docs
- [x] 3.5 Add a CHANGELOG entry noting that compute5-prod's findings become assessable and that the movement is not remediation
- [x] 3.6 Hand the count movement to `elastinix-e79k`

## 4. Co-period numerator, found on deploy

- [x] 4.1 Count `samplesInObservedWindow` alongside the window credit in the sampler and project it into `inuse.json`, verified in the emitted document
- [x] 4.2 Use the observed window only together with the in-window count, falling back to elapsed time and the lifetime count otherwise, verified against the real post-deploy state of compute1-prod and compute2-prod
- [x] 4.3 Verify a host with 825 lifetime samples and a 321-second observed window is no longer judged on that pairing
- [x] 4.4 Verify an intermittent sampler is still rejected: 50 samples in a 44.8 hour observed window reports `unknown`
- [x] 4.5 Verify a healthy host passes: 343 samples in a 44.8 hour observed window
- [x] 4.6 Apply the identical change to the exporter and confirm label-for-label agreement with the bundle on the intermittent case
- [x] 4.7 Verify both toplevels build

## 5. Paired initialisation, found on the second deploy

- [x] 5.1 Initialise the observed window and the in-window count together, so a window carried over from a document predating the count is reset with it, verified against the real post-deploy state of all three hosts
- [x] 5.2 Credit a single interval on the first sample after the reset instead of the gap back to the pre-upgrade sample, verified by confirming the coverage check passes on that sample rather than reading it as a lapse
- [x] 5.3 Verify the lifetime sample count and the accumulated in-use and socket history survive the reset
- [x] 5.4 Verify the guard retains its power after the change: healthy 300s sampling passes, 900s sampling is rejected, and an 8.5 hour host stop passes
- [x] 5.5 Version the window accounting with `observedWindowEpoch` and reset both fields on a mismatch, verified against the real post-redeploy state of all three hosts where an absence check could not fire and an invariant check could not detect two of them
- [x] 5.6 Verify the marker does not re-fire once current, so accumulation continues across ordinary samples
