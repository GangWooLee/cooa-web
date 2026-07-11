# demo:bulk 생성 본체 — lib/tasks/demo.rake가 `load`로 적재해 Demo::Bulk.generate!(rng:) 호출.
# db/demo/는 autoload 경로가 아니라 재적재해도 안전(상수 재정의는 모듈로 격리). 모든 무작위는 호출측이
# 넘긴 고정 RNG 인스턴스(Random.new(20260710))로만 — 연속 2회 실행이 동일 카운트가 되도록 결정적.
# owner 연결(BYPASSRLS) 전제 + Current.tenant_id 스탬프(rake가 세팅). 순수 AR create!만 — audit 행 0.
require_relative "pools"

module Demo
  module Bulk
    ROOT_COUNT = 12                       # 신규 작업실(루트) 수 → 기존 3 + 12 = 15
    COMPONENT_COUNTS = [ 3, 4, 5, 6 ].freeze  # 아이템당 구성요소 수(순환, 평균 4.5)
    VERSION_COUNTS   = [ 2, 3, 4, 3 ].freeze  # 구성요소당 버전 수(순환, 평균 3)
    DEEP_ROOTS = [ 0, 4, 8 ].freeze       # 깊이-4 트리를 만드는 루트 인덱스(그 외는 깊이-3)

    module_function

    def generate!(rng:)
      Generator.new(rng).run!
    end

    # 상태를 담아 트리→콘텐츠→멤버→초대 순으로 결정적 생성. Pools 상수를 순환/샘플해 이름을 채운다.
    class Generator
      include Demo::Pools

      def initialize(rng)
        @rng = rng
        @item_seq = 0    # 전역 아이템 순번(제품 code·COMPONENT_COUNTS 인덱스)
        @comp_seq = 0    # 전역 구성요소 순번(VERSION_COUNTS·스크리닝/리뷰 플래그 인덱스)
        @review_seq = 0  # 전역 리뷰 순번(pending/reviewed·리뷰어 배정 분기)
        @stale_seq = 0   # stale 연출 카운터(상한 STALE_TARGET)
        @workspace_ids = []   # 벌크 작업실 id(스코프 grant·초대 대상)
        @scope_product_ids = [] # 스코프 grant·초대용 벌크 아이템 id 표본
        @hero_version_ids = []  # 작업실당 1개 히어로 버전 id(아트워크 첨부 대상)
      end

      STALE_TARGET = 20 # 콘텐츠 stale(ReviewedTuple.stale? true) 연출 목표 건수

      def run!
        @kim_account = Account.find_by(email: "kim@cooa.dev") ||
                       Account.joins(:user).find_by(users: { email: "kim@cooa.dev" })
        raise "seed owner account(kim) 없음 — load_seed 선행 필요" if @kim_account.nil?

        build_members!            # 벌크 멤버 20(User+Account+tenant-wide grant) — 저작권 풀 먼저 채움
        @users = User.order(:id).to_a  # 시드 8 + 벌크 20 = 28(저작권·submitter·reviewer 풀)

        ROOT_COUNT.times { |i| build_root!(i) }

        attach_hero_artwork!      # 작업실당 1개 히어로 버전에 실제 아트워크 첨부
        add_scoped_grants!        # 일부 멤버에 workspace/product 스코프 grant
        build_invitations!        # 대기 초대 7건
        nil
      end

      # ── 멤버 ──────────────────────────────────────────────────────────────
      # 벌크 계정 uuid는 최상위 대역(ffffffff-…)으로 고정 — dev 픽커/smoke의 Account.active.order(:id) 첫
      # 계정이 항상 시드 계정으로 남아야 한다(벌크 계정이 첫 자리에 오면 약한 역할로 쓰기 왕복이 깨질 수 있음).
      TENANT_ROLE_CYCLE = %w[
        contributor contributor viewer assignee ra_reviewer approver viewer contributor
        assignee contributor viewer ra_reviewer contributor approver viewer contributor
        assignee contributor viewer contributor
      ].freeze

      def build_members!
        tid = Current.tenant_id
        20.times do |i|
          name = KOREAN_NAMES[i % KOREAN_NAMES.length]
          user = User.create!(name: name, role: USER_JOB_ROLES[i % USER_JOB_ROLES.length],
                              avatar_color: AVATAR_COLORS[i % AVATAR_COLORS.length],
                              email: "member#{i + 1}@team.demo")
          acc = Account.create!(id: format("ffffffff-1111-4111-8111-%012d", i + 1),
                               tenant_id: tid, user: user, email: user.email, status: "active")
          RoleAssignment.create!(account: acc, tenant_id: tid,
                                 role_key: TENANT_ROLE_CYCLE[i], scope_type: "tenant")
        end
        puts "  · 멤버 20명(벌크 계정 ffffffff-… 대역) 생성"
      end

      # ── 루트 트리 ─────────────────────────────────────────────────────────
      def build_root!(index)
        ApplicationRecord.transaction do
          root = new_folder(ROOT_LINES[index], parent: nil, position: index)
          @workspace_ids << root.workspace_id
          @hero_pending = true # 이 루트에서 처음 만나는 current 버전을 히어로로 표시
          deep = DEEP_ROOTS.include?(index)

          3.times do |m|
            market = MARKETS_WEIGHTED.sample(random: @rng)
            mid = new_folder("#{ApplicationRecord.country_label(market)} #{MID_SUFFIXES[m % MID_SUFFIXES.length]}",
                             parent: root, position: m)
            build_mid!(mid, market, deep: (deep && m.zero?))
          end
        end
        puts "  · 작업실 #{index + 1}/#{ROOT_COUNT} 완료 (products=#{Product.count} components=#{Component.count} versions=#{ComponentVersion.count})"
      end

      # mid 폴더 아래: 직속 아이템 + 서브폴더(깊이 확보). deep이면 서브의 서브까지(깊이 4).
      def build_mid!(mid, market, deep:)
        direct = deep ? 3 : (mid.position.zero? ? 3 : 4 + mid.position % 2) # 3~5
        direct.times { |k| build_item!(parent: mid, market: market, position: k) }

        return unless mid.position.zero? # 서브폴더는 첫 mid에만(폴더 수 억제)

        sub = new_folder("#{SUBFOLDER_LABELS[0]}", parent: mid, position: direct)
        if deep
          2.times { |k| build_item!(parent: sub, market: market, position: k) }
          sub2 = new_folder("#{SUBFOLDER_LABELS[1]}", parent: sub, position: 2)
          2.times { |k| build_item!(parent: sub2, market: market, position: k) } # 깊이 4
        else
          3.times { |k| build_item!(parent: sub, market: market, position: k) }
        end
      end

      # 리프(SKU) + 구성요소 트리.
      def build_item!(parent:, market:, position:)
        seq = (@item_seq += 1)
        base = PRODUCT_ITEMS[(seq - 1) % PRODUCT_ITEMS.length]
        variant = VARIANT_SUFFIXES.sample(random: @rng)
        owner = @users.sample(random: @rng)
        item = Product.create!(
          name: "#{base} #{variant}", parent: parent, kind: "item",
          code: format("HB-%s-%04d", market, seq), country: market,
          channel: CHANNELS.sample(random: @rng), owner: owner, product_type: "기획",
          position: position, deadline: (Time.current + @rng.rand(-30..90).days).to_date
        )
        @scope_product_ids << item.id if @scope_product_ids.length < ROOT_COUNT && position.zero?

        comp_count = COMPONENT_COUNTS[(seq - 1) % COMPONENT_COUNTS.length]
        comp_count.times { |c| build_component!(item, index: c) }
      end

      def build_component!(product, index:)
        cseq = (@comp_seq += 1)
        types = Component::TYPES.keys
        type = types[index % types.length]
        comp = product.components.create!(component_type: type, name: Component::TYPES[type], position: index)

        n = VERSION_COUNTS[(cseq - 1) % VERSION_COUNTS.length]
        stamps = version_timestamps(n)
        versions = (1..n).map do |v|
          comp.component_versions.create!(
            version_number: v, label: "[#{product.code}]",
            image_name: IMAGE_NAMES[(v - 1) % IMAGE_NAMES.length],
            change_reason: (v > 1 ? CHANGE_REASONS.sample(random: @rng) : "1차 시안"),
            created_by: @users.sample(random: @rng), current: (v == n),
            created_at: stamps[v - 1], updated_at: stamps[v - 1]
          )
        end
        current = versions.last
        if @hero_pending
          @hero_version_ids << current.id
          @hero_pending = false
        end

        screened = (cseq % 3) != 0        # ~66.7%
        reviewed = (cseq % 5) < 2         # 40%
        return unless screened || reviewed # active 버전만 콘텐츠/피드백을 붙임

        seed_content!(current)
        add_annotations!(current)
        add_screening!(current, product.country) if screened
        add_review!(current) if reviewed
      end

      # ── 콘텐츠(label_texts/ingredients) ──────────────────────────────────
      def seed_content!(version)
        (2 + @rng.rand(3)).times do # 2~4
          kind = [ :label, :ad, :ingredient_list ].sample(random: @rng)
          content = case kind
          when :label then LABEL_CONTENTS.sample(random: @rng)
          when :ad then AD_CONTENTS.sample(random: @rng)
          else INGREDIENT_LIST_PREFIX + INGREDIENTS.sample(4, random: @rng).map(&:first).join(", ")
          end
          version.label_texts.create!(text_type: kind.to_s, content: content,
                                      language: (version.component.product.country == "US" ? "en" : "ko"),
                                      country: version.component.product.country)
        end
        INGREDIENTS.sample(2 + @rng.rand(3), random: @rng).each_with_index do |(nm, canon, cas), i| # 2~4
          version.ingredients.create!(inci_name: nm, inci_canonical: canon, cas: cas,
                                      declared_pct: (@rng.rand(10) < 3 ? (@rng.rand(1..500) / 100.0) : nil),
                                      position: i)
        end
      end

      # ── 어노테이션 + 코멘트 스레드 ───────────────────────────────────────
      def add_annotations!(version)
        (1 + @rng.rand(2)).times do |i| # 1~2
          author = @users.sample(random: @rng)
          status = %w[open open resolved dismissed].sample(random: @rng)
          created = after(version.created_at, max_days: 25)
          ann = version.annotations.create!(
            seq: i + 1, box_x: rand_box, box_y: rand_box, box_w: 4 + @rng.rand(8), box_h: 2 + @rng.rand(5),
            category: ANNOTATION_CATEGORIES.sample(random: @rng), created_by: author,
            position: i, status: status,
            resolved_by: (status == "resolved" ? @users.sample(random: @rng) : nil),
            resolved_at: (status == "resolved" ? after(created, max_days: 10) : nil),
            created_at: created, updated_at: created
          )
          root = ann.comments.create!(author: author, body: ANNOTATION_BODIES.sample(random: @rng),
                                      created_at: created, updated_at: created)
          next unless @rng.rand(2).zero? # ~50% 스레드에 답글

          reply_at = after(created, max_days: 8)
          ann.comments.create!(author: @users.sample(random: @rng), parent: root,
                               body: ANNOTATION_REPLIES.sample(random: @rng),
                               created_at: reply_at, updated_at: reply_at)
        end
      end

      # ── 스크리닝 런 + findings(서비스 호출 없이 직접 create!) ─────────────
      def add_screening!(version, country)
        decision = weighted_decision
        created = after(version.created_at, max_days: 20)
        run = version.screening_runs.create!(
          country: country, decision: decision, status: "completed",
          summary: SCREENING_SUMMARIES[decision], requested_by: @users.sample(random: @rng),
          created_at: created, updated_at: created
        )
        finding_specs(decision).each_with_index do |fdecision, i|
          run.screening_findings.create!(
            element_type: FINDING_ELEMENT_TYPES.sample(random: @rng), decision: fdecision,
            subject: FINDING_SUBJECTS.sample(random: @rng), issue_description: FINDING_ISSUES.sample(random: @rng),
            citation: FINDING_CITATIONS.sample(random: @rng), severity: severity_for(fdecision),
            confidence: 55 + @rng.rand(40), position: i
          )
        end
      end

      # ── 리뷰 요청(정본 ApprovalRequest.submit_for!) ──────────────────────
      def add_review!(version)
        rseq = (@review_seq += 1)
        submitter = @users.sample(random: @rng)
        reviewer = (@users - [ submitter ]).sample(random: @rng)
        reviewed = (rseq % 5) < 2 # 40% reviewed, 60% pending

        assign = reviewed || rseq.even? # reviewed는 항상 배정, pending은 절반만(무배정 = 인박스 pull 풀)
        req = ApprovalRequest.submit_for!(version, submitter_id: submitter.id,
                                          reviewer_ids: (assign ? [ reviewer.id ] : []),
                                          due_at: due_at_for(rseq, reviewed))
        requested_at = after(version.created_at, max_days: 20)
        req.update_columns(requested_at: requested_at, created_at: requested_at, updated_at: requested_at)

        if reviewed
          req.confirm_review!(reviewer_id: reviewer.id) # SoD: 리뷰어 ≠ 제출자
          acted = after(requested_at, max_days: 12)
          req.approval_steps.first&.update_columns(acted_at: acted, created_at: acted, updated_at: acted)
        elsif @stale_seq < STALE_TARGET
          @stale_seq += 1                                # 콘텐츠 stale 연출: submit 후 label_text 변경
          lt = version.label_texts.first
          lt&.update!(content: "#{lt.content} (개정 검토중)")
        end
      end

      # ── 히어로 아트워크 첨부(작업실당 1건) ────────────────────────────────
      # 공유 blob 순환 참조: ActiveStorage는 checksum dedup을 하지 않으므로 파일별 blob을 1회만 만들고
      # 여러 버전이 공유한다. 제약: 공유 blob은 한 attachment를 purge하면 blob이 함께 삭제돼 나머지
      # 참조가 깨진다(데모 전용이라 무해 — 프로덕션 업로드 경로는 버전별 개별 blob).
      def attach_hero_artwork!
        files = artwork_files
        return puts "  · 아트워크 소스 없음 — 히어로 첨부 건너뜀" if files.empty?

        blobs = files.map do |path|
          ActiveStorage::Blob.create_and_upload!(io: File.open(path), filename: File.basename(path),
                                                 content_type: content_type_for(path))
        end
        @hero_version_ids.each_with_index do |vid, i|
          ComponentVersion.find(vid).artwork.attach(blobs[i % blobs.length])
        end
        puts "  · 히어로 아트워크 #{@hero_version_ids.size}건 첨부(공유 blob #{blobs.size})"
      end

      # db/demo/assets/ 에 png/jpg/webp/pdf 가 있으면 그것을 순환, 없으면 fixture PDF 단일. SVG는
      # ARTWORK_TYPES(png/jpeg/webp/pdf) 화이트리스트에 없어 제외.
      def artwork_files
        dir = Rails.root.join("db/demo/assets")
        if dir.directory?
          globbed = Dir.glob(dir.join("*.{png,jpg,jpeg,webp,pdf}")).sort
          return globbed if globbed.any?
        end
        fixture = Rails.root.join("test/fixtures/files/sample_artwork.pdf")
        fixture.exist? ? [ fixture.to_s ] : []
      end

      def content_type_for(path)
        case File.extname(path).downcase
        when ".png" then "image/png"
        when ".jpg", ".jpeg" then "image/jpeg"
        when ".webp" then "image/webp"
        else "application/pdf"
        end
      end

      # ── 스코프 grant(트리 생성 후 — 대상 존재 보장) ──────────────────────
      def add_scoped_grants!
        accounts = Account.where(email: (1..20).map { |i| "member#{i}@team.demo" }).order(:id).to_a
        tid = Current.tenant_id
        accounts.sample(6, random: @rng).each_with_index do |acc, i|
          role = Authz::RoleLabels::WORKSPACE_ROLE_KEYS.sample(random: @rng)
          if i.even? && @workspace_ids.any?
            RoleAssignment.create!(account: acc, tenant_id: tid, role_key: role,
                                   scope_type: "workspace", scope_workspace_id: @workspace_ids.sample(random: @rng))
          elsif @scope_product_ids.any?
            RoleAssignment.create!(account: acc, tenant_id: tid, role_key: role,
                                   scope_type: "product", scope_product_id: @scope_product_ids.sample(random: @rng))
          end
        end
        puts "  · 스코프 grant 부여(workspace/product)"
      end

      # ── 대기 초대 7건 ────────────────────────────────────────────────────
      def build_invitations!
        specs = [
          { role_key: "contributor", scope_type: "tenant" },
          { role_key: "viewer", scope_type: "tenant" },
          { role_key: "ra_reviewer", scope_type: "tenant" },
          { role_key: "brand_admin", scope_type: "workspace" },
          { role_key: "contributor", scope_type: "workspace" },
          { role_key: "external_collaborator", scope_type: "product" },
          { role_key: "viewer", scope_type: "product" }
        ]
        specs.each_with_index do |spec, i|
          kwargs = { email: "invitee#{i + 1}@invite.demo", role_key: spec[:role_key],
                     invited_by_account_id: @kim_account.id, scope_type: spec[:scope_type] }
          kwargs[:scope_workspace_id] = @workspace_ids.sample(random: @rng) if spec[:scope_type] == "workspace"
          kwargs[:scope_product_id] = @scope_product_ids.sample(random: @rng) if spec[:scope_type] == "product"
          invitation, = Invitation.generate!(**kwargs)
          invitation.update_columns(expires_at: 1.day.from_now) if i < 2 # 만료 임박 2건
        end
        puts "  · 대기 초대 7건 생성"
      end

      # ── 잡동사니 헬퍼 ────────────────────────────────────────────────────
      def new_folder(name, parent:, position:)
        Product.create!(name: name, parent: parent, kind: "folder", product_type: "기획", position: position)
      end

      def rand_box = (5 + @rng.rand(80)).to_f

      def version_timestamps(n)
        t = Time.current - @rng.rand(120..180).days
        Array.new(n) do
          stamp = t
          t += @rng.rand(2..15).days + @rng.rand(0..80_000).seconds
          stamp
        end
      end

      def after(ts, max_days:)
        t = ts + @rng.rand(0..max_days).days + @rng.rand(0..80_000).seconds
        t > Time.current ? Time.current - @rng.rand(0..2).days : t
      end

      # ok 45 / warning 25 / violation 20 / unable 10
      def weighted_decision
        r = @rng.rand(100)
        return "ok" if r < 45
        return "warning" if r < 70
        return "violation" if r < 90

        "unable"
      end

      # findings 0-4, 런 판정과 정합(ok=0건, 나머지는 런 판정 중심).
      def finding_specs(decision)
        case decision
        when "ok" then []
        when "warning" then Array.new(1 + @rng.rand(3)) { "warning" }
        when "violation" then Array.new(1 + @rng.rand(4)) { @rng.rand(3).zero? ? "warning" : "violation" }
        else Array.new(1 + @rng.rand(2)) { "unable" }
        end
      end

      def severity_for(decision)
        { "violation" => "Critical", "warning" => "Major", "unable" => "Major", "ok" => "Minor" }[decision]
      end

      # pending due_at: 임박/초과/무기한 혼합. reviewed는 과거 마감(이미 처리됨).
      def due_at_for(rseq, reviewed)
        return Time.current - @rng.rand(1..20).days if reviewed

        case rseq % 3
        when 0 then Time.current + @rng.rand(1..7).days   # 임박
        when 1 then Time.current - @rng.rand(1..15).days  # 초과(overdue)
        else nil                                          # 무기한
        end
      end
    end
  end
end
