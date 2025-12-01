"""BigQuery repository implementation."""

import os
from pathlib import Path
from typing import Any

from google.cloud import bigquery

from src.repository import Repository


class BigQueryRepository:
    """BigQuery implementation of Repository interface."""

    def __init__(self, project_id: str, dataset_id: str = "shift_data"):
        """Initialize BigQuery repository.

        Args:
            project_id: GCP project ID
            dataset_id: BigQuery dataset ID (default: shift_data)
        """
        self.project_id = project_id
        self.dataset_id = dataset_id
        self.client = bigquery.Client(project=project_id)

    def execute_query(self, query: str, verbose: bool = True) -> Any:
        """Execute a SQL query and return results.

        Args:
            query: SQL query string
            verbose: Whether to print the query

        Returns:
            Query job result
        """
        if verbose:
            print(f"[BigQuery] Executing query:\n{query}")

        query_job = self.client.query(query)
        return query_job.result()  # Waits for job to complete

    def execute_script(self, sql_file_path: str | Path, verbose: bool = True) -> None:
        """Execute a SQL script from a file.

        Args:
            sql_file_path: Path to SQL file
            verbose: Whether to print progress
        """
        sql_path = Path(sql_file_path)
        if not sql_path.is_absolute():
            # Resolve relative to project root
            base_path = Path(__file__).parent.parent.parent
            sql_path = base_path / sql_path

        sql_path = sql_path.resolve()

        if verbose:
            print(f"[BigQuery] Executing script: {sql_path}")

        try:
            with open(sql_path, "r") as f:
                sql_text = f.read()
                self.execute_query(sql_text, verbose=verbose)
        except FileNotFoundError:
            raise FileNotFoundError(f"SQL file not found: {sql_path}")
        except Exception as e:
            raise RuntimeError(f"Error executing script {sql_path}: {e}")

