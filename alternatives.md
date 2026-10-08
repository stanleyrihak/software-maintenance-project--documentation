---
# Standalone build:  ./build.sh alternatives.md  ->  alternatives.pdf
# To include it in the documentation later: delete this YAML block, move the
# file into chapters/ and add it to chapters.txt (e.g. after the ML-KEM chapter).
title: Alternative approaches
subtitle: Draft chapter for the technical documentation
author:
  - Stanislav Řihák
  - Roland Budzák
course: Software Development, Maintenance & Operations (2026)
date: October 2026
toc: true
toc-depth: 2
reference-section-title: References
---

# Alternative approaches

The task — protect a legacy edge–cloud system against quantum-capable attackers with ML-KEM — has more than one reasonable solution.
This chapter describes the main alternatives to the approach taken in this project, explains the concepts behind each, and sketches how each would be implemented in this system.
It ends with a comparison and the reasons for our choice.

The alternatives differ along five largely independent questions:

1. **Where** is ML-KEM applied: inside the application, in the transport layer (TLS), in a separate proxy, at the network level, or in a standard message format?
2. **Which** key exchange: ML-KEM alone, or combined with a classical algorithm (hybrid)?
3. **Who** is the sender: is the gateway authenticated, and how?
4. **How** do old and new components coexist during the migration?
5. **With what** technology: protocol, library, deployment platform.

## Where ML-KEM is applied

### Application-level encryption (the approach chosen)

**Concept.** The application itself performs the cryptography.
Before sending a reading, the gateway's code encapsulates a fresh shared secret with the cloud's ML-KEM public key, encrypts the reading with AES-256-GCM under that secret, and sends the KEM ciphertext, nonce and ciphertext in a JSON body.
The transport underneath (plain HTTP) knows nothing about it.

**In this project.** `gateway/app/crypto.py` and `cloud/app/crypto.py`, about 35 lines in total, using ML-KEM-768 and AES-256-GCM from the `cryptography` package.
The earlier v2 used the same layer with sessions instead of per-message keys.

**Strengths and weaknesses.** Every cryptographic step is visible, testable and observable in the application (the rejection metrics by reason exist because the application sees each failure).
The cost is a custom protocol: properties that mature protocols provide — forward secrecy, peer authentication, negotiation, replay protection — have to be designed by hand, and that is where both versions of this project had their security problems.

### TLS 1.3 with a hybrid post-quantum key exchange

**Concept.** TLS is the protocol behind HTTPS.
A TLS 1.3 connection starts with a handshake in which client and server agree on keys, then all traffic is protected by the *record layer* with an AEAD cipher (AES-GCM or ChaCha20-Poly1305).
The key agreement uses *ephemeral* keys — new for every connection and thrown away afterwards — which gives **forward secrecy**: stealing a server's long-term key later does not decrypt recorded sessions.
The server proves its identity with a certificate.

Since 2024, TLS implementations support a **hybrid key exchange** named `X25519MLKEM768`: the client sends both an X25519 public key and an ML-KEM-768 encapsulation key; the server answers with its X25519 share and an ML-KEM ciphertext; and the two resulting secrets are combined into the TLS key schedule.
Major browsers and content-delivery networks use it by default.
With OpenSSL 3.5 or later, it is offered by default in TLS 1.3.

**How it would be implemented here.** The JSON envelope and both `crypto.py` modules would disappear; the gateway would simply post the reading to `https://cloud:8443/data`.

1. *Certificates.* Create a small private certificate authority for the test environment and issue a certificate for the cloud (and, for mutual TLS, one for the gateway):

   ```sh
   openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
     -keyout ca.key -out ca.crt -days 365 -subj "/CN=project-ca"
   openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
     -keyout cloud.key -out cloud.csr -subj "/CN=cloud"
   openssl x509 -req -in cloud.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
     -out cloud.crt -days 90 -extfile <(printf "subjectAltName=DNS:cloud")
   ```

2. *Server side.* Either let uvicorn serve TLS directly, relying on the OpenSSL that Python is linked against:

   ```sh
   uvicorn app.main:app --host 0.0.0.0 --port 8443 \
     --ssl-certfile cloud.crt --ssl-keyfile cloud.key
   ```

   or — more controllable — put a TLS-terminating web server in front of the cloud and pin the key-exchange group:

   ```nginx
   server {
       listen 8443 ssl;
       ssl_protocols       TLSv1.3;
       ssl_ecdh_curve      X25519MLKEM768;     # accept only the hybrid group
       ssl_certificate     /certs/cloud.crt;
       ssl_certificate_key /certs/cloud.key;
       ssl_client_certificate /certs/ca.crt;   # mutual TLS (optional)
       ssl_verify_client   on;
       location / { proxy_pass http://cloud:8001; }
   }
   ```

