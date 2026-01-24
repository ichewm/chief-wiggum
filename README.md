# Chief Wiggum

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/Language-Bash-blue)](https://www.gnu.org/software/bash/)
[![Ralph Wiggum](https://img.shields.io/badge/CI-passing-green)](https://github.com/0kenx/chief-wiggum)

**Chief Wiggum** is an agentic task runner that helps your computer do things while you're sleeping! It uses the **[Ralph Wiggum](https://awesomeclaude.ai/ralph-wiggum)** way of doing things: "simple, happy, and do one thing at a time."

![Chief Wiggum](docs/chief_wiggum.jpeg)

> "Bake him away, toys."

## Overview

Chief Wiggum monitors a `.ralph/kanban.md` file in your project. For every incomplete task, it spawns an isolated worker. Each worker:

1.  Creates a dedicated **git worktree** to ensure complete isolation from your main working directory and other workers.
2.  Generates a **PRD (Product Requirement Document)** specific to that task.
3.  Enters the **Ralph Loop**, autonomously driving **Claude Code** to execute specific tasks until completion.
4.  Merges results back via Pull Requests and updates the Kanban board.

## Prerequisites

- **Linux/macOS** (Bash environment)
- **Git**
- **Claude Code** (`claude` CLI installed and authenticated)
- **GitHub CLI** (`gh` installed and authenticated) - Required for PR management

## Installation & Usage

### Option 1: Global Installation

Run the installation script to set up Chief Wiggum in `~/.claude/chief-wiggum`:

```bash
./install.sh
```

Then, add the binary directory to your PATH:

```bash
export PATH="$HOME/.claude/chief-wiggum/bin:$PATH"
```

### Option 2: Run from Source

You can run Chief Wiggum directly from this repository by setting `WIGGUM_HOME` to the current directory:

```bash
export WIGGUM_HOME=$(pwd)
export PATH="$WIGGUM_HOME/bin:$PATH"
```

## Quick Start

### 1. Initialize a Project

Navigate to any git repository where you want to use Chief Wiggum and initialize the configuration:

```bash
cd /path/to/your/project
wiggum init
```

This creates a `.ralph/` directory containing a `kanban.md` file.

### 2. Define Tasks

Edit `.ralph/kanban.md` to add tasks to the **TASKS** section.

```markdown
## TASKS

- [ ] **[TASK-001]** Refactor Authentication
  - Description: Split auth logic into a separate service...
  - Priority: HIGH
```

Task statuses:
- `- [ ]` - Pending (not yet assigned)
- `- [=]` - In Progress (worker actively working on it)
- `- [x]` - Complete (worker finished successfully)
- `- [*]` - Failed (worker encountered an error)

### 3. Validate Tasks

Before running workers, ensure your Kanban board is correctly formatted:

```bash
wiggum validate
```

This checks for:
- Correct Task ID format (`TASK-001`)
- Required fields (Description, Priority)
- Unique Task IDs
- Valid dependency references
- Proper indentation

### 4. Start Workers

Run `wiggum run` to spawn workers for incomplete tasks:

```bash
wiggum run
```

Chief will:
- Assign pending tasks to workers (up to 4 concurrent workers by default)
- Mark assigned tasks as `[=]` in-progress
- Monitor workers and spawn new ones as workers finish
- Wait until all tasks are complete

To change the maximum concurrent workers:

```bash
wiggum run --max-workers 8
```

### 5. Monitor Progress

Watch the status of active workers in real-time:

```bash
# View combined logs from all workers
wiggum monitor

# View status summary table
wiggum monitor status

# View split pane with recent logs for each worker
wiggum monitor split
```

Check the overall system status:

```bash
wiggum status
```

### 6. Review and Merge

Workers create Pull Requests for completed tasks. Manage them with:

```bash
# List open worker PRs
wiggum review list

# View a specific PR
wiggum review pr 123 view

# Merge a specific PR
wiggum review pr 123 merge

# Merge all open worker PRs
wiggum review merge-all
```

## Advanced Commands

### Cleanup

If you need to remove worktrees and temporary files (e.g., after a crash or to free up space):

```bash
wiggum clean
```

This removes all worker worktrees and clears the `.ralph/workers/` directory.

## Architecture

- **`wiggum`**: Main orchestrator.
- **`wiggum-validate`**: Ensures your instructions (Kanban) are legible.
- **`wiggum-monitor`**: Keeps an eye on the boys (workers).
- **`wiggum-review`**: Paperwork processing (PR management).
- **Workers**: Isolated processes running in temporary git worktrees (`.ralph/workers/`).
- **Ralph Loop**: The core execution loop (`lib/ralph-loop.sh`) that prompts Claude Code to read the PRD, execute work, and verify results.

### Context Window Management

The Ralph Loop uses a **controlled context window** approach to prevent context bloat:

1. Each iteration starts a fresh Claude session with a unique session ID.
2. Sessions are limited to a configurable number of turns (default: 20).
3. When a session hits the turn limit:
   - The session is resumed with `--resume <session-id>`
   - Claude provides a summary of work completed
   - The summary is appended to the PRD as a changelog entry
4. The next iteration reads the updated PRD (with changelog) and continues with fresh context.

This ensures each session stays within ~10-15K tokens instead of growing unbounded.

## Directory Structure

When running, Chief Wiggum creates:

```text
.ralph/
├── kanban.md       # The source of truth for tasks
├── changelog.md    # Summary of all completed tasks
├── workers/        # Temporary worktrees for active agents
├── logs/           # Worker logs
└── metrics/        # Cost and performance tracking
```

## Agent Architecture

Chief Wiggum uses a hierarchical agent system where **each Kanban task maps to an agent as its entry point**, and agents can recursively invoke sub-agents to complete their work.

### Agent Structure

Each agent is a self-contained bash script in `/lib/agents/` that implements a standard interface:

```bash
agent_required_paths()    # Returns list of prerequisite files needed
agent_run()               # Main entry point: agent_run(worker_dir, project_dir, ...)
agent_output_files()      # [Optional] Returns list of output files to validate
agent_cleanup()           # [Optional] Cleanup after completion
```

**Available agents:**
| Agent | Purpose |
|-------|---------|
| `system.task-worker` | Primary task execution - reads PRD, implements features |
| `engineering.validation-review` | Code review against PRD requirements |
| `engineering.pr-comment-fix` | Addresses PR review feedback iteratively |

### Kanban → Agent Linking

Each task in the Kanban board is linked to an agent as its entry point:

```
.ralph/kanban.md (task definition)
       ↓
Task Parser extracts metadata (ID, priority, dependencies)
       ↓
Worker directory created: worker-TASK-001-<timestamp>/
       ↓
PRD generated from task specification
       ↓
system.task-worker agent executes as entry point
       ↓
Agent may invoke sub-agents (e.g., engineering.validation-review)
       ↓
Kanban updated: [ ] → [=] → [x] or [*]
```

### Recursive Agent Calls (Sub-Agents)

Agents can call other agents, creating a hierarchy. There are two invocation modes:

**Top-Level Agents** (`run_agent`):
- Full lifecycle management with PID recording and signal handlers
- Started by the orchestrator for each Kanban task
- Manages its own violation monitor

**Sub-Agents** (`run_sub_agent`):
- Lightweight nested execution within parent agent context
- Inherits parent's `worker_dir` and `project_dir`
- No independent PID file or violation monitor

Example hierarchy:
```
system.task-worker (top-level agent)
  └── engineering.validation-review (sub-agent)
        └── [could call further sub-agents if needed]
```

From `system/task-worker.sh`:
```bash
# After main work completes, run validation as sub-agent
run_sub_agent "engineering.validation-review" "$worker_dir" "$project_dir"
```

### Claude Invocation Patterns

Agents invoke Claude Code in multiple ways, often combining patterns within a single agent:

#### Pattern 1: Single Execution (`run_agent_once`)

One-shot prompts where no session continuity is needed:

```bash
run_agent_once "$workspace" "$system_prompt" "$user_prompt" "$output_file" "$max_turns"
```

- Executes Claude with a single prompt
- Limited to configurable turns (default: 3)
- No session state preserved after completion

#### Pattern 2: Ralph Loop (`run_ralph_loop`)

Iterative work sessions with context preservation between iterations:

```bash
run_ralph_loop "$workspace" \
    "$system_prompt" \
    "_user_prompt_callback" \      # Function that generates each iteration's prompt
    "_completion_check_callback" \ # Function that checks if work is done
    "$max_iterations" \            # How many iterations before giving up
    "$max_turns" \                 # Turns per Claude session
    "$output_dir" \
    "$session_prefix"
```

Each iteration:
1. Check completion callback - exit if done
2. Generate prompt via callback
3. **Work phase**: Claude executes with turn limit
4. **Summary phase**: Resume session to generate summary
5. Save summary as context for next iteration

This pattern prevents context bloat by:
- Starting fresh sessions each iteration
- Carrying forward only summaries (~10-15K tokens per session)
- Allowing indefinite work across many iterations

#### Pattern 3: Session Resume (`run_agent_resume`)

Continue an existing session for follow-up work:

```bash
run_agent_resume "$session_id" "$prompt" "$output_file" "$max_turns"
```

- Uses `--resume <session-id>` to continue conversation
- Preserves full context from previous session
- Used for final summary generation after Ralph Loop

### Combining Patterns

Agents typically combine these patterns. Here's how `system.task-worker` uses all three:

```
1. RALPH LOOP (iterative work)
   ├── Iteration 0: Read PRD, start implementation
   ├── Iteration 1-N: Continue until complete
   │   └── Each iteration: work phase + summary phase
   └── Completion detected

2. SESSION RESUME (final summary)
   └── Resume last session to generate final summary

3. SUB-AGENT CALL
   └── engineering.validation-review agent (uses its own Ralph Loop internally)
```

The `engineering.validation-review` sub-agent then runs its own Ralph Loop:
```
RALPH LOOP (validation)
├── Iteration 0: Read PRD + code, start review
├── Iteration 1-N: Continue analysis
└── Generate PASS/FAIL result
```

### Context Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         TASK-WORKER                              │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    RALPH LOOP                            │    │
│  │  ┌──────────┐    ┌──────────┐    ┌──────────┐           │    │
│  │  │ Iter 0   │───►│ Iter 1   │───►│ Iter N   │           │    │
│  │  │ Work     │    │ Work     │    │ Work     │           │    │
│  │  │ Summary  │    │ Summary  │    │ Summary  │           │    │
│  │  └──────────┘    └──────────┘    └──────────┘           │    │
│  │       │               │               │                  │    │
│  │       ▼               ▼               ▼                  │    │
│  │   [context]──────►[context]──────►[context]              │    │
│  └─────────────────────────────────────────────────────────┘    │
│                              │                                   │
│                              ▼                                   │
│                    SESSION RESUME (final summary)                │
│                              │                                   │
│                              ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │         SUB-AGENT: engineering.validation-review          │    │
│  │  ┌──────────────────────────────────────┐               │    │
│  │  │           RALPH LOOP                  │               │    │
│  │  │  Iter 0 ──► Iter 1 ──► ... ──► Done   │               │    │
│  │  └──────────────────────────────────────┘               │    │
│  │                      │                                   │    │
│  │                      ▼                                   │    │
│  │               PASS / FAIL result                         │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

This architecture enables:
- **Unlimited work**: Ralph Loop can iterate indefinitely without context overflow
- **Specialized agents**: Each agent focuses on one responsibility
- **Composability**: Agents can be combined in different ways
- **Isolation**: Each agent manages its own Claude sessions
