| name | description |
|------|-------------|
| wiggum-plan | Create implementation plans through systematic 7-phase workflow: discovery, exploration, clarifying questions, architecture design, plan writing, and summary. Planning only - never implements. Always writes plan to `.ralph/plans/TASK-ID.md`. |

# Wiggum Plan

## Purpose

Create implementation plans through a systematic 7-phase workflow that ensures deep codebase understanding and thoughtful architecture decisions. This skill is for **planning only** - it never implements code.

## Input

**Mode 1 - Existing Task**: A task ID from `.ralph/kanban.md` (e.g., `TASK-015`, `FEATURE-042`).

**Mode 2 - New Task**: A description of work to be done (e.g., "Add user authentication with JWT"). When no valid task ID is provided, the skill will:
1. Create the task in `.ralph/kanban.md`
2. Then create the implementation plan

## When This Skill is Invoked

**Manual invocation:**
- Before implementing a complex task
- When a task needs architectural analysis
- To document approach before handing to a worker

**From other skills:**
- After `/kanban` creates tasks that need detailed planning

## Critical Rules

1. **NEVER implement** - This skill produces plans, not code
2. **ALWAYS write the plan file** - Every session must end with writing `.ralph/plans/TASK-ID.md`
3. **Multiple iterations allowed** - Explore, ask questions, explore more as needed
4. **READ-ONLY exploration** - Only modify the kanban file (when creating tasks) and plan file
5. **Create task when needed** - If no valid task ID is provided, create the task in kanban first
6. **Clarifying questions are critical** - Never skip Phase 3; it's one of the most important phases

## Core Workflow: 7 Phases

### Phase 0: Task Creation (when no task ID provided)

**Skip this phase if a valid task ID was provided.**

When the input is a description rather than a task ID:

**Analyze existing kanban:**
- Read `.ralph/kanban.md`
- Identify the highest task number for ID assignment
- Note existing dependencies and task prefixes used
- Check for similar/related pending tasks

**Clarify requirements with AskUserQuestion:**
- Scope: What should be included/excluded?
- Priority: How urgent is this work?
- Dependencies: Does this depend on existing tasks?

**Design the task:**
- Determine if it should be one task or multiple
- If multiple tasks needed, break down with proper dependencies (use Scope field for sub-items within a single task)
- Each task should be completable by one worker in one session

**Create the task in kanban:**
- Add properly formatted task entry to `.ralph/kanban.md`
- Include all required fields: Description, Priority, Dependencies
- Use optional fields (Scope, Acceptance Criteria) when helpful
- Confirm with user before writing via AskUserQuestion

For task format details, see `/kanban` skill references:
- Task format: `skills/kanban/references/task-format.md`
- Dependency patterns: `skills/kanban/references/dependency-patterns.md`
- Sizing guidelines: `skills/kanban/references/sizing-guidelines.md`

**After task creation, continue to Phase 1 with the newly created task ID.**

---

### Phase 1: Research

**Goal:** Deep understanding of the requirements, the system, and the specifications before touching any code. This is NOT just reading the task — it is understanding how the system works and how the new requirements fit within it.

**Read the task requirements:**
- Read `.ralph/kanban.md` and find the task entry for the given ID
- Extract Description, Scope, Acceptance Criteria, Dependencies
- Check dependent tasks to understand what they provide
- Classify the task: is this a bug fix, a new feature, a refactor, or a behavioral change?

**Read project-level instructions:**
- Read `CLAUDE.md` or `AGENTS.md` at the project root (if they exist) for conventions and constraints
- Explore `docs/` for analysis, research, references, and developer documentation

**Discover and read specifications:**
- Explore `spec/` — this is the source of truth for specifications. Do not assume any internal structure; list what you find and read each spec relevant to the task
- Determine how the new requirements fit within the existing specifications
- Identify which interfaces, contracts, or schemas are affected
- Does the spec already accommodate this requirement, or does it need to be extended?
- Flag any cases where current code already deviates from spec — the plan should correct drift, not entrench it