3. *Client side.* The gateway posts over HTTPS, trusting the project CA and, for mutual TLS, presenting its own certificate:

   ```python
   requests.post("https://cloud:8443/data", json=reading,
                 verify="/certs/ca.crt",
                 cert=("/certs/gateway.crt", "/certs/gateway.key"))
   ```

   The client's OpenSSL must support the hybrid group (OpenSSL 3.5+ in the gateway image).

4. *Verification.* Check that the hybrid group was negotiated and that a classical-only client is refused:

   ```sh
   openssl s_client -connect cloud:8443 -groups X25519MLKEM768 </dev/null \
     | grep "Negotiated TLS1.3 group"          # expect X25519MLKEM768
   openssl s_client -connect cloud:8443 -groups X25519 </dev/null  # must fail
   ```

   A `cloud_tls_handshakes_total{group=...}` metric is not available out of the box; post-quantum observability would come from the proxy's access log (nginx can log `$ssl_curve`) rather than from application metrics.

**Strengths and weaknesses.** No custom cryptographic code; forward secrecy; replay protection and integrity of the whole connection, including the replies (which the chosen design leaves unauthenticated); certificate-based server authentication and, with mutual TLS, gateway authentication; a protocol analysed for years.
The trade-offs: certificate management becomes an operational task; the certificates themselves still use classical signatures (acceptable, because authentication only has to resist attacks *at connection time*, unlike confidentiality, which must survive "harvest now, decrypt later"); and ML-KEM becomes nearly invisible — a single configuration line — which makes the integration harder to demonstrate and to observe.

### Reverse proxy or sidecar

**Concept.** A *sidecar* is a helper container that runs next to an application and takes over a cross-cutting concern — here, encryption.
The legacy application keeps speaking plain HTTP, but only to its own local proxy; the proxies talk post-quantum TLS to each other.
This is the classic way to modernise software that cannot or should not be changed, and it is how *service meshes* (Istio, Linkerd) encrypt traffic between services.

```
gateway app --http--> gateway-proxy ==PQ-TLS==> cloud-proxy --http--> cloud app
   (unchanged)          (stunnel/Envoy)          (nginx/Envoy)          (unchanged)
```

**How it would be implemented here.** Two extra services in `docker-compose.yml`: the cloud-side proxy with the nginx configuration from the previous section, and a gateway-side proxy that accepts plaintext locally and opens the TLS connection, for example stunnel in client mode:

```ini
; stunnel.conf (gateway side)
[cloud]
client  = yes
accept  = 127.0.0.1:9001          ; the gateway posts to http://127.0.0.1:9001/data
connect = cloud-proxy:8443
CAfile  = /certs/ca.crt
verifyChain = yes
curves  = X25519MLKEM768          ; group list passed to OpenSSL (3.5+)
```

The gateway's only change is `CLOUD_URL=http://127.0.0.1:9001/data` — the original v1 endpoint.
Even the legacy plaintext `POST /data` of the cloud could stay as it is, because only the proxy can reach it.
Envoy would be the choice for richer features (retries, per-connection metrics, automatic certificate rotation).

**Strengths and weaknesses.** Zero changes to the application code — the strongest answer to "legacy software that cannot be modified"; security code and application code can be updated independently; one proxy can protect several services.
The cost is another component to configure, monitor and secure, and the short hop between application and proxy is still plaintext, so the two must share a trusted host or network namespace.

### VPN or encrypted tunnel at network level

**Concept.** Instead of protecting individual connections, protect the whole network path.
A VPN creates an encrypted tunnel between two machines or sites; every packet between them — whatever the protocol — is encrypted.
Two families have post-quantum options:

- **WireGuard** is a small, modern VPN whose handshake uses X25519.
  On its own it is not post-quantum, but it accepts an optional pre-shared symmetric key mixed into the handshake.
  **Rosenpass** runs a separate post-quantum key exchange (based on Classic McEliece and ML-KEM) and feeds a fresh pre-shared key into WireGuard every couple of minutes, making the tunnel post-quantum secure without changing WireGuard.
- **IPsec** with IKEv2 can perform *additional key exchanges* on top of the classical one (RFC 9370), and implementations such as strongSwan 6 support ML-KEM for them.

