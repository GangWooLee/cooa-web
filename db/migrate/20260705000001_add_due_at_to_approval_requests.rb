# Stage 5 (P2): 리뷰 요청에 선택적 마감일(due_at)을 붙인다. nullable — 기존 전 행은 NULL(마감일 없음)으로
# 유효하고, 기본값 없는 nullable 컬럼 추가는 테이블 rewrite/락 없음 → strong_migrations 안전(safety_assured
# 불요). overdue 판정(due_at < now)·인박스 표시·개인 액션어블 overdue 배지가 이 컬럼 위에 선다.
#
# 타입 = timestamptz(의도적): 이 테이블의 기존 시각 컬럼(requested_at/created_at)은 `without time zone`이지만
# due_at은 "마감 순간"이라 TZ 모호성 없는 절대 인스턴트로 저장한다(overdue 경계 비교의 안전). requested_at
# (정렬 축)은 불변 — due_at은 표시/강조 전용이고 정렬을 재편하지 않는다.
class AddDueAtToApprovalRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :approval_requests, :due_at, :timestamptz
  end
end
