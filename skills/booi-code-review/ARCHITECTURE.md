# Architecture

Rules for the **Architecture** axis. Every finding here is a judgement call — label it "possible …", never a hard violation. A documented repo standard or ADR (`docs/adr/`) overrides; don't re-litigate a recorded decision.

## Vocabulary

Use these terms exactly.

- **Module** — anything with an interface and an implementation: function, file, hook, folder.
- **Interface** — everything a caller must know: types, plus invariants, ordering ("call `init()` first"), error modes, required config.
- **Deep** module — a lot of behaviour behind a small interface. **Shallow** — interface nearly as complex as the implementation.
- **Seam** — where an interface lives; a place behaviour can change without editing callers.
- **Locality** — change, bugs and knowledge concentrated in one place.

## Structure

- **Deletion test.** Imagine deleting the module. Complexity vanishes → it was a pass-through; inline it. Complexity reappears across callers → it earns its keep.
- **Shallow modules.** Files holding one tiny function used once; wrappers that only forward; one-function-per-file folders. → merge into a deeper module grouped by concept.
- **Hidden dependencies.** A module that silently reads a singleton, global or context its signature doesn't show. → pass it in, or make the requirement part of the interface.
- **Speculative seams.** A port, adapter, config option or parameter with only one real use. One adapter = hypothetical seam; two = real. → delete until a second need shows.
- **Dependency direction.** Inner layers import outer ones, or imports form a cycle. → invert or move the shared piece inward.
- **Separation of concerns.** Business logic in UI components; I/O in pure logic; one function doing fetching, logging, toasting and state. → split by layer.
- **Single responsibility.** A file or function with more than one reason to change.
- **Colocation.** Things that change together live apart (grouped by type, not feature); a constant exported from a leaf and imported by its parent.
- **Module boundaries.** Imports reaching into another module's internals instead of its public entry.
- **Coupling.** Shared mutable state; two states that must always change together (derive one, or merge them).
- **Folder structure.** Doesn't mirror the domain; misplaced files; pointless deep nesting.
- **Testability.** Logic only reachable through the UI or a network call. The interface is the test surface — if testing needs to reach past it, the module is the wrong shape.

## Smells (Fowler, *Refactoring* ch.3)

What it is → how to fix.

- **Mysterious Name** — name doesn't reveal what it does or holds. → rename; if no honest name comes, the design is murky.
- **Duplicated Code** — the same logic shape in more than one hunk or file. → extract the shared shape once.
- **Feature Envy** — a function reaching into another object's data more than its own. → move it to the data.
- **Data Clumps** — the same few fields or params always travel together. → bundle them into one type.
- **Primitive Obsession** — a string or number standing in for a domain concept. → give it its own small type.
- **Repeated Switches** — the same `switch`/`if`-cascade on the same type in several places. → one lookup map both sites share.
- **Shotgun Surgery** — one logical change forces edits across many files. → gather what changes together.
- **Divergent Change** — one file edited for several unrelated reasons. → split by reason.
- **Speculative Generality** — abstraction, params or hooks the spec doesn't need. → inline until a real need shows.
- **Message Chains** — long `a.b().c().d()` navigation. → hide the walk behind one function.
- **Middle Man** — a function or hook that mostly delegates onward. → call the real target directly.
- **Refused Bequest** — an implementer ignoring most of what it inherits. → composition instead.
