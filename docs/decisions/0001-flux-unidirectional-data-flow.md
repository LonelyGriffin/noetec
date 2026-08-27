# 0001: Flux-Inspired Unidirectional Data Flow

## Context

Noetec needs a state-management and data-flow architecture that keeps a growing set of features (vault management, editing, persistence, and eventually sync) predictable and testable. In a reactive UI it is easy for state to be mutated from many places, producing circular dependencies, hidden side effects, and flows that are hard to trace or debug.

## Decision

Adopt a Flux-inspired unidirectional data flow. The loop is:

1. A user action occurs in the View.
2. The View calls `command.run(param)` on a System's Command.
3. The Command executes its handler, performing domain operations on Entities.
4. The handler updates the System's reactive state (Notifiers).
5. A `WatchingWidget` observing those notifiers detects the change and rebuilds.
6. The cycle repeats from step 1.

Properties of this flow:

- **Unidirectional** — state moves in one direction only; no circular dependencies between systems.
- **Explicit** — all state changes flow through commands; nothing mutates state behind the scenes.
- **Isolated** — a system cannot directly mutate another system's state.
- **Cross-system communication** — if System A needs System B to act, A calls B's command. A may watch B's state but never mutates it.

## Status

Accepted.

## Consequences

- Positive: data flow is explicit and easy to trace; state transitions are testable at the command boundary; circular dependencies between systems are structurally prevented.
- Positive: views stay thin (no business logic, no direct entity mutation), which keeps UI code simple.
- Negative: more boilerplate than ad-hoc mutation — every state change requires a command, even trivial ones.
- Negative: indirection — a reader must follow the command → handler → notifier chain to understand how a UI event leads to a state change.

## Alternatives considered

- **Direct two-way binding / mutable shared state** — rejected: leads to hidden side effects, circular dependencies, and flows that are hard to trace or test.
- **Bloc / event-sink pattern** — rejected: similar unidirectional guarantees but with heavier ceremony (events + states + blocs) than the command/notifier model chosen here; the chosen stack achieves the same one-way flow with less indirection (see ADR-0005).
- **Redux-style single global store** — rejected: a single immutable global state tree plus reducers adds a normalization burden and indirection that is unnecessary when feature-based systems each own their own reactive state.
