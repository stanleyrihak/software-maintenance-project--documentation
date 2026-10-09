# AI-assisted development

LLMs were used throughout the project to explain the assignment, generate code and tests, design the ML-KEM integration, write CI and monitoring configuration, and review the result.
Three tools were used:

| Tool | Used by | Main use |
|------------------|------------------------------|-----------------------------------------|
| ChatGPT (GPT-4o) | Stanislav Řihák, Roland Budzák | understanding the brief, the baseline system |
| Claude Code | Roland Budzák, Stanislav Řihák, Tom | most of the code, tests and CI, reviews |
| Codex | Tom | the first ML-KEM design, persistence and monitoring (v3.1.0) |

: AI tools used in the project.

The prompts with the AI output and the decisions are recorded in the code repository: `documentation/phases/`.

## How we worked with AI

Most work followed the same steps:

1. We described the task, and the AI proposed a plan and then the code and tests.
2. We read the proposal, ran the tests and, for larger changes, ran the system in Docker.
3. We accepted, changed or rejected the output, and recorded the decision with its reason.

## Decisions on AI output

| What the AI proposed | Decision | Why |
|------------------------------------------|----------------------|-----------------------------------------|
| the device / gateway / cloud architecture | accepted | simple and matching the brief |
| adding ML-KEM already in the first version | rejected | a plain baseline was needed first, to compare against |
| ML-KEM sessions shared by many readings (v2) | accepted, later dropped | a review found a nonce-reuse bug; the rewrite uses a new key per reading |
| `kyber-py` as the ML-KEM library | replaced | an educational, not constant-time implementation; OpenSSL is used instead |
| both ML-KEM keys written into `docker-compose.yml` | replaced | the private key was public in the repository; keys are now generated per machine |
| no Grafana, to keep the system small | reversed | monitoring was added later, but only as an optional stack |
| v3.1.0 code merged without review | corrected | a `NaN` temperature could be stored and broke reading the data |

: Main decisions on AI-generated output.

## What we learned

- **AI can quickly make a project too complex.**
  Each request added more code, and by v2.2.0 the application had grown to 3,102 lines that the team could no longer read and review with confidence.
  The rewrite brought it down to 464 lines.
- **Agents with different contexts give conflicting advice.**
  Each team member worked with their own agent, which knew only part of the project.
  The same decision could be called acceptable by one agent and a security threat by another: committing the ML-KEM keys was described as "acceptable for a course project" during the rewrite, and as a critical problem in a later review.
