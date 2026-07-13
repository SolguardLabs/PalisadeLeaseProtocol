# Security Policy

## Supported Version

This repository is maintained as a standalone protocol implementation. The supported version is the
current local checkout.

## Reporting

Submit a concise security report with:

- Impact and affected assets.
- Root cause with code references.
- Minimal reproduction steps.
- Expected behavior versus observed behavior.
- Suggested remediation.

Do not disclose unresolved findings through public issues or comments.

## Scope

In scope:

- Lease listing, opening, renewal, settlement, and cancellation flows.
- Reward accrual, checkpointing, and beneficiary attribution.
- Pricing, utilization signals, and fee accounting.
- Vault custody and productive-position token lifecycle.
- Operator views and solvency reporting.

Out of scope:

- Dependency supply-chain issues.
- Local workstation configuration.
- Denial-of-service through intentionally huge test inputs.
- Cosmetic formatting issues that do not alter security assumptions.