**How it would be implemented here.** Run a WireGuard interface on the host (or in a privileged container) at the gateway site and at the cloud site, with Rosenpass on both ends; route the gateway's traffic to the cloud through the tunnel.
The applications would then talk plain HTTP over a private tunnel address.
Docker makes this harder than the other options: the containers need `NET_ADMIN` capabilities or the tunnel must live on the host.

**Strengths and weaknesses.** Protects all traffic between the sites at once, including protocols nobody remembered; completely transparent to the applications; well suited when a whole legacy site has to be connected.
But it needs privileged network configuration, authenticates *machines* rather than services, gives no visibility into individual readings, and is the heaviest option to run in a course test environment.

### A standard message format: HPKE

**Concept.** Hybrid Public Key Encryption (HPKE, RFC 9180) is a standard recipe for exactly what the chosen design does by hand: encrypt a message to a recipient's public key using a KEM, a key-derivation function and an AEAD.
It defines how the shared secret is turned into keys (with context binding), how the encapsulated key is attached to the ciphertext, and several modes:

- *base* mode — anyone with the public key can encrypt (like our design);
- *PSK* and *auth* modes — additionally prove that the sender holds a pre-shared key or a private key, which is what our design lacks.

Post-quantum KEMs for HPKE are being standardised, including ML-KEM-768 and **X-Wing**, a hybrid KEM that combines X25519 and ML-KEM-768 into one.

**How it would be implemented here.** Replace the hand-made envelope with an HPKE library call: the gateway calls `seal(recipient_public_key, info, aad, plaintext)` and sends the returned `(enc, ciphertext)`; the cloud calls `open(...)`.
The `info` string would bind the key to this protocol and version, and the PSK mode would authenticate the gateway.
Because HPKE is transport-independent, the same envelope would work over HTTP, MQTT, a message queue or a file.
Library support for the post-quantum KEM identifiers is still maturing, which is the main practical obstacle today.

**Strengths and weaknesses.** Keeps the per-message model and the visibility of our design while replacing self-designed details with a reviewed standard, including key derivation and optional sender authentication.
It still has no forward secrecy (the recipient key is long-term) and needs its own replay protection.

## Pure post-quantum or hybrid key exchange

**Concept.** ML-KEM was standardised in 2024; classical X25519 has a decade of deployment and analysis behind it.
A *hybrid* key exchange runs both and combines the two secrets, so the result is secure as long as **either** algorithm remains unbroken: a quantum computer would have to break ML-KEM's lattice problem, and an unexpected flaw in ML-KEM would still leave X25519.
National security agencies (for example Germany's BSI and France's ANSSI) recommend hybrid schemes for the transition period; TLS and HPKE (X-Wing) use them.

**How it would be implemented here.** The cloud would publish an X25519 public key next to its ML-KEM key.
Per message, the gateway would create an ephemeral X25519 key, compute both secrets and combine them with a key-derivation function that also binds the public values, so neither secret can be swapped out:

```python
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives import hashes

ss_pq, ct_pq = mlkem_public.encapsulate()                 # post-quantum part
eph = X25519PrivateKey.generate()
ss_ec = eph.exchange(cloud_x25519_public)                 # classical part
eph_pub = eph.public_key().public_bytes_raw()

aes_key = HKDF(hashes.SHA256(), 32, salt=None,
               info=b"mlkem-gw-cloud-v2|hybrid|" + ct_pq + eph_pub
               ).derive(ss_pq + ss_ec)                     # both secrets → one key
# send ct_pq and eph_pub with the envelope; the cloud mirrors the computation
```

**Strengths and weaknesses.** Protection against both a future quantum computer and a possible weakness in the new algorithm, at the cost of 32 more bytes and one X25519 operation per message — negligible here.
It adds a second key pair to manage and makes the design slightly more complex.

## Authenticating the sender

The chosen design encrypts readings but does not prove who sent them.
The options, from the simplest:

- **Pre-shared key with HMAC** (as in v2).
  Gateway and cloud share a secret; the gateway computes `HMAC-SHA256(psk, envelope)` and sends it along; the cloud recomputes and compares in constant time.
  In v3 this would be about 20 lines and one more value in `.env`.
  Its weakness: every holder of the PSK can impersonate every other, and the PSK must be distributed securely.
- **Mutual TLS.** Both sides present certificates during the TLS handshake (see above).
  Identity is tied to a certificate that can be revoked, and nothing changes in the application code.
- **Post-quantum signatures: ML-DSA (FIPS 204).** The gateway signs each envelope (or each session) with its ML-DSA private key; the cloud verifies with the gateway's public key.
  This gives post-quantum *authentication* in addition to post-quantum confidentiality.
  The cost is size: an ML-DSA-65 signature is about 3.3 KB and its public key about 2 KB, more than the reading itself.
  Library support exists in liboqs and is arriving in mainstream libraries.
