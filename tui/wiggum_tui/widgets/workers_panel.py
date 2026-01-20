"""Workers panel widget with DataTable."""

from pathlib import Path
from datetime import datetime
from textual.app import ComposeResult
from textual.widgets import DataTable, Static
from textual.widget import Widget
from textual.binding import Binding
from textual.message import Message

from ..data.worker_scanner import scan_workers, get_worker_counts
from ..data.models import Worker, WorkerStatus
from ..actions.worker_control import stop_worker, kill_worker


class WorkersPanel(Widget):
    """Workers panel showing all workers in a table."""

    DEFAULT_CSS = """
    WorkersPanel {
        height: 1fr;
        width: 100%;
        layout: vertical;
    }

    WorkersPanel .workers-header {
        height: 1;
        background: #1e293b;
        padding: 0 1;
    }

    WorkersPanel DataTable {
        height: 1fr;
    }

    WorkersPanel .empty-message {
        text-align: center;
        color: #64748b;
        padding: 2;
    }
    """

    BINDINGS = [
        Binding("s", "stop_worker", "Stop"),
        Binding("k", "kill_worker", "Kill"),
        Binding("c", "view_conversation", "View Chat"),
        Binding("l", "view_logs", "View Logs"),
    ]

    class WorkerSelected(Message):
        """Message sent when a worker is selected."""

        def __init__(self, worker: Worker) -> None:
            super().__init__()
            self.worker = worker

    def __init__(self, ralph_dir: Path) -> None:
        super().__init__()
        self.ralph_dir = ralph_dir
        self._workers_list: list[Worker] = []
        self._selected_worker: Worker | None = None

    def compose(self) -> ComposeResult:
        self._load_workers()
        counts = get_worker_counts(self._workers_list)

        yield Static(
            f"[bold]Workers[/] │ "
            f"[#22c55e]Running: {counts['running']}[/] │ "
            f"[#3b82f6]Completed: {counts['completed']}[/] │ "
            f"[#dc2626]Failed: {counts['failed']}[/] │ "
            f"Total: {counts['total']}",
            classes="workers-header",
        )

        if not self._workers_list:
            yield Static(
                "No workers found. Run 'wiggum run' to start workers.",
                classes="empty-message",
            )
            return

        table = DataTable(id="workers-table")
        table.cursor_type = "row"
        table.zebra_stripes = True
        yield table

    def on_mount(self) -> None:
        """Set up the data table."""
        if not self._workers_list:
            return
        try:
            table = self.query_one("#workers-table", DataTable)
            table.add_columns("Status", "Worker ID", "Task", "PID", "Started", "PR URL")
            self._populate_table(table)
        except Exception as e:
            self.log.error(f"Failed to populate workers table: {e}")

    def _load_workers(self) -> None:
        """Load workers from .ralph/workers directory."""
        self._workers_list = scan_workers(self.ralph_dir)

    def _populate_table(self, table: DataTable) -> None:
        """Populate the table with worker data."""
        table.clear()
        for worker in self._workers_list:
            status_style = self._get_status_style(worker.status)
            status_text = f"[{status_style}]{worker.status.value.upper()}[/]"

            # Format timestamp
            try:
                dt = datetime.fromtimestamp(worker.timestamp)
                started = dt.strftime("%H:%M:%S")
            except (ValueError, OSError):
                started = "Unknown"

            # Format PID
            pid_str = str(worker.pid) if worker.pid else "-"

            # Truncate worker ID and PR URL for display
            worker_id = worker.id
            if len(worker_id) > 25:
                worker_id = worker_id[:22] + "..."

            pr_url = worker.pr_url or ""
            if len(pr_url) > 30:
                pr_url = pr_url[:27] + "..."

            table.add_row(
                status_text,
                worker_id,
                worker.task_id,
                pid_str,
                started,
                pr_url,
                key=worker.id,
            )

    def _get_status_style(self, status: WorkerStatus) -> str:
        """Get Rich style for a status."""
        return {
            WorkerStatus.RUNNING: "#22c55e",
            WorkerStatus.STOPPED: "#64748b",
            WorkerStatus.COMPLETED: "#3b82f6",
            WorkerStatus.FAILED: "#dc2626",
        }.get(status, "#64748b")

    def _get_selected_worker(self) -> Worker | None:
        """Get the currently selected worker."""
        try:
            table = self.query_one("#workers-table", DataTable)
            if table.cursor_row is not None and table.cursor_row < len(self._workers_list):
                return self._workers_list[table.cursor_row]
        except Exception:
            pass
        return None

    def action_stop_worker(self) -> None:
        """Stop the selected worker."""
        worker = self._get_selected_worker()
        if not worker:
            self.app.notify("No worker selected", severity="warning")
            return

        if worker.status != WorkerStatus.RUNNING:
            self.app.notify("Worker is not running", severity="warning")
            return

        if worker.pid:
            if stop_worker(worker.pid):
                self.app.notify(f"Sent SIGTERM to {worker.id}")
                self.refresh_data()
            else:
                self.app.notify(f"Failed to stop {worker.id}", severity="error")

    def action_kill_worker(self) -> None:
        """Kill the selected worker."""
        worker = self._get_selected_worker()
        if not worker:
            self.app.notify("No worker selected", severity="warning")
            return

        if worker.status != WorkerStatus.RUNNING:
            self.app.notify("Worker is not running", severity="warning")
            return

        if worker.pid:
            if kill_worker(worker.pid):
                self.app.notify(f"Sent SIGKILL to {worker.id}")
                self.refresh_data()
            else:
                self.app.notify(f"Failed to kill {worker.id}", severity="error")

    def action_view_conversation(self) -> None:
        """View conversation for selected worker."""
        worker = self._get_selected_worker()
        if worker:
            # Switch to conversations tab and select this worker
            self.app.action_switch_tab("conversations")
            self.post_message(self.WorkerSelected(worker))

    def action_view_logs(self) -> None:
        """View logs for selected worker."""
        worker = self._get_selected_worker()
        if worker:
            self.app.action_switch_tab("logs")
            # Could emit a message to switch log source

    def refresh_data(self) -> None:
        """Refresh worker data and re-render."""
        self._load_workers()

        # Update header
        try:
            counts = get_worker_counts(self._workers_list)
            header = self.query_one(".workers-header", Static)
            header.update(
                f"[bold]Workers[/] │ "
                f"[#22c55e]Running: {counts['running']}[/] │ "
                f"[#3b82f6]Completed: {counts['completed']}[/] │ "
                f"[#dc2626]Failed: {counts['failed']}[/] │ "
                f"Total: {counts['total']}"
            )
        except Exception:
            pass

        # Update table
        try:
            table = self.query_one("#workers-table", DataTable)
            self._populate_table(table)
        except Exception:
            pass