**Ask initial clarifying questions:**
- What problem does this solve?
- What is the desired functionality?
- Are there any constraints or requirements not in the task?
- What does success look like?

**Output:** Clear understanding of requirements, specifications, and constraints before diving into code.

---

### Phase 2: Codebase Exploration (Parallel Analysis)

**Goal:** Build comprehensive understanding of relevant existing code through parallel exploration of four dimensions.

**Dimension A - Similar Features:**
- Search for existing features that solve similar problems
- Trace execution paths from entry points through data transformations
- Document how existing features are structured
- **For bug fixes**: Trace the failure path, identify root cause (not just symptoms), find sibling bugs sharing the same cause, check why existing tests missed it
- **For new features**: Map every component the feature will touch, find analogous features as implementation references

**Dimension B - Architecture & Patterns:**
- Map abstraction layers and module boundaries
- Identify design patterns used in the codebase
- Understand technology stack and conventions
- Study how the system works end-to-end for the area this task touches
- Understand existing abstractions — what they encapsulate and what assumptions they encode

**Dimension C - Integration Points:**
- Find code that will interact with the new feature
- Identify shared utilities, services, and data models
- Understand testing patterns and coverage expectations

**Dimension D - Interfaces & Coupling:**
- What is the current interface surface between the modules this task touches?
- Can the integration surface be *reduced* rather than extended? Fewer touch-points is better
- Are the affected modules orthogonal — independent concerns, or hidden coupling?
- If modules share state, configuration, or implicit contracts, can these be made explicit and narrow?
- Would an explicit interface (function contract, file format, schema) make two modules less entangled?
- Prefer designs where a change in one module does not ripple into unrelated modules

**Exploration tools (READ-ONLY):**
- **Glob**: Find files by pattern
- **Grep**: Search for code patterns, function names, imports
- **Read**: Examine specific files in detail
- **Bash** (read-only): `ls`, `git log`, `git diff`

**Output:** Identify key files for reference with specific insights from each. Catalog every file that will need to change, with specific line ranges.

---

### Phase 3: Clarifying Questions (CRITICAL)

**Goal:** Address all remaining ambiguities before designing architecture.

> ⚠️ **This is one of the most important phases. Do not skip it.**

**Consolidate questions from exploration into categories (ask in this order):**

1. **Architectural Direction** *(always first)*: Present any architectural improvements the new requirements make possible — consolidation, decoupling, simplification. Ground options in Phase 1-2 findings. If no changes are warranted, state why.
2. **Integration Points**: How should this interact with existing systems?
3. **Design Preferences**: Performance vs simplicity? Explicit vs convention?
4. **Edge Cases & Error Handling**: Failure modes, empty states, retry logic
5. **Scope Boundaries**: What's explicitly out of scope?

**AskUserQuestion Format:**
```yaml
questions:
  - question: Should we consolidate modules X and Y behind a shared interface?
    header: Architecture
    multiSelect: false
    options:
      - label: Consolidate (Recommended)
        description: "Reduces coupling. X (src/x.sh:40) and Y (src/y.sh:15) share 3 implicit contracts"
      - label: Keep separate
        description: "Lower risk, but interface surface stays wide"
```

**Guidelines:**
- Ground every option in codebase findings (cite file paths)
- One decision per question (avoid compound questions)
- Provide trade-off context in descriptions
- Ask 3-6 questions for complex features

**Output:** All ambiguities resolved with clear decisions documented.

---

### Phase 4: Architecture Design (Multiple Approaches)

**Goal:** Present 2-3 architecture approaches with trade-off analysis, then recommend the best fit.

**Reflect on best practices first:**
- How is this kind of problem solved in well-tested production systems?
- What are established patterns in the broader ecosystem for this functionality?
- Are there known pitfalls, anti-patterns, or scaling concerns with the naive approach?
- What would a senior architect critique about the simplest possible implementation?

**Generate approaches:**

