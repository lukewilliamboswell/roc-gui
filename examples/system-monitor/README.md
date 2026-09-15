# System Monitor

A read-only desktop dashboard for an explicitly granted view of CPU, memory,
disk I/O, network I/O, and processes.

Sampling is owned by the host's `sysinfo` integration and runs with timer waits
through the production task route. Overall CPU is normalized across the whole
machine and represented in tenths of one percent from 0 to 1000. Per-process
CPU uses the same unit and may exceed 1000 for multi-core use. Memory and I/O
values are bytes reported by the operating-system sampler.

Every metric is structurally either `Value` or `Unavailable`; unavailable is
never displayed as measured zero. The bounded, deterministically sorted process
table exposes PID, display name, CPU, and memory only—never usernames, paths,
command lines, environment, hostnames, or machine identifiers.

Specifications use a deterministic host sampler through the identical snapshot
ABI and application state machine. They cover permission denial, unavailable
sensors, pause/resume, filtering and selection, bounded history, host-owned
counters, and a natural 500-process scaling case through the ordinary table.
