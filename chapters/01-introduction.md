# Introduction

Most data on the internet today is protected by key exchange based on RSA or elliptic curves.
A capable quantum computer could break both of them.
An attacker does not need to wait for that computer: traffic recorded today can be stored and decrypted later ("harvest now, decrypt later").
Data with a long shelf life such as industrial measurements, health data, infrastructure telemetry is therefore already at risk.
NIST standardised the first post-quantum key-encapsulation mechanism, ML-KEM, in 2024 [@fips203].

Legacy devices make the migration hard.
A sensor in the field often cannot be updated: its firmware is fixed, its hardware too small, or nobody is responsible for it anymore.
The realistic approach is therefore to leave the device unchanged and add protection around it in a form of gateway that connects it to the cloud.

The aim of this project was to create (with the help of AI models) a small legacy system and modernize it for post-quantum era.
The system has three parts: a simulated legacy temperature sensor, an edge gateway that receives its readings and forwards them, and a cloud service that stores them.
The task was not to implement ML-KEM ourselves, but to integrate an existing implementation safely into this legacy environment, and to build, test, deploy and monitor the result.