| Approach | Description | When to Use |
|----------|-------------|-------------|
| **Minimal Changes** | Smallest possible footprint, follows existing patterns exactly | Time-critical, low-risk features |
| **Clean Architecture** | Ideal design with proper abstractions and separation | Foundational features, long-term maintainability |
| **Pragmatic Balance** | Balanced trade-off between minimal and clean | Most features; good default |

**For each approach, document:**
- Key architectural decisions and rationale
- Component design with file paths and responsibilities
- Data flow from entry points through transformations
- Files to CREATE vs MODIFY vs REFERENCE
- Specification impact: which specs need modification, interface surface changes (narrower/same/wider)
- Whether modules can be consolidated or simplified, or whether new abstractions are justified
- Pros and cons

**Present trade-off analysis:**
```
questions:
  - question: Which architecture approach should we use?
    header: Approach
    multiSelect: false
    options:
      - label: Minimal Changes (Recommended)
        description: "Add to existing X pattern in src/Y. Fast, low risk. Trade-off: less flexible"
      - label: Clean Architecture
        description: "New abstraction layer with proper interfaces. Trade-off: more files, higher effort"
      - label: Pragmatic Balance
        description: "Extend existing patterns with targeted improvements. Trade-off: moderate complexity"
```

**After user selection, confirm before proceeding:**
```
questions:
  - question: Ready to finalize the implementation plan with this approach?
    header: Confirm
    multiSelect: false
    options:
      - label: Yes, write the plan
        description: Finalize plan with selected architecture
      - label: Explore more
        description: I have more questions or want to reconsider
```

**Output:** Selected architecture approach with user approval.

---

### Phase 5: Write the Plan (REQUIRED)

**Goal:** Document the complete implementation plan.

**You MUST write the plan to `.ralph/plans/TASK-ID.md`** - this is not optional.

**Plan must include:**
- Selected architecture approach and rationale
- Specification impact: specs consulted, spec modifications required, interface changes, existing drift
- Patterns discovered during exploration (with file references)
- Step-by-step implementation sequence with file paths, line numbers, current code snippets, and precise change descriptions
- Module impact summary and whether modules should be combined or reorganized
- Critical files table (CREATE/MODIFY/REFERENCE with line ranges)
- Optimization goals: whether this simplifies or adds complexity
- Future considerations: migration, compatibility, follow-up work
- Testing plan: specific tests to add/modify/run, with success criteria
- Potential challenges and mitigations
- Decisions made during clarifying questions

For plan structure and format, see references/plan-format.md.

---

### Phase 6: Summary

**Goal:** Document accomplishments and provide clear next steps.

**Present summary to user:**
- What was planned and why
- Key architectural decisions made
- Specification changes required (if any)
- Interface surface impact (narrower/same/wider)
- Critical files identified
- Potential challenges flagged
- Suggested next steps (run worker, need more planning, etc.)

**Output:** User has clear understanding of the plan and confidence to proceed.

## Key Principles

1. **Research before exploring** - Understand requirements, specs, and system architecture before diving into code
2. **Specs are source of truth** - Explore `spec/` to understand existing specifications; plan must account for spec fit and required changes
3. **Follow the 7 phases** - Research → Exploration → Questions → Architecture → Plan → Summary
4. **Parallel exploration** - Analyze similar features, architecture, integration points, and interfaces/coupling together
5. **Minimize interface surface** - Prefer designs that reduce coupling between modules, not extend it
6. **Questions are critical** - Phase 3 is one of the most important; never skip it
7. **Multiple approaches** - Present 2-3 architecture options with trade-off analysis
8. **Get approval** - Confirm architecture choice before writing plan
9. **Ground in findings** - Every option must reference actual codebase patterns and spec documents
10. **Always write plan** - Session must end with `.ralph/plans/TASK-ID.md`
11. **Never implement** - Planning only, no code changes

## Progressive Disclosure

This SKILL.md contains the core workflow. For detailed guidance:
- **Plan format**: references/plan-format.md
- **Exploration strategies**: references/exploration-strategies.md
- **Question patterns**: references/question-patterns.md
