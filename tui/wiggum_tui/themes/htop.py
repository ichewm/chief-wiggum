"""htop-inspired color scheme for wiggum TUI."""

COLORS = {
    # Status colors
    "running": "#22c55e",  # Green
    "stopped": "#64748b",  # Gray
    "completed": "#3b82f6",  # Blue
    "failed": "#dc2626",  # Red
    "pending": "#94a3b8",  # Light gray
    "in_progress": "#f59e0b",  # Amber
    # Log levels
    "debug": "#64748b",  # Gray
    "info": "#3b82f6",  # Blue
    "warn": "#eab308",  # Yellow
    "error": "#dc2626",  # Red
    # Priority
    "critical": "#dc2626",  # Red
    "high": "#f59e0b",  # Amber
    "medium": "#3b82f6",  # Blue
    "low": "#64748b",  # Gray
    # UI elements
    "header_bg": "#1e293b",
    "panel_bg": "#0f172a",
    "border": "#334155",
    "text": "#e2e8f0",
    "muted": "#64748b",
    "accent": "#f59e0b",
    "selected": "#1e40af",
}

# Textual CSS theme
HTOP_THEME = """
Screen {
    background: #0f172a;
}

Header {
    background: #1e293b;
    color: #e2e8f0;
    dock: top;
    height: 1;
}

Footer {
    background: #1e293b;
    color: #64748b;
    dock: bottom;
    height: 1;
}

.panel {
    background: #0f172a;
    border: solid #334155;
}

.panel-title {
    background: #1e293b;
    color: #f59e0b;
    text-style: bold;
}

DataTable {
    background: #0f172a;
}

DataTable > .datatable--header {
    background: #1e293b;
    color: #e2e8f0;
    text-style: bold;
}

DataTable > .datatable--cursor {
    background: #1e40af;
    color: #e2e8f0;
}

.status-running {
    color: #22c55e;
}

.status-stopped {
    color: #64748b;
}

.status-completed {
    color: #3b82f6;
}

.status-failed {
    color: #dc2626;
}

.status-pending {
    color: #94a3b8;
}

.status-in_progress {
    color: #f59e0b;
}

.log-debug {
    color: #64748b;
}

.log-info {
    color: #3b82f6;
}

.log-warn {
    color: #eab308;
}

.log-error {
    color: #dc2626;
}

.priority-critical {
    color: #dc2626;
    text-style: bold;
}

.priority-high {
    color: #f59e0b;
}

.priority-medium {
    color: #3b82f6;
}

.priority-low {
    color: #64748b;
}

TabbedContent {
    background: #0f172a;
    height: 1fr;
}

TabPane {
    background: #0f172a;
    padding: 0;
    height: 1fr;
}

ContentSwitcher {
    height: 1fr;
}

Tabs {
    background: #1e293b;
}

Tab {
    background: #1e293b;
    color: #64748b;
}

Tab.-active {
    background: #0f172a;
    color: #f59e0b;
    text-style: bold;
}

RichLog {
    background: #0f172a;
    scrollbar-background: #1e293b;
    scrollbar-color: #334155;
}

Tree {
    background: #0f172a;
}

Tree > .tree--cursor {
    background: #1e40af;
}

Select {
    background: #1e293b;
    border: solid #334155;
}

SelectCurrent {
    background: #1e293b;
}

SelectOverlay {
    background: #1e293b;
    border: solid #334155;
}

.metric-card {
    background: #1e293b;
    border: solid #334155;
    padding: 1;
    margin: 1;
}

.metric-value {
    color: #22c55e;
    text-style: bold;
}

.metric-label {
    color: #64748b;
}

.kanban-column {
    width: 1fr;
    height: 100%;
    border: solid #334155;
}

.kanban-header {
    background: #1e293b;
    color: #e2e8f0;
    text-align: center;
    text-style: bold;
    height: 1;
}

.kanban-task {
    background: #1e293b;
    border: solid #334155;
    margin: 0 1;
    padding: 0 1;
    height: auto;
}
"""
