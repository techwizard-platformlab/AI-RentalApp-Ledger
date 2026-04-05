"""
seed_test_data.py — Insert sample data into PostgreSQL for local dev and CI testing.
20 tenants, 20 properties, 50 payments (mix of paid/overdue)
Run: python seed_test_data.py
"""

import os
import random
from datetime import date, timedelta

from sqlalchemy import create_engine, text


def get_engine():
    url = (
        f"postgresql+psycopg2://{os.environ.get('DB_USER','rentaluser')}:"
        f"{os.environ.get('DB_PASSWORD','rentalpass')}"
        f"@{os.environ.get('DB_HOST','localhost')}:5432/"
        f"{os.environ.get('DB_NAME','rentaldb')}"
    )
    return create_engine(url)


TENANT_NAMES = [
    "John Smith", "Alice Johnson", "Bob Williams", "Carol Brown", "David Jones",
    "Eva Garcia", "Frank Miller", "Grace Wilson", "Henry Moore", "Iris Taylor",
    "James Anderson", "Karen Thomas", "Liam Jackson", "Mia White", "Noah Harris",
    "Olivia Martin", "Peter Thompson", "Quinn Martinez", "Rachel Robinson", "Sam Clark",
]

STREETS = [
    "123 Main St", "456 Oak Ave", "789 Pine Rd", "101 Maple Dr", "202 Elm Blvd",
    "303 Cedar Ln", "404 Birch Way", "505 Walnut St", "606 Spruce Ave", "707 Ash Rd",
    "808 Willow Ct", "909 Poplar Pl", "111 Chestnut St", "222 Hickory Ln", "333 Sycamore Dr",
    "444 Magnolia Ave", "555 Dogwood Rd", "666 Cypress Blvd", "777 Pecan Way", "888 Redwood St",
]


def seed(engine):
    with engine.begin() as conn:
        # Create tables if not exist
        conn.execute(text("""
            CREATE TABLE IF NOT EXISTS tenants (
                id SERIAL PRIMARY KEY, full_name TEXT NOT NULL,
                email TEXT, phone TEXT, created_at TIMESTAMP DEFAULT NOW(), updated_at TIMESTAMP DEFAULT NOW()
            );
            CREATE TABLE IF NOT EXISTS properties (
                id SERIAL PRIMARY KEY, address TEXT NOT NULL, city TEXT DEFAULT 'Austin',
                monthly_rent NUMERIC(10,2) DEFAULT 1500.00,
                created_at TIMESTAMP DEFAULT NOW(), updated_at TIMESTAMP DEFAULT NOW()
            );
            CREATE TABLE IF NOT EXISTS leases (
                id SERIAL PRIMARY KEY, tenant_id INT REFERENCES tenants(id),
                property_id INT REFERENCES properties(id),
                start_date DATE, end_date DATE,
                monthly_rent NUMERIC(10,2), currency TEXT DEFAULT 'USD', status TEXT DEFAULT 'active',
                created_at TIMESTAMP DEFAULT NOW(), updated_at TIMESTAMP DEFAULT NOW()
            );
            CREATE TABLE IF NOT EXISTS payments (
                id SERIAL PRIMARY KEY, lease_id INT REFERENCES leases(id),
                amount NUMERIC(10,2), currency TEXT DEFAULT 'USD',
                status TEXT, payment_date DATE,
                created_at TIMESTAMP DEFAULT NOW(), updated_at TIMESTAMP DEFAULT NOW()
            );
            CREATE TABLE IF NOT EXISTS ledger_entries (
                id SERIAL PRIMARY KEY, tenant_id INT REFERENCES tenants(id),
                entry_type TEXT, amount NUMERIC(10,2), currency TEXT DEFAULT 'USD',
                description TEXT, entry_date DATE, reference_id TEXT,
                created_at TIMESTAMP DEFAULT NOW(), updated_at TIMESTAMP DEFAULT NOW()
            );
        """))

        # Tenants
        tenant_ids = []
        for name in TENANT_NAMES:
            first = name.split()[0].lower()
            row = conn.execute(text(
                "INSERT INTO tenants (full_name, email, phone) VALUES (:n, :e, :p) RETURNING id"
            ), {"n": name, "e": f"{first}@example.com", "p": f"555-{random.randint(1000,9999)}"})
            tenant_ids.append(row.scalar())

        # Properties
        property_ids = []
        for addr in STREETS:
            rent = random.choice([1200, 1500, 1800, 2000, 2200])
            row = conn.execute(text(
                "INSERT INTO properties (address, monthly_rent) VALUES (:a, :r) RETURNING id"
            ), {"a": addr, "r": rent})
            property_ids.append(row.scalar())

        # Leases (one per tenant)
        lease_ids = []
        for i, tid in enumerate(tenant_ids):
            pid = property_ids[i]
            start = date.today() - timedelta(days=random.randint(30, 365))
            end = start + timedelta(days=365)
            rent = 1500 + random.randint(0, 10) * 100
            row = conn.execute(text(
                "INSERT INTO leases (tenant_id, property_id, start_date, end_date, monthly_rent) "
                "VALUES (:tid, :pid, :s, :e, :r) RETURNING id"
            ), {"tid": tid, "pid": pid, "s": start, "e": end, "r": rent})
            lease_ids.append(row.scalar())

        # Payments (50 total, mix of paid/overdue)
        statuses = ["paid"] * 35 + ["overdue"] * 10 + ["pending"] * 5
        random.shuffle(statuses)
        for i in range(50):
            lid = random.choice(lease_ids)
            amount = 1500 + random.randint(-200, 500)
            pay_date = date.today() - timedelta(days=random.randint(0, 90))
            status = statuses[i]
            conn.execute(text(
                "INSERT INTO payments (lease_id, amount, status, payment_date) VALUES (:l, :a, :s, :d)"
            ), {"l": lid, "a": amount, "s": status, "d": pay_date})

        # Ledger entries (one per payment approximately)
        for tid in tenant_ids[:10]:
            conn.execute(text(
                "INSERT INTO ledger_entries (tenant_id, entry_type, amount, description, entry_date, reference_id) "
                "VALUES (:t, :et, :a, :d, :ed, :r)"
            ), {
                "t": tid, "et": random.choice(["credit", "debit"]),
                "a": round(random.uniform(500, 2500), 2),
                "d": f"Monthly rent payment for {date.today().strftime('%B %Y')}",
                "ed": date.today() - timedelta(days=random.randint(0, 30)),
                "r": f"PAY-{random.randint(10000, 99999)}",
            })

    print(f"Seeded: {len(tenant_ids)} tenants, {len(property_ids)} properties, "
          f"{len(lease_ids)} leases, 50 payments, 10 ledger entries.")


if __name__ == "__main__":
    seed(get_engine())
