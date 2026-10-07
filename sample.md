---
title: ML-KEM Legacy Modernization
subtitle: Technical documentation
author:
  - Stanislav Řihák
  - Roland Budzák
  - Tom (yyy-tom)
  - Tiago
  - Francisca
institution: University of Oulu
course: Software Development, Maintenance & Operations (2026)
version: "v3.2.0 (sample layout)"
repository: https://github.com/Rolko6/Software-Development-and-Maintenance-Project
date: October 2026
toc: true
toc-depth: 2
---

# Introduction

This is a **layout sample**, not the real documentation. It shows how the
final PDF will look: title page, table of contents, numbered headings, a
diagram, a table, code blocks and inline code such as `POST /data/secure`.

The system consists of a simulated legacy device, an edge gateway and a cloud
service. The gateway protects readings with ML-KEM-768 key establishment and
AES-256-GCM before forwarding them to the cloud.

# Architecture

![Components and communication paths.](diagrams/architecture.pdf){width=55%}

## Components

| Component | Port | Responsibility |
|---|---|---|
| Device | — | Simulates a DS18B20 sensor; sends a reading every 5 s |
| Gateway | 8000 | Validates readings, encrypts them, forwards them to the cloud |
| Cloud | 8001 | Decrypts, validates and stores readings in SQLite |

: Services and their responsibilities.

## Protecting one reading

The gateway encapsulates a fresh shared secret with the cloud's public key and
uses it as the AES-256-GCM key:

```python
shared_secret, kem_ciphertext = encapsulate(CLOUD_PUBLIC_KEY)
nonce, ciphertext = encrypt_payload(shared_secret, plaintext)
```

> A solution that runs successfully is not necessarily correct, secure,
> maintainable, or suitable for operations. (Course brief)

# Evaluation

1. Every claim is backed by a test, a command or a measurement.
2. Known limitations are listed explicitly.

Example of a results table:

| Case | Expected | Actual | Stored |
|---|---|---|---|
| Tampered ciphertext | 400 | 400 | no |
| NaN on legacy `/data` | 422 | 422 | no |
| Replay within 30 s | 409 | 200 | yes (known limitation) |

: Security checks against the running containers.
