# Reference measurements

The project does not promise a universal RAM, process-count, CPU, frame-rate, or battery-life improvement. Workloads, Windows builds, drivers, hardware, power modes, display brightness, and selected optional profiles all change the result.

## Observational reference capture

The website reports two aggregate values from one 64 GB Windows 11 reference machine. Each value is the average of five one-second Windows performance-counter samples.

| Metric | Initial capture | Final capture | Observed change |
|---|---:|---:|---:|
| Running processes | 270 | 186 | 84 fewer (31.1%) |
| Available memory | 50,138 MiB (49.0 GiB) | 55,271 MiB (54.0 GiB) | 5,133 MiB (5.0 GiB) more |

The initial capture was recorded on August 1, 2026 before the workstation work began. The final capture was recorded on August 2, 2026 after cleanup work and before the final shell pass. These were not controlled A/B runs: foreground and background workloads differed, and several changes preceded the final capture. The values are therefore an honest report of one observed result, not proof that the standard installer alone caused the difference.

## Battery life

No controlled, repeated before-and-after battery rundown has been completed. The project therefore publishes no battery-life improvement percentage.

The website includes a calculator based on:

```text
estimated runtime (hours) = full-charge battery capacity (Wh) / average power draw (W)
```

That is an estimate from user-supplied measurements. It does not account for changing workloads, display brightness, battery aging, conversion losses, or power-mode transitions.

## How to measure your system

Use the repository's baseline capture before making changes, keep the workload and power conditions consistent, restart when required, and repeat the same capture afterward. Keep raw reports private: they can contain account, device, software, and hardware details.
