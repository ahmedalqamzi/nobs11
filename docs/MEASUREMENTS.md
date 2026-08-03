# Reference measurements

NoBS11 does not promise a universal RAM, process-count, CPU, frame-rate, or battery-life improvement. Windows builds, drivers, hardware utilities, active workloads, power modes, display brightness, and the selected profile all change the result.

## What was observed

The owner observed idle memory use fall from approximately **27–28 GB** before the workstation cleanup to approximately **7 GB** after the final configuration, restart, and clean-idle check on one 64 GB Windows 11 laptop. That is roughly 74–75% less idle memory use on this one machine.

The ~7 GB value was read from Task Manager after the final clean restart. It was not saved as a raw five-sample performance-counter capture, so the website labels it as an owner-observed value rather than presenting it as a lab measurement.

## Retained counter snapshots

Two earlier snapshots used five one-second Windows performance-counter samples per value:

| Metric | Initial snapshot | Later snapshot | Observed change |
|---|---:|---:|---:|
| Running processes | 384 | 186 | 198 fewer (51.6%) |
| Available memory | 36,757 MiB (35.9 GiB) | 55,271 MiB (54.0 GiB) | 18,514 MiB (18.1 GiB) more |

On the nominal 64 GB reference system, those available-memory samples are consistent with roughly 27–28 GiB used initially and roughly 10 GiB used in the later retained snapshot. The owner-observed ~7 GB result came after the remaining cleanup and a clean restart.

The initial and later snapshots were recorded on August 1–2, 2026. These were not controlled A/B runs: foreground and background workloads differed, several changes happened between captures, and the full reference configuration is more aggressive than the Standard or Lean installer profiles. The values are an honest report of one machine's result, not proof that every system or any one tweak will reproduce it.

## Battery life and gaming performance

No controlled, repeated before-and-after battery rundown or frame-time benchmark has been completed. NoBS11 therefore publishes no battery-life, average-FPS, 1% low, latency, or power-draw improvement percentage.

Lower background activity can reduce idle work, but the size of any battery or gaming benefit must be measured on the target machine. A credible battery comparison keeps brightness, power mode, radios, workload, battery state, test duration, and ambient conditions consistent across repeated runs.

## How to measure your system

1. Restart, wait for startup activity to settle, and keep the same foreground apps closed.
2. Capture a baseline before applying a profile.
3. Apply the selected profile and restart when requested.
4. Repeat the same capture under the same power and workload conditions.
5. Compare medians across multiple runs rather than choosing the best result.

Keep raw reports private: they can contain account, device, software, and hardware details.
