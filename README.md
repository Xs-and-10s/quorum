# ⚖️ Quorum

**Three minds. One review.**

Quorum is a multi-agent AI code review application that streams real-time specialist feedback to your browser. Paste code, pick a language, and watch as three AI specialists — Security, Logic, and Style — analyze your code from different angles, then a lead engineer synthesizes their findings into one actionable summary.

Built as a reference demo for [Phlox](https://hex.pm/packages/phlox), an Elixir graph-based orchestration engine for AI agent pipelines.

---

## What It Demonstrates

Quorum isn't a toy. It's a vertical slice through a production-grade architecture, designed to show how Phlox orchestrates real AI workloads with real infrastructure concerns.

**Phlox features exercised:**

- **Graph orchestration** — five-node sequential pipeline (`validate → security → logic → style → synthesize`)
- **`prep/2 → exec/2 → post/4` lifecycle** — each specialist node is independently testable; `exec` never touches shared state
- **FlowSupervisor** — each review spawns a supervised FlowServer under a DynamicSupervisor
- **Real-time Monitor** — telemetry-backed ETS tracking with PubSub subscriptions for live progress
- **Simplect middleware** — pipeline-wide token compression to stay within Groq's free-tier rate limits
- **Complect interceptor** — per-node override so the synthesizer output stays readable
- **Swappable LLM providers** — change one line to switch from Groq to Anthropic, Google, OpenAI, or Ollama

**Architecture patterns exercised:**

- **Event Sourcing** via Commanded + EventStore (Postgres-backed)
- **CQRS** — commands dispatch through aggregates; read-side projections via Ecto
- **Server-Sent Events** — Datastar Pro streams specialist cards into the DOM as they complete
- **No LiveView** — pure Phoenix controllers + HEEx templates + Datastar for reactivity

---

## Architecture

```
Browser (Datastar Pro)
  │
  POST /review {code, language}
    → Commanded: dispatch RequestReview
    → Phlox: FlowSupervisor.start_flow → FlowServer.run (async)
    → returns JSON {flow_id} → Datastar patches into signals
  │
  GET /review/:flow_id/stream
    → Phlox.Monitor.subscribe(flow_id)
    → catch up on already-completed nodes
    → stream_loop receives {:phlox_monitor, ...} messages
    → Datastar.Elements.patch / Datastar.Signals.patch per specialist
    → Commanded: dispatch RecordSpecialistReview / RecordSynthesis
  │
  ◀── specialist cards + synthesis stream into the DOM
```

### Pipeline Topology

```
validate_input → security → logic → style → synthesize
```

Sequential, not fan-out — designed for rate-limited free-tier APIs. Each node follows Phlox's three-phase lifecycle:

| Phase | Purpose | Access |
|-------|---------|--------|
| `prep/2` | Extract what `exec` needs from shared state | Read-only shared |
| `exec/2` | Do the work (LLM call, validation, etc.) | Only prep result — no shared |
| `post/4` | Write results back, decide next action | Full shared + exec result |

This isolation is what makes every node independently testable.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Orchestration | [Phlox](https://hex.pm/packages/phlox) v0.4.0 |
| Validation | [Gladius](https://hex.pm/packages/gladius) v0.6.0 |
| SSE streaming | [datastar_ex](https://hex.pm/packages/datastar_ex) v0.1.0 |
| Frontend reactivity | [Datastar Pro](https://data-star.dev/pro) v1.0.0-RC.8 (aliased bundle) |
| Web framework | Phoenix 1.8 (no LiveView) |
| Event sourcing | Commanded + EventStore (Postgres) |
| Read-side projections | Ecto |
| LLM provider | Phlox.LLM.Groq (llama-3.3-70b-versatile) |
| Token compression | Phlox.Middleware.Simplect + Phlox.Interceptor.Complect |

---

## Prerequisites

- **Elixir** 1.18+ and **Erlang/OTP** 27+
- **PostgreSQL** 14+ (for Ecto and EventStore)
- **Groq API key** — free at [console.groq.com](https://console.groq.com) (14,400 req/day, 12K TPM)

---

## Setup

### 1. Clone and install dependencies

```bash
git clone https://github.com/Xs-and-10s/quorum.git
cd quorum
mix deps.get
```

### 2. Configure your Groq API key

```bash
export GROQ_API_KEY="gsk_your_key_here"
```

Or add it to a `.env` file and source it.

### 3. Create and migrate databases

Quorum uses two Postgres databases: one for Ecto projections and one for the EventStore.

```bash
mix ecto.create
mix event_store.create
mix ecto.migrate
mix event_store.init
```

### 4. Start the server

```bash
mix phx.server
```

Visit [http://localhost:4000](http://localhost:4000).

---

## Usage

1. **Paste code** into the textarea. Any language works, but the review quality is best for languages the LLM knows well.

2. **Select the language** from the dropdown (Elixir, TypeScript, or JavaScript).

3. **Click "Review Code"** and watch the status bar light up as each specialist completes.

4. **Specialist cards** stream into the page in real time as each finishes:
   - 🛡 **Security** — injection vulnerabilities, auth flaws, data exposure, hardcoded secrets
   - 🧠 **Logic** — off-by-one errors, unhandled edge cases, concurrency bugs, type mismatches
   - ✨ **Style** — naming clarity, function length, dead code, idiomatic usage

5. **Synthesis** appears last — the lead engineer's consolidated summary with deduplicated findings grouped by severity.

### Try this example

Paste the classic SQL injection bug to see all three specialists flag it from different angles:

```elixir
def fetch_user(id) do
  query = "SELECT * FROM users WHERE id = #{id}"
  Repo.query!(query)
end
```

---

## Interpreting Results

### Severity ratings

Each specialist uses its own severity vocabulary:

| Specialist | Ratings |
|-----------|---------|
| Security | CRITICAL · HIGH · MEDIUM · LOW |
| Logic | BUG · SMELL · SUGGESTION |
| Style | REFACTOR · NITPICK · PRAISE |

### Error cards

If a specialist card appears with an error styling, it means the LLM call failed — usually a Groq rate limit (429). The review text will contain the error details. The pipeline continues; other specialists and the synthesis still run.

### Token compression

Quorum uses Phlox's Simplect/Complect system to stay within Groq's free-tier rate limits:

- **Specialists** respond at `:full` compression (~65% token savings) — terse, technical output that's ideal for code review findings
- **Synthesizer** responds at `:lite` compression (~40% savings) — preserves grammar and readability since users read this summary directly

If you're on a paid Groq tier (or using a different provider), you can remove the Simplect middleware from `Quorum.FlowSupervisor` and the Complect interceptor from `Quorum.Pipeline.Nodes.Synthesize` for full prose output.

---

## Swapping LLM Providers

Change one file: `lib/quorum/pipeline/code_review.ex`. Replace the Groq params with any Phlox adapter:

```elixir
# Groq (free, rate-limited)
%{llm: Phlox.LLM.Groq, llm_opts: [model: "llama-3.3-70b-versatile"]}

# Anthropic
%{llm: Phlox.LLM.Anthropic, llm_opts: [model: "claude-sonnet-4-6"]}

# Google Gemini
%{llm: Phlox.LLM.Google, llm_opts: [model: "gemini-2.5-flash"]}

# OpenAI
%{llm: Phlox.LLM.OpenAI, llm_opts: [model: "gpt-4.1-mini"]}

# Local (Ollama)
%{llm: Phlox.LLM.Ollama, llm_opts: [model: "llama3"]}
```

Set the corresponding environment variable (`ANTHROPIC_API_KEY`, `GOOGLE_AI_KEY`, `OPENAI_API_KEY`) and restart.

---

## Project Structure

```
lib/
├── quorum/
│   ├── application.ex              # Supervision tree
│   ├── flow_supervisor.ex          # Starts Phlox flows with Simplect middleware
│   ├── commanded_app.ex            # Commanded application
│   ├── commands.ex                 # RequestReview, RecordSpecialistReview, RecordSynthesis
│   ├── events.ex                   # ReviewRequested, SpecialistReviewRecorded, etc.
│   ├── aggregates/
│   │   └── code_review.ex          # Commanded aggregate
│   ├── projectors/
│   │   └── review_summary.ex       # Ecto read-side projector
│   ├── interceptor/
│   │   └── rate_limit.ex           # Pre-exec delay for rate-limited APIs
│   └── pipeline/
│       ├── code_review.ex          # Graph definition (5 nodes, sequential)
│       └── nodes/
│           ├── specialist.ex       # Shared behaviour for LLM review nodes
│           ├── validate_input.ex   # Input validation via Gladius
│           ├── security_review.ex  # 🛡 Security specialist
│           ├── logic_review.ex     # 🧠 Logic specialist
│           ├── style_review.ex     # ✨ Style specialist
│           └── synthesize.ex       # Lead engineer synthesis
├── quorum_web/
│   ├── controllers/
│   │   ├── page_controller.ex      # Serves the home page
│   │   └── review_controller.ex    # POST /review + GET /review/:id/stream (SSE)
│   └── templates/
│       ├── layout/root.html.heex   # HTML shell
│       └── page/home.html.heex     # Datastar Pro reactive UI
└── priv/
    └── static/assets/
        ├── app.css                 # Dark theme
        └── datastar-pro-aliased.js # Datastar Pro bundle (data-star-* prefix)
```

---

## Datastar Pro Notes

Quorum uses the aliased Datastar Pro bundle, which means all attributes use the `data-star-*` prefix instead of the standard `data-*`:

| Standard | Aliased (Quorum) |
|----------|-----------------|
| `data-signals` | `data-star-signals` |
| `data-on:click` | `data-star-on:click` |
| `data-bind:value` | `data-star-bind:value` |
| `data-show` | `data-star-show` |
| `data-effect` | `data-star-effect` |

Signals use `$` prefix (`$flow_id`, `$code`), actions use `@` prefix (`@post()`, `@get()`).

---

## Testing

```bash
# Create test databases (first time only)
MIX_ENV=test mix ecto.create
MIX_ENV=test mix event_store.create
MIX_ENV=test mix ecto.migrate
MIX_ENV=test mix event_store.init

# Run tests
mix test
```

---

## Known Limitations

- **Sequential pipeline** — specialists run one at a time to respect Groq's TPM limit. On a paid tier or with a local model, you could refactor to parallel fan-out using `Phlox.BatchNode` or `Phlox.FanOutNode`.
- **No persistent review history UI** — reviews are stored in the EventStore and projected to Ecto, but there's no UI to browse past reviews yet. The data is there; the page isn't.
- **Basic markdown rendering** — the `md_to_html/1` helper in the controller handles bold, headers, code blocks, and lists. It's not a full markdown parser. For production, consider pulling in Earmark.
- **Groq rate limits** — even with Simplect compression, very large code pastes can exceed 12K TPM. The pipeline degrades gracefully (error cards for failed specialists), but the synthesis may also fail if it can't read the prior reviews.

---

## Credits

- **[Phlox](https://hex.pm/packages/phlox)** — graph-based orchestration engine for Elixir
- **[Datastar](https://data-star.dev)** — hypermedia framework for reactive UIs
- **[datastar_ex](https://hex.pm/packages/datastar_ex)** — Elixir SSE adapter for Datastar
- **[Commanded](https://hex.pm/packages/commanded)** — CQRS/ES framework for Elixir
- **[Gladius](https://hex.pm/packages/gladius)** — validation library for Elixir
- **[Caveman](https://github.com/JuliusBrussee/caveman)** — inspiration for Phlox's Simplect/Complect token compression

---

## License

MIT
