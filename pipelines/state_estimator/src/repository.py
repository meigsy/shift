"""Repository interface for database operations."""

from typing import Any, Protocol
from pathlib import Path


class Repository(Protocol):
    """Abstract interface for database operations."""

    def execute_query(self, query: str) -> Any:
        """Execute a SQL query and return results."""
        ...

    def execute_script(self, sql_file_path: str | Path) -> None:
        """Execute a SQL script from a file."""
        ...

