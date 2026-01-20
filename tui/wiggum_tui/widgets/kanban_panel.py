"""Kanban board panel widget."""

from pathlib import Path
from textual.app import ComposeResult
from textual.containers import Horizontal, Vertical, VerticalScroll
from textual.widgets import Static
from textual.widget import Widget

from ..data.kanban_parser import parse_kanban, group_tasks_by_status
from ..data.models import Task, TaskStatus


class TaskCard(Static):
    """A single task card in the kanban board."""

    DEFAULT_CSS = """
    TaskCard {
        background: #1e293b;
        border: solid #334155;
        margin: 0 0 1 0;
        padding: 0 1;
        height: auto;
        min-height: 3;
    }

    TaskCard:hover {
        border: solid #f59e0b;
    }

    TaskCard .task-id {
        color: #f59e0b;
        text-style: bold;
    }

    TaskCard .task-title {
        color: #e2e8f0;
    }

    TaskCard .task-priority-critical {
        color: #dc2626;
    }

    TaskCard .task-priority-high {
        color: #f59e0b;
    }

    TaskCard .task-priority-medium {
        color: #3b82f6;
    }

    TaskCard .task-priority-low {
        color: #64748b;
    }
    """

    def __init__(self, task_data: Task) -> None:
        super().__init__()
        self._task_data = task_data

    def render(self) -> str:
        """Render task card content."""
        priority_class = f"task-priority-{self._task_data.priority.lower()}"
        priority_indicator = {
            "CRITICAL": "!!!",
            "HIGH": "!!",
            "MEDIUM": "!",
            "LOW": "",
        }.get(self._task_data.priority, "")

        title = self._task_data.title
        if len(title) > 30:
            title = title[:27] + "..."

        lines = [
            f"[bold #f59e0b]{self._task_data.id}[/] [{priority_class}]{priority_indicator}[/]",
            f"[#e2e8f0]{title}[/]",
        ]
        return "\n".join(lines)


class KanbanColumn(Widget):
    """A single column in the kanban board."""

    DEFAULT_CSS = """
    KanbanColumn {
        width: 1fr;
        height: 100%;
        border: solid #334155;
    }

    KanbanColumn .column-header {
        background: #1e293b;
        text-align: center;
        text-style: bold;
        height: 1;
        padding: 0 1;
    }

    KanbanColumn .column-header-pending {
        color: #94a3b8;
    }

    KanbanColumn .column-header-in_progress {
        color: #f59e0b;
    }

    KanbanColumn .column-header-complete {
        color: #22c55e;
    }

    KanbanColumn .column-header-failed {
        color: #dc2626;
    }

    KanbanColumn .column-content {
        padding: 1;
    }
    """

    def __init__(self, status: TaskStatus, tasks_list: list[Task]) -> None:
        super().__init__()
        self._status = status
        self._tasks_list = tasks_list

    def compose(self) -> ComposeResult:
        status_name = self._status.value.replace("_", " ").upper()
        header_class = f"column-header-{self._status.value}"
        yield Static(
            f"[{header_class}]{status_name} ({len(self._tasks_list)})[/]",
            classes="column-header",
        )
        with VerticalScroll(classes="column-content"):
            for task_item in self._tasks_list:
                yield TaskCard(task_item)


class KanbanPanel(Widget):
    """Kanban board panel showing tasks in columns."""

    DEFAULT_CSS = """
    KanbanPanel {
        height: 1fr;
        width: 100%;
        layout: horizontal;
    }

    KanbanPanel .kanban-board {
        height: 1fr;
        width: 100%;
    }

    KanbanPanel .empty-message {
        text-align: center;
        color: #64748b;
        padding: 2;
    }
    """

    def __init__(self, ralph_dir: Path) -> None:
        super().__init__()
        self.ralph_dir = ralph_dir
        self.kanban_path = ralph_dir / "kanban.md"
        self._tasks_list: list[Task] = []

    def compose(self) -> ComposeResult:
        self._load_tasks()

        if not self._tasks_list:
            yield Static(
                "No tasks found. Create .ralph/kanban.md to add tasks.",
                classes="empty-message",
            )
            return

        grouped = group_tasks_by_status(self._tasks_list)

        with Horizontal(classes="kanban-board"):
            yield KanbanColumn(TaskStatus.PENDING, grouped[TaskStatus.PENDING])
            yield KanbanColumn(TaskStatus.IN_PROGRESS, grouped[TaskStatus.IN_PROGRESS])
            yield KanbanColumn(TaskStatus.COMPLETE, grouped[TaskStatus.COMPLETE])
            yield KanbanColumn(TaskStatus.FAILED, grouped[TaskStatus.FAILED])

    def _load_tasks(self) -> None:
        """Load tasks from kanban.md."""
        self._tasks_list = parse_kanban(self.kanban_path)

    def refresh_data(self) -> None:
        """Refresh task data and re-render."""
        self._load_tasks()
        # Remove old content and recompose
        self.remove_children()
        for widget in self.compose():
            self.mount(widget)
