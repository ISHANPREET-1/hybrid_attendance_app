"""Vercel Python function: shares the exact local API implementation."""
from backend.database import make_engine
from backend.service import Service
from backend.server import Handler

_engine = make_engine()


class handler(Handler):
    service = Service(_engine)
