# Screening-level verbs (run_screening / view_screening_findings / submit_for_approval) resolve via
# ApplicationPolicy's generic verb predicates. Identity-based SoD moved to the approval aggregate
# (ApprovalRequestPolicy, Phase 3b/3c) — there is no screening-level approve anymore.
class ScreeningRunPolicy < ApplicationPolicy
end
