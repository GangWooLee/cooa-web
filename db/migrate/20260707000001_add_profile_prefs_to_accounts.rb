class AddProfilePrefsToAccounts < ActiveRecord::Migration[8.1]
  # 계정 설정(셀프 프로필)용 표시 선호 — tenant-scoped accounts에 둔다(전역 users는 런타임 UPDATE 잠금:
  # lib/tasks/cooa.rake PERSON_TABLES = SELECT,INSERT only, grant_audit이 over-grant 차단). accounts는 이미
  # RLS+full DML grant 완비 → grant 재분류 불요. 둘 다 nullable(폴백: user.avatar_color / user.role).
  def change
    add_column :accounts, :avatar_color, :string
    add_column :accounts, :job_title, :string
  end
end
