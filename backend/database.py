import os
import time

from sqlalchemy import create_engine, event
from sqlalchemy.orm import declarative_base, sessionmaker

import metrics

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://gamba:gamba@localhost:5432/gamba")

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


def _sql_operation(statement):
    operation = statement.lstrip().split(None, 1)[0].upper() if statement else "OTHER"
    return operation if operation in {"SELECT", "INSERT", "UPDATE", "DELETE"} else "OTHER"


@event.listens_for(engine, "before_cursor_execute")
def before_cursor_execute(conn, cursor, statement, parameters, context, executemany):
    context._gamba_query_started = time.perf_counter()
    context._gamba_query_operation = _sql_operation(statement)


def _record_query(context, outcome):
    started = getattr(context, "_gamba_query_started", None)
    if started is None:
        return

    operation = getattr(context, "_gamba_query_operation", "OTHER")
    metrics.db_query_duration.labels(operation).observe(time.perf_counter() - started)
    metrics.db_queries.labels(operation, outcome).inc()
    context._gamba_query_started = None


@event.listens_for(engine, "after_cursor_execute")
def after_cursor_execute(conn, cursor, statement, parameters, context, executemany):
    _record_query(context, "success")


@event.listens_for(engine, "handle_error")
def handle_query_error(exception_context):
    if exception_context.execution_context is not None:
        _record_query(exception_context.execution_context, "error")


@event.listens_for(engine.pool, "checkout")
def connection_checked_out(dbapi_connection, connection_record, connection_proxy):
    metrics.db_pool_checked_out.inc()


@event.listens_for(engine.pool, "checkin")
def connection_checked_in(dbapi_connection, connection_record):
    metrics.db_pool_checked_out.dec()
