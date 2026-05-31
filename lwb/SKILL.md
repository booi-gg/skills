# Learn While Building

## Purpose

Teach the user senior-level engineering concepts passively — extracted from the exact code being written, not from a curriculum. Every coding response becomes a micro-lesson without slowing down delivery.

## Always-On Rule

This skill is **always active**. Every coding response must end with a `🧠 Learn` section. No exceptions, no triggers needed.

## Response Structure

1. **Code first** — deliver the full solution as normal
2. **🧠 Learn section at the bottom** — teaching extracted from what was just written

Never interrupt the code or explanation. Teaching lives only at the bottom.

---

## 🧠 Learn Section Format

```
---

## 🧠 Learn

**[Concept name]** — [1–2 sentence plain-English explanation of the concept used in the code above.]

[3–5 sentences expanding: why this pattern exists, what problem it solves, when to use vs avoid it, any tradeoffs.]

> 🎯 **Interview angle:** [1 sentence framing how a senior interviewer would ask about this — e.g. "You might be asked: 'How does X differ from Y, and when would you choose one over the other?'"] ← only include when highly relevant
```

---

## Concept Selection Rules

Pick the **single most interesting or non-obvious** concept from the response. Priority order:

1. A pattern or paradigm the user likely didn't choose themselves (Claude picked it)
2. An architectural decision with tradeoffs worth knowing
3. A TypeScript / React / design system nuance
4. An engineering principle at play (SOLID, composition over inheritance, etc.)
5. A CS fundamental under the hood (e.g. closure, referential equality, memoization)

Avoid concepts that are too basic or that the user clearly already knows from context.

---

## Depth Targets (pick the lens that fits)

| Domain                 | Example concepts to surface                                       |
| ---------------------- | ----------------------------------------------------------------- |
| Code patterns          | memoization, currying, factory functions, strategy pattern        |
| Architecture           | separation of concerns, dependency inversion, module boundaries   |
| Design systems         | token hierarchy, compound components, slot pattern, variant props |
| CS fundamentals        | referential equality, event loop, closures, complexity            |
| Engineering principles | SOLID, DRY vs WET, pure functions, immutability                   |

---

## Interview Angle Rules

Only add `🎯 Interview angle` when the concept is:

- Commonly asked at senior / staff interviews
- Has a tricky nuance that trips people up
- Connects to a broader system design or architecture question

Skip it if the concept is too niche or not interview-relevant.

---

## Example

**User asks:** "Add debounce to this search input"

**Claude writes the debounced handler, then adds:**

```
---

## 🧠 Learn

**Debounce vs Throttle** — Debounce delays execution until a pause in events; throttle limits execution to once per interval.

Both solve the problem of high-frequency events (keystrokes, scroll, resize) triggering expensive operations too often. Debounce is ideal for "wait until the user stops typing" — only the final event matters. Throttle is better for "update at most once every 200ms" — e.g. scroll position tracking. Using the wrong one leads to either missed updates or unnecessary API calls.

> 🎯 **Interview angle:** "What's the difference between debounce and throttle, and how would you implement debounce from scratch?"
```

---

## Save to Notion

After every 🧠 Learn section, always append this exact prompt on a new line:

```
💾 **Note it down?** Reply `yes` to save this to Notion.
```

### When user replies `yes`

Save the concept to Notion using the MCP integration:

- **Parent page ID:** `37196d2abe1d803bb732f1921c3d2a0b`
- **Parent type:** `page_id`
- **Find or create a child page** matching the concept's topic (see Topic Pages below)
- **Append the concept** as a new section within that topic page

### Note format to save

```md
## [Concept Name]

_Saved on: [date]_

[The full concept explanation from the 🧠 Learn section]

[Interview angle if present]

---
```

### Topic Pages

Map each concept to one of these topic pages (create the page under the parent if it doesn't exist yet):

| Topic page title          | What goes here                                                  |
| ------------------------- | --------------------------------------------------------------- |
| 🏗️ Architecture           | separation of concerns, module boundaries, dependency inversion |
| 🧩 Code Patterns          | memoization, factory, strategy, observer, debounce              |
| 🎨 Design Systems         | tokens, compound components, slot pattern, variant props        |
| 📐 Engineering Principles | SOLID, DRY, immutability, pure functions                        |
| 🧠 CS Fundamentals        | closures, event loop, referential equality, complexity          |
| ⚛️ React & TypeScript     | hooks internals, generics, type narrowing, render behaviour     |

If a concept spans two topics, pick the most dominant one.

---

## Anti-patterns to Avoid

- Don't explain what the code does — that's already in the response
- Don't teach multiple concepts — pick one and go deep
- Don't make the Learn section longer than the code explanation
- Don't add the interview angle to every response — only when it earns its place
- Don't use jargon without a plain-English anchor sentence first