- **At the device.** The legacy device itself cannot be changed, so it cannot authenticate.
  The realistic measures are network ones: keep the device-to-gateway link on an isolated local network, allow only known addresses, and treat the gateway as the trust boundary.

## Migration strategies

- **Parallel endpoints with a switch** (chosen, v3.1 onward).
  The cloud keeps the old plaintext endpoint, closed by default and opened only for not-yet-migrated gateways; a metric shows when it can be closed.
- **Mode flags** (v2).
  A single setting `off` / `enabled` / `required` on both sides moves the whole system through the stages, including back to `off` for a rollback.
  More flexible, but every combination has to be tested.
- **Protocol negotiation.** The client announces the versions it supports (for example in a header or a versioned path such as `/v2/data`) and the server answers with the best common one.
  This is how TLS itself migrates.
- **Strangler pattern.** A new component (here: the gateway or a proxy) is put in front of the old one and takes over its traffic step by step until the old path can be removed.
- **Canary and blue/green rollout.** New gateway versions are deployed to a few sites first (canary), or run side by side with the old version and switched over at once (blue/green); versioned images make both, and the rollback, possible.

## Technology choices

**Cryptographic libraries.**

| Library | Notes |
|--------------------------|---------------------------------------------------------|
| `cryptography` (OpenSSL) | chosen; maintained, constant-time, already used for AES-GCM |
| liboqs / `oqs-python` (Open Quantum Safe) | broad set of post-quantum algorithms including ML-DSA; research-oriented |
| Go `crypto/mlkem` | part of Go's standard library since Go 1.24 |
| Bouncy Castle | Java and C#; includes ML-KEM and ML-DSA |
| PQClean / pqm4 | portable C and microcontroller implementations, for devices that *can* be updated |
| `kyber-py` | educational, not constant-time; used briefly in v3.0.0 and replaced |

: Possible ML-KEM implementations.

**Communication protocol.** HTTP with JSON (chosen) is simple and easy to test.
Typical IoT systems use **MQTT**, a publish/subscribe protocol in which devices and gateways publish readings to a broker (for example Mosquitto) that consumers subscribe to; the broker connection can use the same post-quantum TLS.
For very constrained devices, **CoAP** with OSCORE offers a compact alternative.

**Reliability.** A gateway could *store and forward*: write each reading to a local queue or database first and deliver it when the cloud is reachable, so that no reading is lost during an outage — something neither version of this project does.

**Deployment and monitoring.** Docker Compose (chosen) suits a single host; Kubernetes (locally with kind or minikube) would add rolling updates, health-based restarts and a natural place for sidecars or a service mesh.
OpenTelemetry would add traces through the whole device → gateway → cloud path, next to Prometheus metrics.

## Comparison

| | Application-level (chosen) | TLS 1.3 hybrid | Proxy / sidecar | VPN tunnel | HPKE |
|---|---|---|---|---|---|
| Application code changed | yes | little | **none** | **none** | yes |
| Post-quantum confidentiality | yes | yes | yes | yes | yes |
| Forward secrecy | no | **yes** | **yes** | **yes** | no |
| Gateway authentication | no (could add HMAC) | with mutual TLS | with mutual TLS | per machine | PSK/auth mode |
| Replies protected | no | **yes** | **yes** | **yes** | no |
| Standardised protocol | no (own design) | **yes** | **yes** | **yes** | **yes** |
| ML-KEM visible and observable in the application | **yes** | barely | no | no | yes |
| Operational effort | low | medium (certificates) | medium (extra services) | high (privileged networking) | low |

: Comparison of the approaches.

## Why application-level encryption was chosen

The course asks for ML-KEM to be *integrated* into a legacy software environment and for the integration to be evaluated critically.
Application-level encryption makes every step of that integration explicit: the key encapsulation, the symmetric encryption, the failure modes and their metrics can all be read in a few dozen lines, tested in isolation and observed in production.
It also needs no infrastructure beyond the existing services.
These were the deciding reasons.

The price is that the protocol around ML-KEM is our own, without forward secrecy, sender authentication or protected replies — gaps that the alternatives above close by design.
For a production system we would therefore recommend **TLS 1.3 with the hybrid `X25519MLKEM768` key exchange and mutual TLS, terminated in a sidecar proxy**: no custom cryptography, no change to the legacy applications, and post-quantum confidentiality with forward secrecy and authenticated peers.
The project's application-level design remains valuable as the transparent, testable model of what that configuration does internally.
