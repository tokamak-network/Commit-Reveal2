## Branch Guide

This repository contains the Commit-Reveal² implementation and is organized into purpose-specific branches.

### Citation (ICBC 2025)

Suhyeon Lee and Euisin Gee, "Commit-Reveal²: Randomized Reveal Order Mitigates Last-Revealer Attacks in Commit-Reveal," ICBC 2025 — IEEE International Conference on Blockchain and Cryptocurrency, June 2025.

Note: A journal version is planned but not yet finalized.

### icbc2025

- Dedicated to the ICBC 2025 conference paper.
- Publication is finalized; no further changes are expected.
- Not subject to external audit.

### full-paper

- Dedicated to the forthcoming journal submission (full paper).
- Will remain under revision until acceptance; journal venue is not yet finalized.
- Not subject to external audit.

### service

- Main service branch under external audit.
- Acts as the integration branch used by `drb-node` for interaction.
- Stable, integration-focused changes are merged here.

### audit/main-fixes

- Working branch to resolve issues reported by the external audit.
- All fixes will be merged back into `service` after validation.

## Workflow Summary

- Research branches: `icbc2025` and `full-paper` are for the paper(s) and are excluded from audit.
- Service branches: `audit/main-fixes` is where audit findings are addressed; validated fixes will be merged into `service` for integration and operation.
