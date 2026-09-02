# Dual-pass STT for low-latency voice control

Use this pattern when a user wants faster conversational response without replacing an already validated high-accuracy model.

## Contract

- The fast model is **provisional only**.
- The previously validated model remains **authoritative**. Never silently downgrade it for speed.
- Start useful reversible work from the provisional transcript.
- Run the authoritative pass in a tracked background task.
- Equivalent results stay silent: no duplicate echo, steer, or extra turn.
- Material differences trigger one append-only correction; never mutate prior history.

## Material-difference policy

Normalize Unicode, spacing, punctuation, casing, and common fillers first. Treat these as material even when generic string similarity is high:

- negation or polarity;
- quantities, currency, dates, times, versions, percentages, or units;
- names, handles, URLs, paths, account IDs, environments (`production` vs `staging`);
- requested action (`send`, `save`, `delete`, `approve`, `cancel`, etc.);
- safety-critical facts.

Use a cheap deterministic comparator first. Ambiguous middle cases may use a narrowly prompted semantic adjudicator, but it must compare only the two transcripts and must not invent a third wording.

## Gateway integration invariants

- Centralize fresh, busy-steer, interrupt-monitor, and pending-drain voice handling on one event-level STT cache.
- Schedule the authoritative pass at most once per media snapshot.
- Media merge must invalidate/cancel the stale verifier snapshot while preserving the transcript-echo count.
- Track verifier tasks in the gateway background-task set.
- Keep correction delivery session- and generation-scoped; drop stale results after reset/session replacement.
- Active correction should append at a role-safe tool-result boundary. If no active injection point remains, queue one internal correction turn.
- Do not use ordinary background `delegate_task` completion for silent-equivalence verification: it always surfaces a completion turn.

## Side-effect safety

If provisional text can reach tools before verification completes, a just-in-time gate is required for effect-capable tools:

- known read-only tools proceed immediately;
- an effect-capable tool waits for the shared verification result;
- matched verification releases it;
- discrepancy, failure, timeout, or stale ownership blocks it fail-closed;
- unknown, terminal, browser-interaction, file-write, messaging, MCP-without-readOnlyHint, and external-service tools default to effect-capable.

An existing fail-closed `pre_tool_call` plugin hook is preferable to a parallel dispatcher. Do not rely on approval prompts alone because permissive/yolo modes may bypass approval while a hook block remains authoritative.

## Model and language details

- A single global local-model cache will thrash when alternating fast and authoritative models. Use a bounded cache keyed by model when latency matters; otherwise measure cold reload cost honestly.
- Allow the fast pass to override language independently. A global language hint validated for the authoritative model can cause a smaller model to translate or misdecode.
- Preserve user-configured prompts and proper-noun hints for both passes.

## Tests

At minimum verify:

1. fast transcript begins before authoritative completion;
2. equivalent transcripts cause zero correction calls;
3. negation/quantity/entity/action differences cause exactly one correction;
4. monitor → interrupt → drain schedules one authoritative pass;
5. media merge invalidates stale verification;
6. late/stale corrections cannot cross sessions or generations;
7. read-only tools proceed while effect-capable tools wait;
8. discrepancy/failure/timeout blocks effect-capable tools;
9. prompt role alternation and cached history stay unchanged;
10. a real voice fixture exercises both matched and intentionally wrong-provisional correction paths.

## Communication during implementation

A live-chat latency fix can require several minutes of coding and model benchmarks. Send a short progress update before a long implementation stretch; do not leave the user wondering whether voice handling or the agent itself stalled.