"""Main Textual application for Wiggum TUI."""

from pathlib import Path
from datetime import datetime

from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Container, Horizontal, Vertical
from textual.widgets import Header, Footer, Static, TabbedContent, TabPane

from .themes.htop import HTOP_THEME
from .widgets.kanban_panel import KanbanPanel
from .widgets.workers_panel import WorkersPanel
from .widgets.logs_panel import LogsPanel
from .widgets.metrics_panel import MetricsPanel
from .widgets.conversation_panel import ConversationPanel
from .data.watcher import RalphWatcher


class WiggumHeader(Static):
    """Custom header showing project info and stats."""

    DEFAULT_CSS = """
    WiggumHeader {
        background: #1e293b;
        color: #e2e8f0;
        height: 1;
        dock: top;
        padding: 0 1;
    }
    """

    def __init__(self, ralph_dir: Path) -> None:
        super().__init__("")
        self.ralph_dir = ralph_dir
        self.project_dir = ralph_dir.parent
        self.update(self._render_header())

    def _render_header(self) -> str:
        time_str = datetime.now().strftime("%H:%M:%S")
        project_name = self.project_dir.name
        return f" WIGGUM MONITOR │ {project_name} │ {time_str}"

    def update_header(self) -> None:
        """Update header content."""
        self.update(self._render_header())


class WiggumApp(App):
    """Main Wiggum TUI application."""

    TITLE = "Wiggum Monitor"
    CSS = HTOP_THEME

    BINDINGS = [
        Binding("q", "quit", "Quit"),
        Binding("1", "switch_tab('kanban')", "Kanban", show=True),
        Binding("2", "switch_tab('workers')", "Workers", show=True),
        Binding("3", "switch_tab('logs')", "Logs", show=True),
        Binding("4", "switch_tab('metrics')", "Metrics", show=True),
        Binding("5", "switch_tab('conversations')", "Chat", show=True),
        Binding("r", "refresh", "Refresh"),
        Binding("?", "help", "Help"),
    ]

    def __init__(self, ralph_dir: Path) -> None:
        super().__init__()
        self.ralph_dir = ralph_dir
        self.watcher = RalphWatcher(ralph_dir)

    def compose(self) -> ComposeResult:
        yield WiggumHeader(self.ralph_dir)
        with TabbedContent(initial="workers"):
            with TabPane("Kanban", id="kanban"):
                yield KanbanPanel(self.ralph_dir)
            with TabPane("Workers", id="workers"):
                yield WorkersPanel(self.ralph_dir)
            with TabPane("Logs", id="logs"):
                yield LogsPanel(self.ralph_dir)
            with TabPane("Metrics", id="metrics"):
                yield MetricsPanel(self.ralph_dir)
            with TabPane("Conversations", id="conversations"):
                yield ConversationPanel(self.ralph_dir)
        yield Footer()

    async def on_mount(self) -> None:
        """Start file watcher on mount."""
        # Register callbacks for each panel
        self.watcher.on_kanban_change(self._on_kanban_change)
        self.watcher.on_workers_change(self._on_workers_change)
        self.watcher.on_logs_change(self._on_logs_change)
        self.watcher.on_metrics_change(self._on_metrics_change)

        # Start watching
        self.watcher.start()

        # Set up header update timer
        self.set_interval(1, self._update_header)

    def on_unmount(self) -> None:
        """Stop file watcher on unmount."""
        self.watcher.stop()

    async def _on_kanban_change(self) -> None:
        """Handle kanban.md changes."""
        try:
            panel = self.query_one(KanbanPanel)
            panel.refresh_data()
        except Exception:
            pass

    async def _on_workers_change(self) -> None:
        """Handle workers directory changes."""
        try:
            panel = self.query_one(WorkersPanel)
            panel.refresh_data()
        except Exception:
            pass

    async def _on_logs_change(self) -> None:
        """Handle log file changes."""
        try:
            panel = self.query_one(LogsPanel)
            panel.refresh_data()
        except Exception:
            pass

    async def _on_metrics_change(self) -> None:
        """Handle metrics.json changes."""
        try:
            panel = self.query_one(MetricsPanel)
            panel.refresh_data()
        except Exception:
            pass

    def _update_header(self) -> None:
        """Update header time."""
        try:
            header = self.query_one(WiggumHeader)
            header.update_header()
        except Exception:
            pass

    def action_switch_tab(self, tab_id: str) -> None:
        """Switch to a specific tab."""
        tabbed = self.query_one(TabbedContent)
        tabbed.active = tab_id

    def action_refresh(self) -> None:
        """Manually refresh all panels."""
        try:
            self.query_one(KanbanPanel).refresh_data()
        except Exception:
            pass
        try:
            self.query_one(WorkersPanel).refresh_data()
        except Exception:
            pass
        try:
            self.query_one(LogsPanel).refresh_data()
        except Exception:
            pass
        try:
            self.query_one(MetricsPanel).refresh_data()
        except Exception:
            pass

    def action_help(self) -> None:
        """Show help dialog."""
        self.notify(
            "Keyboard shortcuts:\n"
            "1-5: Switch tabs │ r: Refresh │ q: Quit\n"
            "s: Stop worker │ k: Kill worker │ c: View chat",
            title="Help",
            timeout=5,
        )
