"""
extract_data.py — Extract rental data from PostgreSQL and convert to text Documents.
Tables: tenants, properties, payments, leases, ledger_entries
"""

import os
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional

from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine


@dataclass
class Document:
    text: str
    metadata: dict = field(default_factory=dict)


def get_engine() -> Engine:
    db_url = (
        f"postgresql+psycopg2://{os.environ['DB_USER']}:{os.environ['DB_PASSWORD']}"
        f"@{os.environ['DB_HOST']}:{os.environ.get('DB_PORT', '5432')}/{os.environ['DB_NAME']}"
    )
    return create_engine(db_url, pool_pre_ping=True)


def extract_payments(engine: Engine, since: Optional[datetime] = None) -> list[Document]:
    query = """
        SELECT p.id, p.amount, p.currency, p.status, p.payment_date,
               t.full_name AS tenant_name, t.id AS tenant_id,
               pr.address AS property_address
        FROM payments p
        JOIN leases l ON p.lease_id = l.id
        JOIN tenants t ON l.tenant_id = t.id
        JOIN properties pr ON l.property_id = pr.id
        WHERE (:since IS NULL OR p.updated_at >= :since)
        ORDER BY p.payment_date DESC
    """
    docs = []
    with engine.connect() as conn:
        rows = conn.execute(text(query), {"since": since}).fetchall()
        for row in rows:
            text_repr = (
                f"Tenant {row.tenant_name} paid {row.currency} {row.amount:,.2f} "
                f"on {row.payment_date} for property {row.property_address}. "
                f"Payment status: {row.status}."
            )
            docs.append(Document(
                text=text_repr,
                metadata={
                    "table": "payments", "id": str(row.id),
                    "date": str(row.payment_date), "tenant_id": str(row.tenant_id),
                    "status": row.status, "amount": float(row.amount),
                }
            ))
    return docs


def extract_leases(engine: Engine, since: Optional[datetime] = None) -> list[Document]:
    query = """
        SELECT l.id, l.start_date, l.end_date, l.monthly_rent, l.currency, l.status,
               t.full_name AS tenant_name, t.id AS tenant_id,
               pr.address AS property_address
        FROM leases l
        JOIN tenants t ON l.tenant_id = t.id
        JOIN properties pr ON l.property_id = pr.id
        WHERE (:since IS NULL OR l.updated_at >= :since)
    """
    docs = []
    with engine.connect() as conn:
        rows = conn.execute(text(query), {"since": since}).fetchall()
        for row in rows:
            text_repr = (
                f"Lease for {row.tenant_name} at {row.property_address}: "
                f"{row.start_date} to {row.end_date}. "
                f"Monthly rent: {row.currency} {row.monthly_rent:,.2f}. "
                f"Lease status: {row.status}."
            )
            docs.append(Document(
                text=text_repr,
                metadata={
                    "table": "leases", "id": str(row.id),
                    "date": str(row.start_date), "tenant_id": str(row.tenant_id),
                    "status": row.status,
                }
            ))
    return docs


def extract_ledger_entries(engine: Engine, since: Optional[datetime] = None) -> list[Document]:
    query = """
        SELECT le.id, le.entry_type, le.amount, le.currency, le.description,
               le.entry_date, le.reference_id,
               t.full_name AS tenant_name, t.id AS tenant_id
        FROM ledger_entries le
        LEFT JOIN tenants t ON le.tenant_id = t.id
        WHERE (:since IS NULL OR le.updated_at >= :since)
        ORDER BY le.entry_date DESC
    """
    docs = []
    with engine.connect() as conn:
        rows = conn.execute(text(query), {"since": since}).fetchall()
        for row in rows:
            tenant_part = f" for tenant {row.tenant_name}" if row.tenant_name else ""
            text_repr = (
                f"Ledger entry [{row.entry_type}]{tenant_part}: "
                f"{row.currency} {row.amount:,.2f} on {row.entry_date}. "
                f"Description: {row.description}. Reference: {row.reference_id}."
            )
            docs.append(Document(
                text=text_repr,
                metadata={
                    "table": "ledger_entries", "id": str(row.id),
                    "date": str(row.entry_date), "tenant_id": str(row.tenant_id or ""),
                    "entry_type": row.entry_type,
                }
            ))
    return docs


def extract_all_documents(since: Optional[datetime] = None) -> list[Document]:
    """Extract all rental documents from PostgreSQL since the given datetime (or all if None)."""
    engine = get_engine()
    docs = []
    docs.extend(extract_payments(engine, since))
    docs.extend(extract_leases(engine, since))
    docs.extend(extract_ledger_entries(engine, since))
    engine.dispose()
    return docs
