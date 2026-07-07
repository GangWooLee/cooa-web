# Deep readiness probe (/ready) — distinct from /up (rails/health), which is the shallow "did the process
# boot" liveness probe for the load balancer. /ready checks the app can actually SERVE traffic:
#   db    — a real round-trip (SELECT 1). Failure ⇒ 503 so the LB pulls this node out of rotation.
#   queue — SolidQueue worker heartbeat within QUEUE_WINDOW. Worker ABSENCE is NOT a failure (dev / single
#           node runs no worker; the queue tables may not even be provisioned) — reported for observability
#           only, never a 503.
class HealthController < ApplicationController
  QUEUE_WINDOW = 5.minutes

  # Pre-auth probe: skip account resolution (reuse SessionsController's macro) and skip Pundit honestly
  # (readiness is not a policied resource — skip_authorization, not a bypass of verify_authorized).
  allow_unauthenticated_access only: :ready

  def ready
    skip_authorization

    db_up = database_up?
    render json: { status: db_up ? "ok" : "error", db: db_up ? "up" : "down", queue: queue_liveness },
           status: db_up ? :ok : :service_unavailable
  end

  private

  # Any successful round-trip means the primary DB is reachable; a connection/query error means it is not.
  def database_up?
    ActiveRecord::Base.connection.select_value("SELECT 1")
    true
  rescue StandardError
    false
  end

  # active = a supervisor/worker heartbeat within QUEUE_WINDOW; idle = none. "unavailable" = the queue
  # backend is not reachable/provisioned (e.g. dev/test primary DB has no solid_queue tables) — still NOT a
  # readiness failure, only surfaced so an operator can tell "no workers" from "no queue infra".
  #
  # SAVEPOINT (requires_new): in prod SolidQueue rides a SEPARATE queue DB, but in dev/test it shares the
  # primary connection — so a missing-table error would abort the request's RLS transaction (opened by
  # Authentication#scope_to_tenant) and cascade PG::InFailedSqlTransaction. Wrapping the probe in a savepoint
  # (the codebase idiom) rolls back only the subtransaction on failure, leaving the outer tx healthy.
  def queue_liveness
    SolidQueue::Process.transaction(requires_new: true) do
      SolidQueue::Process.where("last_heartbeat_at > ?", QUEUE_WINDOW.ago).exists? ? "active" : "idle"
    end
  rescue StandardError
    "unavailable"
  end
end
