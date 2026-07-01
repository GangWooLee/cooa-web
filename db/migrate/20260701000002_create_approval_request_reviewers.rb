require Rails.root.join("lib/tenant_rls").to_s

# 리뷰어 지정(리프레임 후속): 리뷰 요청 시 지정된 리뷰어(1..N). "요청받음 = 그 리뷰 한정 검토 권한"
# (GitHub-PR 모델) — 담당자의 자유텍스트 role을 권한으로 매핑하지 않고, per-record ACL로 처리해
# RoleAssignment 제품-스코프(uuid↔bigint) 블로커를 우회한다. approval_request당 여러 리뷰어라 조인
# 테이블(approval_requests/approval_steps는 UNIQUE-per-parent). reviewer_id는 전역 users(bigint) —
# submitter_id/approver_id와 동일 공간(SoD 비교용). owner 역할로 실행(COOA_DB_USER).
class CreateApprovalRequestReviewers < ActiveRecord::Migration[8.1]
  include TenantRls

  def up
    create_table :approval_request_reviewers do |t|
      t.uuid   :tenant_id, null: false
      t.bigint :approval_request_id, null: false
      t.bigint :reviewer_id, null: false # User(bigint) — 요청받은 리뷰어
      t.timestamps
    end
    add_index :approval_request_reviewers, [:tenant_id, :approval_request_id, :reviewer_id],
              unique: true, name: "arr_tenant_request_reviewer_key" # 요청당 리뷰어 중복 방지
    add_index :approval_request_reviewers, [:tenant_id, :reviewer_id], name: "arr_tenant_reviewer_idx" # 수신함 쿼리
    composite_fk!(:approval_request_reviewers, :approval_request_id, :approval_requests, name: "arr_request_tenant_fkey")
    add_foreign_key :approval_request_reviewers, :users, column: :reviewer_id
    enable_tenant_rls!("approval_request_reviewers")
  end

  def down
    drop_table :approval_request_reviewers
  end
end
