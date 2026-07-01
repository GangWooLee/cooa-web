# 리뷰 리프레임 후 정리(죽은코드·오독 지뢰 제거):
#  - screening_runs.approved_by_id / approved_at: 은퇴한 screening-레벨 승인 경로의 고아 컬럼(DROP COLUMN이
#    FK fk_rails_fe66c052dc + index를 연쇄 제거). status enum의 'approved' 값 제거는 모델에서.
#  - approval_requests.market: M-4(시장관할) 폐지 후 vestigial.
#  - approval_requests.reviewed_at → requested_at: 실은 요청 시각(pending 때 찍힘)인데 "확인 시각"으로 오독됨.
#    실제 확인 시각은 approval_steps.acted_at. owner 실행(COOA_DB_USER) + 이후 rls:audit.
class CleanupReviewSchema < ActiveRecord::Migration[8.1]
  def up
    remove_column :screening_runs, :approved_by_id
    remove_column :screening_runs, :approved_at
    remove_column :approval_requests, :market
    rename_column :approval_requests, :reviewed_at, :requested_at
  end

  def down
    add_column :screening_runs, :approved_at, :datetime
    add_column :screening_runs, :approved_by_id, :integer
    add_index :screening_runs, :approved_by_id
    add_foreign_key :screening_runs, :users, column: :approved_by_id
    add_column :approval_requests, :market, :string, null: false, default: ""
    change_column_default :approval_requests, :market, nil
    rename_column :approval_requests, :requested_at, :reviewed_at
  end
end
