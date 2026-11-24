"""Database setup for local development, CI and hosted PostgreSQL."""
import argparse
from .database import make_engine, migrate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['migrate', 'check', 'bootstrap-admin', 'create-sensor', 'list-sensors', 'revoke-sensor'])
    parser.add_argument('--env-file', help='Read administrator settings from this file; database settings still come from the normal local environment')
    parser.add_argument('--name', help='create-sensor: label, e.g. "ESP32 Room 101"')
    parser.add_argument('--room', help='create-sensor: must equal the class room field exactly')
    parser.add_argument('--id', help='revoke-sensor: sensor id')
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
        elif args.command in ('create-sensor', 'list-sensors', 'revoke-sensor'):
            import secrets, time
            from sqlalchemy import select, insert, update
            from .database import csi_sensors
            from .service import digest, uid
            migrate(engine)
            with engine.begin() as conn:
                if args.command == 'create-sensor':
                    if not args.name or not args.room:
                        parser.error('create-sensor needs --name and --room')
                    token, sensor_id = secrets.token_urlsafe(32), uid()
                    conn.execute(insert(csi_sensors).values(id=sensor_id, name=args.name, room=args.room,
                        token_hash=digest(token), active=1, created_at=time.time()))
                    print(f'Sensor {sensor_id} created for room "{args.room}".')
                    print(f'CSI_SERVICE_TOKEN={token}')
                    print('Store this token in csi/.env on the processing laptop. It is not shown again.')
                elif args.command == 'revoke-sensor':
                    changed = conn.execute(update(csi_sensors).where(csi_sensors.c.id == args.id).values(active=0)).rowcount
                    print('Revoked.' if changed else 'No sensor with that id.')
                else:
                    for row in conn.execute(select(csi_sensors)).mappings():
                        print(row['id'], row['room'], row['name'], 'active' if row['active'] else 'revoked', row['last_seen_at'])
        else:
            from sqlalchemy import select
            with engine.connect() as conn:
                conn.execute(select(1))
            print(f'Database connection OK ({engine.dialect.name})')
    finally:
        engine.dispose()


if __name__ == '__main__':
    main()
