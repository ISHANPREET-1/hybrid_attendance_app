"""Database setup for local development, CI and hosted PostgreSQL."""
import argparse
from .database import make_engine, migrate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['migrate', 'check', 'bootstrap-admin'])
    parser.add_argument('--env-file', help='Read administrator settings from this file; database settings still come from the normal local environment')
    args = parser.parse_args()
    engine = make_engine()
    try:
        if args.command == 'migrate':
            migrate(engine)
            from .bootstrap import bootstrap_admin
            result = bootstrap_admin(engine)
            print(f'Attendance v2 schema ready ({engine.dialect.name}). Existing demo data retained.')
            print(f'Initial administrator: {result}.')
        elif args.command == 'bootstrap-admin':
            migrate(engine)
            from .bootstrap import bootstrap_admin
            from dotenv import dotenv_values
            settings = dotenv_values(args.env_file) if args.env_file else None
            print(f'Initial administrator: {bootstrap_admin(engine, settings)}.')
        else:
            from sqlalchemy import select
            with engine.connect() as conn:
                conn.execute(select(1))
            print(f'Database connection OK ({engine.dialect.name})')
    finally:
        engine.dispose()


if __name__ == '__main__':
    main()
