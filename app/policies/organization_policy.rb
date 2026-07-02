# 테넌트-레벨 행위(멤버 로스터·초대)의 authorize 대상. ApplicationPolicy가 PermissionMatrix의 모든
# verb 프레디킷(list_tenant_accounts?/manage_members? 등)을 자동 정의하고 AssignmentResolver의
# 테넌트-와이드 역할 해석이 record-독립이라 빈 서브클래스로 충분(신규 verb·MATRIX 변경 없음).
class OrganizationPolicy < ApplicationPolicy
end
