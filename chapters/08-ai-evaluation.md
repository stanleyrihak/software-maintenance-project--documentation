# AI-assisted development and critical evaluation

<!--
WRITING NOTES (not printed in the PDF)

Purpose: the course's central requirement - show that the team assessed,
validated and corrected LLM output instead of trusting it.

Include:
- How LLMs were used: tools (ChatGPT, Claude Code, Codex/GPT), who used them,
  for what; the rule that output is untrusted until verified.
- Summary table of significant AI-generated artefacts: accepted / modified /
  rejected, and why.
- 3-5 detailed cases, each: what was generated, how the problem was found,
  the fix, how it was verified, remaining risk. Candidates:
  1. AES-GCM nonce reuse after a lost response in the v2 session design (S1).
  2. NaN readings breaking GET /data (v2.2.0, again in v3.0.0, and on the
     legacy path in v3.1.0 where SQLite made it permanent).
  3. ML-KEM private key committed to a public repository (v3.0.0).
  4. kyber-py chosen as "existing implementation" although it is educational.
  5. Replay within the timestamp window; forged readings with the public key.
  6. The rewrite itself as a maintainability decision.
- Where the full prompt records are (phase docs, docs/ai/, docs/archive/).

Sources: documentation/phases/*.md, docs/ai/prompts/, docs/archive/ in the
code repo; commit history.
-->
