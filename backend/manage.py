"""Database setup for local development, CI and hosted PostgreSQL."""
import argparse
from .database import make_engine, migrate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['migrate', 'check'])
    args = parser.parse_args()
    engine = make_engine()
    try:
        if args.command == 'migrate':
            migrate(engine)
            print(f'Attendance v2 schema ready ({engine.dialect.name}). Existing demo data retained.')
        else:
            from sqlalchemy import select
            with engine.connect() as conn:
                conn.execute(select(1))
            print(f'Database connection OK ({engine.dialect.name})')
    finally:
        engine.dispose()


if __name__ == '__main__':
    main()
