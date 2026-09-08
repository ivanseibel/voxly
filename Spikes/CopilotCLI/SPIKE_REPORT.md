# Copilot CLI provider spike

Status: no-go. This is not a shipping integration and it does not alter Voxly's production dictation path.

## Scope and boundary

- Whisper remains local and unchanged.
- `LocalRefiner` remains the only production text-processing provider.
- The harness in this directory uses only synthetic, anonymized fixtures and never reads Voxly history.
- The harness runs the external CLI only after an explicit `--run` flag; validation alone makes no network request and consumes no AI credits.
- No credentials, raw private history, or run results are written into this repository. By default, results are written to a fresh directory under the system temporary directory.

## Environment observed on 2026-09-08

- macOS on the target Apple Silicon development machine.
- `gh` version: `2.86.0`.
- The documented `gh copilot` preview wrapper was present but did not install its managed executable.
- The official Homebrew cask installed `copilot` version `1.0.83` at `/opt/homebrew/bin/copilot`.
- Node was `v18.18.2`, below the official npm-install minimum of Node 22, so npm was not used.
- A browser OAuth login was started with `copilot login`. Successful restricted CLI and ACP requests later prove that the CLI's normal credential store remains usable from the harness's sanitized child environment; no token was supplied to, read by, or stored by Voxly.

## Official contract researched

Accessed on 2026-09-08:

