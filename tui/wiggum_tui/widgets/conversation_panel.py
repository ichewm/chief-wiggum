"""Conversation panel widget showing worker chat history."""

from pathlib import Path
from textual.app import ComposeResult
from textual.containers import Horizontal, Vertical, VerticalScroll
from textual.widgets import Static, Select, Tree
from textual.widgets.tree import TreeNode
from textual.widget import Widget

from ..data.conversation_parser import (
    parse_iteration_logs,
    get_conversation_summary,
    truncate_text,
    format_tool_result,
)
from ..data.worker_scanner import scan_workers
from ..data.models import Conversation, ConversationTurn, ToolCall


class ConversationPanel(Widget):
    """Conversation panel showing worker chat history in a tree view."""

    DEFAULT_CSS = """
    ConversationPanel {
        height: 1fr;
        width: 100%;
        layout: vertical;
    }

    ConversationPanel .conv-header {
        height: 1;
        background: #1e293b;
        padding: 0 1;
    }

    ConversationPanel .conv-controls {
        height: 3;
        background: #1e293b;
        padding: 0 1;
    }

    ConversationPanel Select {
        width: 40;
    }

    ConversationPanel Tree {
        height: 1fr;
        background: #0f172a;
        border: solid #334155;
    }

    ConversationPanel .empty-message {
        text-align: center;
        color: #64748b;
        padding: 2;
    }

    ConversationPanel .prompt-section {
        height: auto;
        max-height: 10;
        background: #1e293b;
        border: solid #334155;
        padding: 1;
        margin-bottom: 1;
    }

    ConversationPanel .prompt-label {
        color: #f59e0b;
        text-style: bold;
    }

    ConversationPanel .prompt-text {
        color: #94a3b8;
    }
    """

    def __init__(self, ralph_dir: Path) -> None:
        super().__init__()
        self.ralph_dir = ralph_dir
        self._workers_list: list[tuple[str, str]] = []  # (id, label)
        self.current_worker: str | None = None
        self.conversation: Conversation | None = None

    def compose(self) -> ComposeResult:
        self._load_workers()

        yield Static(
            "[bold]Conversation[/] │ Select a worker to view chat history",
            classes="conv-header",
            id="conv-header",
        )

        with Horizontal(classes="conv-controls"):
            yield Select(
                [(label, worker_id) for worker_id, label in self._workers_list],
                prompt="Select worker...",
                id="worker-select",
            )

        if not self._workers_list:
            yield Static(
                "No workers with conversation logs found.",
                classes="empty-message",
            )
            return

        yield Tree("Conversation", id="conv-tree")

    def on_mount(self) -> None:
        """Initialize panel."""
        if self._workers_list:
            # Auto-select first worker
            first_worker_id = self._workers_list[0][0]
            self._load_conversation(first_worker_id)

    def _load_workers(self) -> None:
        """Load list of workers with conversations."""
        workers = scan_workers(self.ralph_dir)
        self._workers_list = []

        for worker in workers:
            worker_dir = self.ralph_dir / "workers" / worker.id
            logs_dir = worker_dir / "logs"
            if logs_dir.is_dir() and list(logs_dir.glob("iteration-*.log")):
                label = f"{worker.task_id} - {worker.status.value}"
                self._workers_list.append((worker.id, label))

    def _load_conversation(self, worker_id: str) -> None:
        """Load conversation for a worker."""
        self.current_worker = worker_id
        worker_dir = self.ralph_dir / "workers" / worker_id
        self.conversation = parse_iteration_logs(worker_dir)
        self._populate_tree()
        self._update_header()

    def _populate_tree(self) -> None:
        """Populate the tree with conversation turns."""
        try:
            tree = self.query_one("#conv-tree", Tree)
            tree.clear()

            if not self.conversation or not self.conversation.turns:
                tree.root.add_leaf("No conversation data available")
                return

            # Add summary
            summary = get_conversation_summary(self.conversation)
            tree.root.label = (
                f"Conversation │ {summary['turns']} turns │ "
                f"{summary['tool_calls']} tool calls │ "
                f"${summary['cost_usd']:.2f}"
            )

            # Group turns by iteration
            current_iteration = -1
            iteration_node: TreeNode | None = None

            for i, turn in enumerate(self.conversation.turns):
                if turn.iteration != current_iteration:
                    current_iteration = turn.iteration
                    # Find iteration result for this iteration
                    result = next(
                        (r for r in self.conversation.results if r.iteration == current_iteration),
                        None,
                    )
                    result_info = ""
                    if result:
                        result_info = f" │ {result.num_turns} turns │ ${result.total_cost_usd:.2f}"

                    iteration_node = tree.root.add(
                        f"[#f59e0b]Iteration {current_iteration}[/]{result_info}",
                        expand=current_iteration == 0,
                    )

                if iteration_node:
                    self._add_turn_to_tree(iteration_node, turn, i)

            tree.root.expand()

        except Exception:
            pass

    def _add_turn_to_tree(self, parent: TreeNode, turn: ConversationTurn, index: int) -> None:
        """Add a conversation turn to the tree."""
        # Add assistant text if present
        if turn.assistant_text:
            text_preview = truncate_text(turn.assistant_text, 80)
            parent.add_leaf(f"[#3b82f6]Assistant:[/] {text_preview}")

        # Add tool calls
        for tool_call in turn.tool_calls:
            # Format tool label with input preview
            input_preview = self._format_tool_input(tool_call)
            if input_preview:
                tool_label = f"[#22c55e]{tool_call.name}[/] [#64748b]{input_preview}[/]"
            else:
                tool_label = f"[#22c55e]{tool_call.name}[/]"

            tool_node = parent.add(tool_label, expand=False)

            # Add result if present
            if tool_call.result is not None:
                result_preview = format_tool_result(tool_call.result, 80)
                # Color based on result type
                if "Error" in result_preview:
                    tool_node.add_leaf(f"[#dc2626]{result_preview}[/]")
                elif result_preview == "Success":
                    tool_node.add_leaf(f"[#22c55e]{result_preview}[/]")
                else:
                    tool_node.add_leaf(f"[#94a3b8]{result_preview}[/]")

    def _format_tool_input(self, tool_call: ToolCall) -> str:
        """Format tool input for display."""
        if not tool_call.input:
            return ""

        # Handle common tool types
        if tool_call.name == "Read":
            return tool_call.input.get("file_path", "")[:60]
        elif tool_call.name == "Write":
            path = tool_call.input.get("file_path", "")
            return f"{path[:50]}..."
        elif tool_call.name == "Edit":
            path = tool_call.input.get("file_path", "")
            return path[:60]
        elif tool_call.name == "Bash":
            cmd = tool_call.input.get("command", "")
            return truncate_text(cmd, 60)
        elif tool_call.name == "Glob":
            return tool_call.input.get("pattern", "")[:60]
        elif tool_call.name == "Grep":
            return tool_call.input.get("pattern", "")[:60]
        elif tool_call.name == "TodoWrite":
            todos = tool_call.input.get("todos", [])
            return f"{len(todos)} todos"
        else:
            # Generic handling
            first_key = next(iter(tool_call.input.keys()), None)
            if first_key:
                value = str(tool_call.input[first_key])
                return truncate_text(value, 60)
        return ""

    def _update_header(self) -> None:
        """Update header with current worker info."""
        try:
            header = self.query_one("#conv-header", Static)
            if self.conversation:
                summary = get_conversation_summary(self.conversation)
                header.update(
                    f"[bold]Conversation[/] │ {self.current_worker} │ "
                    f"{summary['turns']} turns │ ${summary['cost_usd']:.2f}"
                )
            else:
                header.update("[bold]Conversation[/] │ Select a worker")
        except Exception:
            pass

    def on_select_changed(self, event: Select.Changed) -> None:
        """Handle worker selection change."""
        if event.select.id == "worker-select" and event.value:
            self._load_conversation(str(event.value))

    def refresh_data(self) -> None:
        """Refresh conversation data."""
        if self.current_worker:
            self._load_conversation(self.current_worker)

    def select_worker(self, worker_id: str) -> None:
        """Select a specific worker programmatically."""
        try:
            select = self.query_one("#worker-select", Select)
            select.value = worker_id
            self._load_conversation(worker_id)
        except Exception:
            pass
