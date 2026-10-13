"""
Beacon Point EMA - load the synthetic data into Databricks

This project contains synthetic data and analysis created for demonstration
purposes only. Beacon Point Emergency Management Agency is fictional.

Steps:
  1. Create the schema and volume (if they don't already exist)
  2. Upload the synthetic CSV files to the volume
  3. Create the tables, load them with COPY INTO and apply the row filter

Credentials come from the Databricks SDK's normal sources, so nothing is
stored in this file. On Posit Workbench with Databricks managed credentials,
use the "workbench" profile. Elsewhere, set DATABRICKS_HOST and
DATABRICKS_TOKEN, or a profile in ~/.databrickscfg.

Run from the databricks/ folder:
  uv run upload_to_databricks.py --warehouse-id <sql-warehouse-id> [--profile workbench]
"""

import argparse
import re
from pathlib import Path

from databricks.sdk import WorkspaceClient
from databricks.sdk.service.sql import StatementState

HERE = Path(__file__).resolve().parent
DATA_DIR = HERE.parent / "data"
DDL_FILE = HERE / "databricks_ddl.sql"
VOLUME_PATH = "/Volumes/sol_eng_demo_nickp/beacon_point_ci/raw_files"
CSV_FILES = [
    "synthetic-incidents.csv",
    "synthetic-survey-responses.csv",
    "synthetic-aar-observations.csv",
]


def read_statements(path: Path) -> list[str]:
    """Split the DDL file into statements, dropping comment-only lines."""
    sql = "\n".join(
        line for line in path.read_text().splitlines() if not line.strip().startswith("--")
    )
    return [s.strip() for s in sql.split(";") if s.strip()]


def run_sql(w: WorkspaceClient, warehouse_id: str, statement: str) -> None:
    first_line = statement.splitlines()[0]
    print(f"  {first_line[:90]}")
    result = w.statement_execution.execute_statement(
        statement=statement, warehouse_id=warehouse_id, wait_timeout="50s"
    )
    if result.status.state != StatementState.SUCCEEDED:
        error = result.status.error.message if result.status.error else result.status.state
        raise RuntimeError(f"Statement failed: {first_line}\n{error}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--warehouse-id", required=True, help="ID of the Databricks SQL warehouse to run SQL on")
    parser.add_argument("--profile", default=None, help="Databricks config profile, e.g. 'workbench'")
    args = parser.parse_args()

    missing = [f for f in CSV_FILES if not (DATA_DIR / f).exists()]
    if missing:
        raise SystemExit(f"Missing {missing}. Run `Rscript data/generate_data.R` from the project root first.")

    w = WorkspaceClient(profile=args.profile)
    print(f"Connected to {w.config.host} as {w.current_user.me().user_name}")

    statements = read_statements(DDL_FILE)
    setup = [s for s in statements if re.match(r"CREATE (SCHEMA|VOLUME)", s)]
    load = [s for s in statements if s not in setup]

    print("1. Creating schema and volume")
    for s in setup:
        run_sql(w, args.warehouse_id, s)

    print("2. Uploading synthetic CSV files")
    for name in CSV_FILES:
        with open(DATA_DIR / name, "rb") as f:
            w.files.upload(f"{VOLUME_PATH}/{name}", f, overwrite=True)
        print(f"  {VOLUME_PATH}/{name}")

    print("3. Creating tables, loading data and applying the row filter")
    for s in load:
        run_sql(w, args.warehouse_id, s)

    print("Done. Tables are in sol_eng_demo_nickp.beacon_point_ci")


if __name__ == "__main__":
    main()
