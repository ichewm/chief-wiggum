"""Logs panel widget with filtering and real-time updates."""

from pathlib import Path
from textual.app import ComposeResult
from textual.containers import Horizontal
from textual.widgets import Static, RichLog, Select
from textual.widget import Widget
from textual.binding import Binding

from ..data.log_reader import LogTailer, filter_by_level, read_log
from ..data.models import LogLevel


class LogsPanel(Widget):
    """Logs panel showing log files with filtering."""

    DEFAULT_CSS = """
    LogsPanel {
        height: 1fr;
        width: 100%;
        layout: vertical;
    }

    LogsPanel .logs-header {
        height: 1;
        background: #1e293b;
        padding: 0 1;
    }

    LogsPanel .logs-controls {
        height: 3;
        background: #1e293b;
        padding: 0 1;
    }

    LogsPanel RichLog {
        height: 1fr;
        background: #0f172a;
        border: solid #334155;
    }

    LogsPanel Select {
        width: 20;
        margin-right: 2;
    }
    """

    BINDINGS = [
        Binding("f", "cycle_filter", "Filter"),
        Binding("g", "goto_top", "Top"),
        Binding("G", "goto_bottom", "Bottom"),
    ]

    LOG_SOURCES = [
        ("combined", "Combined Logs"),
        ("audit", "Audit Logs"),
    ]

    FILTER_LEVELS = [
        (None, "All Levels"),
        (LogLevel.INFO, "INFO+"),
        (LogLevel.WARN, "WARN+"),
        (LogLevel.ERROR, "ERROR only"),
    ]

    def __init__(self, ralph_dir: Path) -> None:
        super().__init__()
        self.ralph_dir = ralph_dir
        self.current_source = "combined"
        self.current_filter_idx = 0
        self.tailer: LogTailer | None = None

    def compose(self) -> ComposeResult:
        yield Static(
            "[bold]Logs[/] │ Source: Combined │ Filter: All",
            classes="logs-header",
            id="logs-header",
        )

        with Horizontal(classes="logs-controls"):
            yield Select(
                [(label, value) for value, label in self.LOG_SOURCES],
                value="combined",
                id="source-select",
            )
            yield Select(
                [
                    (label, str(i))
                    for i, (_, label) in enumerate(self.FILTER_LEVELS)
                ],
                value="0",
                id="filter-select",
            )

        yield RichLog(id="log-viewer", highlight=True, markup=True)

    def on_mount(self) -> None:
        """Initialize log viewer."""
        self._setup_tailer()
        self._load_logs()
        # Set up periodic refresh
        self.set_interval(2, self._check_new_logs)

    def _get_log_path(self) -> Path:
        """Get path for current log source."""
        if self.current_source == "combined":
            return self.ralph_dir / "logs" / "workers.log"
        elif self.current_source == "audit":
            return self.ralph_dir / "logs" / "audit.log"
        return self.ralph_dir / "logs" / "workers.log"

    def _setup_tailer(self) -> None:
        """Set up log tailer for current source."""
        log_path = self._get_log_path()
        self.tailer = LogTailer(log_path, max_buffer=1000)

    def _load_logs(self) -> None:
        """Load and display logs."""
        if not self.tailer:
            return

        try:
            log_viewer = self.query_one("#log-viewer", RichLog)
            log_viewer.clear()

            logs = self.tailer.get_new_lines()

            # Apply filter
            min_level = self.FILTER_LEVELS[self.current_filter_idx][0]
            if min_level:
                logs = filter_by_level(logs, min_level)

            for log in logs:
                self._write_log_line(log_viewer, log)

        except Exception:
            pass

    def _write_log_line(self, viewer: RichLog, log) -> None:
        """Write a single log line with coloring."""
        if log.level:
            level_colors = {
                LogLevel.DEBUG: "#64748b",
                LogLevel.INFO: "#3b82f6",
                LogLevel.WARN: "#eab308",
                LogLevel.ERROR: "#dc2626",
            }
            color = level_colors.get(log.level, "#e2e8f0")

            timestamp = f"[#64748b]{log.timestamp}[/]" if log.timestamp else ""
            level = f"[{color}]{log.level.value}[/]"
            message = f"[#e2e8f0]{log.message}[/]"

            viewer.write(f"{timestamp} {level}: {message}")
        else:
            viewer.write(f"[#64748b]{log.raw}[/]")

    def _check_new_logs(self) -> None:
        """Check for and display new log lines."""
        if not self.tailer:
            return

        try:
            new_logs = self.tailer.get_new_lines()
            if not new_logs:
                return

            log_viewer = self.query_one("#log-viewer", RichLog)

            # Apply filter
            min_level = self.FILTER_LEVELS[self.current_filter_idx][0]
            if min_level:
                new_logs = filter_by_level(new_logs, min_level)

            for log in new_logs:
                self._write_log_line(log_viewer, log)

        except Exception:
            pass

    def _update_header(self) -> None:
        """Update header with current settings."""
        try:
            source_name = dict(self.LOG_SOURCES).get(self.current_source, "Unknown")
            filter_name = self.FILTER_LEVELS[self.current_filter_idx][1]

            header = self.query_one("#logs-header", Static)
            header.update(f"[bold]Logs[/] │ Source: {source_name} │ Filter: {filter_name}")
        except Exception:
            pass

    def on_select_changed(self, event: Select.Changed) -> None:
        """Handle source/filter selection change."""
        if event.select.id == "source-select":
            self.current_source = str(event.value)
            self._setup_tailer()
            self._load_logs()
            self._update_header()
        elif event.select.id == "filter-select":
            self.current_filter_idx = int(event.value)
            self._load_logs()
            self._update_header()

    def action_cycle_filter(self) -> None:
        """Cycle through filter levels."""
        self.current_filter_idx = (self.current_filter_idx + 1) % len(self.FILTER_LEVELS)

        try:
            select = self.query_one("#filter-select", Select)
            select.value = str(self.current_filter_idx)
        except Exception:
            pass

        self._load_logs()
        self._update_header()

    def action_goto_top(self) -> None:
        """Scroll to top of logs."""
        try:
            log_viewer = self.query_one("#log-viewer", RichLog)
            log_viewer.scroll_home()
        except Exception:
            pass

    def action_goto_bottom(self) -> None:
        """Scroll to bottom of logs."""
        try:
            log_viewer = self.query_one("#log-viewer", RichLog)
            log_viewer.scroll_end()
        except Exception:
            pass

    def refresh_data(self) -> None:
        """Refresh log display."""
        self._check_new_logs()
