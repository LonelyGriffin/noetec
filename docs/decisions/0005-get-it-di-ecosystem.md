# 0005: get_it-Based DI with the watch_it/listen_it/command_it Ecosystem

## Context

Noetec (a Flutter application) needs a dependency-injection mechanism and a state-management approach consistent with the Flux-inspired unidirectional data flow chosen in ADR-0001. The Flutter ecosystem offers several mature options — Bloc, Riverpod, Provider, and the get_it family — with different trade-offs in boilerplate, indirection, and how directly reactive state is exposed.

## Decision

Use `get_it` as the dependency-injection container, together with its companion ecosystem:

- `listen_it` for reactive state — `ValueNotifier`, `ListNotifier`, `MapNotifier` collections owned directly by systems.
- `watch_it` for reactive views — widgets (via `WatchingWidget`) subscribe to specific notifiers and rebuild automatically on change.
- `command_it` for commands — reactive wrappers around sync/async functions (exposing `.isRunning`, `.errors`, `.value`) that views invoke via `command.run(param)`.

Deliberately do **not** adopt Bloc, Riverpod, or Provider. There is no ViewModel layer: systems hold reactive state directly and widgets watch it, rather than mediating through a per-view model.

## Status

Accepted.

## Consequences

- Positive: no ViewModel indirection — `watch_it`/`listen_it` let services hold reactive state that widgets watch directly, keeping the architecture simpler.
- Positive: the three libraries integrate by design with `get_it` registration, so DI, state, and commands form one coherent stack with consistent idioms.
- Positive: less boilerplate than Bloc's event/state/bloc triplet while preserving the unidirectional command-driven flow.
- Negative: a smaller community and fewer learning resources than Bloc or Riverpod; fewer third-party examples to draw on.
- Negative: the discipline of unidirectional flow is conventional (enforced by review and structure, per ADR-0001) rather than imposed by the framework — Bloc's stricter event/state separation enforces more of it mechanically.
- Negative: compile-time safety guarantees are weaker than Riverpod's provider-graph approach; wiring errors surface at lookup time.

## Alternatives considered

- **Bloc** — rejected: heavier ceremony (events, states, bloc classes per feature) than needed; the same unidirectional guarantees are achieved with commands and notifiers at lower cost.
- **Riverpod** — rejected: powerful compile-safe provider graph, but introduces a separate DI/state paradigm with more concepts than the get_it ecosystem requires; the team prefers the directness of notifiers on systems.
- **Provider** — rejected: adequate for simple cases but weaker as a DI container and offers no equivalent of the integrated command/notifier tooling.
