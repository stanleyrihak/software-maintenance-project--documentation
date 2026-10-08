# Introduction

## The task and why it matters

The aim of this project was to create (with the help of AI models) a small legacy system and modernize it for post-quantum era.
The system has three parts: a simulated legacy temperature sensor, an edge gateway that receives its readings and forwards them, and a cloud service that stores them.
The starting version worked, but had limited tests, no automated pipeline, little monitoring and no protection of the data it transferred.
The task was not to implement ML-KEM ourselves, but to integrate an existing implementation safely into this legacy environment, and to build, test, deploy and monitor the result.

Most data on the internet today is protected by key exchange based on RSA or elliptic curves.
A capable quantum computer could break both of them.
An attacker does not need to wait for that computer: traffic recorded today can be stored and decrypted later ("harvest now, decrypt later").
Data with a long shelf life such as industrial measurements, health data, infrastructure telemetry is therefore already at risk.
NIST standardised the first post-quantum key-encapsulation mechanism, ML-KEM, in 2024 [@fips203].

Legacy devices make the migration hard.
A sensor in the field often cannot be updated: its firmware is fixed, its hardware too small, or nobody is responsible for it anymore.
The realistic approach is therefore to leave the device unchanged and add protection around it in a form of gateway that connects it to the cloud.

## System overview

![The final system: components and communication paths.](figures/architecture.pdf){width=72%}

The **device** simulates a DS18B20 temperature sensor and sends a reading to the gateway every five seconds, in plaintext, exactly as the legacy device would.
The **gateway** validates the reading, keeps track of each sensor's state, encrypts the message, and forwards it to the **cloud**, which decrypts it, validates it again and stores it in a database.
The plaintext path into the cloud still exists for clients that have not been migrated, but it is closed unless explicitly enabled.
The gateway and the cloud expose metrics via endpoints, which an optional monitoring tools collect, show in a dashboard and use to raise alerts.

## How to read this document

Chapter 2 describes how the system works.
The chapters after it follow the course brief's list of required work, one chapter per item:

| Course requirement | Where |
|------------------------------|------------------------------------------|
| Baseline analysis | 3 |
| ML-KEM integration, migration and fallback | 4 |
| Operations: build, test, deployment, health, logs, metrics | 5 |
| AI-assisted development | 6 |
| Critical evaluation and maintenance | 7 |
| Final evaluation | 8 |

: Where each course requirement is covered.
