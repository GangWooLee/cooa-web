# "실제 조직이 6개월 사용한 규모"의 데모 목업 데이터 — dev DB 전용(과밀 대시보드·인박스 300+·멤버 28
# 같은 대량 상태에서만 드러나는 UX·성능 축 검증용). 스키마/신규 테이블 없이 기존 도메인만 대량 생성한다.
#
# 멱등성 = "리셋 후 재생성": demo:bulk 은 매번 시드로 기준선을 되돌린 뒤(load_seed 의 무조건 delete_all)
# 고정 RNG 로 결정적으로 채운다 → 연속 2회 실행이 동일 카운트·유니크 충돌 0. demo:bulk:clear 는 리셋만.
#
# 반드시 OWNER 연결로: COOA_DB_USER=$USER bin/rails demo:bulk  (cooa_app 은 RLS fail-closed + grant 제약).
namespace :demo do
  # 헬퍼는 전역 오염을 피해 모듈로 감싼다(top-level def 회피).
  module DemoTasks
    module_function

    def guard!
      abort "[demo] production 환경에서는 실행할 수 없습니다." if Rails.env.production?
      abort "[demo] test DB 오염 금지 — test 환경에서는 실행할 수 없습니다." if Rails.env.test?

      role = ActiveRecord::Base.connection.select_value("SELECT current_user")
      return unless role == "cooa_app"

      abort <<~MSG
        [demo] owner 연결이 필요합니다 (현재 DB 롤 = cooa_app).
               cooa_app 은 RLS fail-closed + grant 제약으로 대량 생성이 막힙니다.
               다시 실행하세요:  COOA_DB_USER=$USER bin/rails demo:bulk
      MSG
    end

    # 시드 기준선 복귀. 초대는 시드 clear 목록에 없고(accounts/org FK 를 물어 load_seed 의 delete_all 을
    # 깰 수 있어) load_seed 보다 먼저 비운다.
    def reset_to_seed!
      Invitation.where(tenant_id: TenantConfig::DEMO_TENANT_ID).delete_all
      Rails.application.load_seed
      purge_orphan_artwork!
    end

    # 아트워크 첨부 멱등성: 시드의 ComponentVersion.delete_all 은 콜백을 안 태워 active_storage 첨부/blob 을
    # 고아로 남긴다(dependent purge 미발동). 정리하지 않으면 재실행마다 첨부 카운트가 누적된다. 첨부 join 은
    # delete_all(공유 blob double-purge 회피), 그 결과 미첨부가 된 blob 만 purge(파일까지 제거).
    def purge_orphan_artwork!
      ActiveStorage::Attachment.where(record_type: "ComponentVersion").delete_all
      ActiveStorage::Blob.unattached.find_each(&:purge)
    end

    REPORT = [
      [ "작업실 (workspaces)",                :workspaces ],
      [ "제품 (products)",                    :products ],
      [ "  · 폴더",                           :folders ],
      [ "  · 아이템",                         :items ],
      [ "구성요소 (components)",              :components ],
      [ "버전 (component_versions)",          :versions ],
      [ "라벨문구 (label_texts)",             :label_texts ],
      [ "성분 (ingredients)",                 :ingredients ],
      [ "어노테이션 (annotations)",           :annotations ],
      [ "댓글 (annotation_comments)",         :comments ],
      [ "스크리닝 런 (screening_runs)",       :runs ],
      [ "스크리닝 finding",                   :findings ],
      [ "리뷰 요청 (approval_requests)",      :reviews ],
      [ "  · pending",                        :reviews_pending ],
      [ "  · reviewed",                       :reviews_reviewed ],
      [ "리뷰 확인 스텝 (approval_steps)",    :steps ],
      [ "지정 리뷰어 (approval_request_reviewers)", :reviewers ],
      [ "멤버 계정 (accounts)",               :accounts ],
      [ "역할 부여 (role_assignments)",       :grants ],
      [ "대기 초대 (invitations · pending)",  :invitations ],
      [ "아트워크 첨부 (artwork attachments)", :artwork ]
    ].freeze

    def counts
      {
        workspaces: Workspace.count, products: Product.count,
        folders: Product.where(kind: "folder").count, items: Product.where(kind: "item").count,
        components: Component.count, versions: ComponentVersion.count,
        label_texts: LabelText.count, ingredients: Ingredient.count,
        annotations: Annotation.count, comments: AnnotationComment.count,
        runs: ScreeningRun.count, findings: ScreeningFinding.count,
        reviews: ApprovalRequest.count,
        reviews_pending: ApprovalRequest.where(status: "pending").count,
        reviews_reviewed: ApprovalRequest.where(status: "reviewed").count,
        steps: ApprovalStep.count, reviewers: ApprovalRequestReviewer.count,
        accounts: Account.count, grants: RoleAssignment.count,
        invitations: Invitation.pending.count,
        artwork: ActiveStorage::Attachment.where(name: "artwork").count
      }
    end

    def print_report(title, elapsed)
      c = counts
      puts
      puts "── #{title} ─────────────────────────────────"
      REPORT.each { |label, key| puts format("  %-38s %6d", label, c[key]) }
      puts "  #{'-' * 45}"
      puts format("  소요시간 %.1fs", elapsed) if elapsed
      puts
      puts "  ⚠ dev DB 가 시드 기준선으로 리셋된 뒤 생성되었습니다 — 리셋 전 수동 데이터는 소실됩니다."
    end
  end

  desc "6개월 사용 규모의 대량 데모 데이터 생성 (dev 전용 · 시드 리셋 후 재생성 · 멱등)"
  task bulk: :environment do
    DemoTasks.guard!
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    DemoTasks.reset_to_seed!
    Current.tenant_id = TenantConfig::DEMO_TENANT_ID # load_seed 이후 명시 재스탬프(TenantScoped 자동 적재용)
    load Rails.root.join("db/demo/bulk.rb")
    Demo::Bulk.generate!(rng: Random.new(20260710))  # 고정 시드 RNG = 결정적·멱등

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    DemoTasks.print_report("demo:bulk 완료 — 모델별 카운트", elapsed)
  end

  namespace :bulk do
    desc "대량 데모 데이터 제거 — 시드 기준선으로만 복귀 (dev 전용)"
    task clear: :environment do
      DemoTasks.guard!
      DemoTasks.reset_to_seed!
      DemoTasks.print_report("demo:bulk:clear 완료 — 시드 기준선 카운트", nil)
    end
  end
end