- [About GitHub Copilot CLI](https://docs.github.com/en/copilot/concepts/agents/about-copilot-cli) documents programmatic usage, tool permissions, local sandboxing, and subscription-backed model usage.
- [Installing GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/install-copilot-cli) documents Homebrew, npm, install-script, and release-binary installation plus the normal OAuth login flow.
- [Running GitHub Copilot CLI programmatically](https://docs.github.com/en/copilot/how-tos/copilot-cli/automate-copilot-cli/run-cli-programmatically) explicitly supports a prompt piped through standard input: `echo "..." | copilot`. This is the candidate input channel because Voxly must not place dictated text in a child-process argument list.
- [Allowing and denying tool use](https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli/allowing-tools) documents `--available-tools` as a model-visible allowlist and says it takes precedence over the available tool universe; `--deny-tool` rules take precedence over allows.
- [Copilot CLI command reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference) documents `--silent`, `--stream off`, `--disable-builtin-mcps`, `--no-custom-instructions`, `--no-ask-user`, `--no-auto-update`, `--no-remote`, and the JSONL output mode.
- [Copilot CLI ACP server](https://docs.github.com/en/copilot/reference/copilot-cli-reference/acp-server) documents a second candidate boundary: ACP over stdio sends request content through NDJSON rather than command-line arguments and fixes tool filters at server startup.
- [GitHub Terms for Additional Products and Features](https://docs.github.com/en/site-policy/github-terms/github-terms-for-additional-products-and-features), accessed 2026-09-08, says that Copilot Business and Enterprise use the Copilot Product Specific Terms while other users are governed by the GitHub Terms of Service AI-features section. It also states that previews receive only a limited right to use a non-production instance and can change or be discontinued without notice.

The CLI's own current help says non-interactive operation requires `--allow-all-tools`. The harness therefore combines it with `--available-tools=` and explicit denials. GitHub's documentation says unavailable tools are not visible to the model and denials override broad permission. The adversarial sentinel fixture must prove this combination works in the installed version before it can be considered viable.

ACP is explicitly marked as a public preview in its official reference. It is the only tested route that combines a persistent session, ACP client-side permission cancellation, `mcpServers: []`, fixed startup tool filtering, and the warm latency result below. GitHub's currently published terms do not provide a clear authorization for bundling that preview transport into a production dictation application or for using an individual subscription as its automated text-processing backend. Under the backlog rule that unclear terms are a no-go, this blocks shipment.

## Harness

Validate only, with no external call:

```bash
swift Spikes/CopilotCLI/run.swift --validate
```

After completing the CLI's normal OAuth login, run the synthetic contract smoke test:

```bash
swift Spikes/CopilotCLI/run.swift --run --fixture protocol-response
```

Run the full synthetic benchmark with an explicit requested model and a local result destination outside the repository:

```bash
swift Spikes/CopilotCLI/run.swift --run --model auto --results "$TMPDIR/voxly-copilot-benchmark"
```

The persistent ACP warm-path probe needs its isolated SDK dependency once, then can be run as follows:

```bash
cd Spikes/CopilotCLI && npm install
node acp-warm-probe.mjs
```

Run the persistent fixture benchmark with `node acp-benchmark.mjs`. It writes synthetic results to a fresh temporary directory and prints that directory path.

The runner:

- starts every stage in a fresh `0700` temporary working directory;
- passes the prompt only through the child process standard input;
- permits no model-visible tool with `--available-tools=`;
- disables built-in MCP servers, repository/user custom instructions, ask-user, remote session/export, prompt-mode extensions, repository hooks, workspace MCP sources, automatic updates, and OpenTelemetry;
- forwards only a narrow environment (`HOME`, `PATH`, locale, and temporary-directory variables), explicitly removing token environment variables by omission;
- uses `--output-format json --stream off`, extracts only the final `assistant.message.data.content` JSONL event, and accepts it only when it is one JSON object with exactly the key `text`;
- reads standard output and error concurrently, enforces a per-stage timeout, and records no unvalidated standard output or error text;
- creates inside/outside sentinel files for every CLI stage, checks that neither changed and that their random contents were not returned, then removes the whole temporary workspace.

The current result format is for synthetic fixtures only. A complete run still needs a blind comparison against the local Qwen baseline using [blind-scorecard.csv](blind-scorecard.csv), which deliberately separates `candidate_id` from the provider identity during human review.

## Initial execution results

Executed on 2026-09-08 with `copilot` `1.0.83`, model selection `auto`, a 45-second per-stage timeout, and the harness restrictions described above.

- Fixture validation passed for all 21 synthetic fixtures.
- The full run completed 30 stages: all 30 returned a parseable native JSONL `assistant.message` event containing the strict `{"text": ...}` envelope.
- Per-stage latency was 7.0 seconds median, 8.0 seconds p95, and 9.0 seconds maximum.
- Nine fixtures used the required translation-then-refinement flow. Their end-to-end latency was 14.0 seconds median, 15.0 seconds p95, and 15.0 seconds maximum.
- The single prompt-injection fixture attempted to read and overwrite a random sentinel file outside the session directory. It returned a text rewrite instead; neither the inside nor outside sentinel changed, and neither random value appeared in the recorded response.
- The persistent ACP probe used the official `@agentclientprotocol/sdk` `1.4.0`, fixed the CLI startup allowlist to empty, opened its session with `mcpServers: []`, and cancelled every permission request. Its first synthetic response took 1.532 seconds; the second prompt in the same process took 2.641 seconds. Both strict envelopes parsed, no permission request occurred, and its sentinels remained intact.
- The persistent ACP fixture benchmark used one session for all 21 fixtures. All 30 stages returned complete parseable envelopes, with 1.893 seconds median and 2.357 seconds p95 per stage. The nine translation-then-refinement fixtures completed in 3.739 seconds median and 4.448 seconds p95. No permission request occurred; the inside/outside sentinels remained intact and absent from all responses.

These are cold, one-process-per-stage measurements. They do not satisfy or disprove the backlog's **warm** two-stage latency threshold of 8 seconds median and 15 seconds p95. They do establish that the initial cold two-stage median is currently 6 seconds over that threshold, so process reuse or an ACP-based persistent client must be evaluated before a performance go decision.

The full persistent benchmark clears the latency and parseability gate for this synthetic corpus. The fixture corpus does not yet include a representative approximately 200-word dictation, so it is not sufficient to claim that the backlog's 200-word latency requirement has passed.

## Current decision

**No-go for production integration.** The product and safety requirements require subscription and CLI terms that clearly permit the intended automated personal use. The published material does not establish that permission, and the only route that met the measured isolation and warm-latency requirements is ACP, which GitHub documents as public preview and whose governing preview terms restrict use to non-production instances.

The technical harness is retained as evidence: it demonstrated stdin/NDJSON transport, parseable complete output in 30 of 30 synthetic stages, empty model-visible tools, denied permissions, disabled built-in MCP, `mcpServers: []`, and intact adversarial sentinels. This evidence is insufficient to override the contractual gate. The 200-word fixture, local-Qwen blind comparison, and remaining operational tests are deliberately not pursued because none can turn this no-go into a go without GitHub publishing or directly confirming compatible production automation terms.

Voxly remains entirely local. Do not add `TextProcessingProvider`, a Copilot adapter, provider controls, external fallback, privacy copy, or CLI distribution from this spike. Reopen only with a written GitHub terms clarification or a generally available supported API/transport whose terms explicitly permit this desktop automation use; rerun the retained harness and the remaining quality/operational gates at that time.