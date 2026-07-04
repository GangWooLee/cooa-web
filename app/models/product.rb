class Product < ApplicationRecord
  include TenantScoped
  # 자기참조 트리(노션형) — 루트=상위 개념, 자식=변형(국가·용량 등)
  # inverse_of: 트리를 루트→children로 렌더하면 각 child의 parent가 메모리에서 역참조된다 →
  # self_and_ancestors의 조상 walk가 쿼리 0건(사이드바가 매 페이지 렌더하는 N+1 제거).
  belongs_to :parent, class_name: "Product", optional: true, inverse_of: :children
  belongs_to :owner, class_name: "User", optional: true
  has_many :children, -> { order(:position, :id) }, class_name: "Product",
           foreign_key: :parent_id, inverse_of: :parent, dependent: :destroy
  has_many :components, -> { order(:position, :id) }, dependent: :destroy
  has_many :product_members, dependent: :destroy
  has_many :members, through: :product_members, source: :user
  has_many :product_properties, -> { order(:position, :id) }, dependent: :destroy

  scope :roots, -> { where(parent_id: nil).order(:position, :id) }
  scope :ordered, -> { order(:position, :id) }

  normalizes :name, with: ->(v) { v.to_s.strip }
  # 국가 자유입력 — 알려진 라벨/코드는 코드로 정규화(screening fact 매칭 보존), 그 외엔 원문 유지
  normalizes :country, with: ->(v) { ApplicationRecord.normalize_country(v) }
  # 입력 위생(S1): 과도한 이름 거부(보수적 상한). 메시지 한글 — 로케일 en·full_messages 기본 영문 회피(E2 정합).
  validates :name, presence: { message: "— 이름을 입력해 주세요" },
                   length: { maximum: 200, message: "— 200자를 넘을 수 없습니다" }
  validates :code, uniqueness: { allow_blank: true }
  validate :parent_not_self_or_descendant

  def country_label = ApplicationRecord.country_label(country)
  def member_for(role) = product_members.find_by(role: role)&.user

  # 폴더/항목은 kind로 구분(구조 무관) — 빈 폴더도 폴더로 동작
  def folder? = kind == "folder"
  def leaf?   = !folder?

  # 자기 + 모든 하위 id (이동 시 순환 방지용) — 인-루비 BFS
  def self_and_descendant_ids
    ids = [ id ]
    frontier = children.to_a
    until frontier.empty?
      n = frontier.shift
      ids << n.id
      frontier.concat(n.children.to_a)
    end
    ids.compact
  end

  # 이동/생성 시 상위 후보: 폴더만(트리 순서·depth 포함), 자기·하위 제외.
  # 반환: [[folder, depth], …] — tree_preorder 한 번으로 depth 확보(폼 N+1 회피).
  def self.parent_options_for(node)
    exclude = node&.persisted? ? node.self_and_descendant_ids : []
    tree_preorder.filter_map { |n, d| [ n, d ] if n.folder? && !exclude.include?(n.id) }
  end

  # 조상 경로(루트→…→self) — 브레드크럼/하이라이트용
  def self_and_ancestors
    chain = []
    node = self
    while node
      chain.unshift(node)
      node = node.parent
    end
    chain
  end

  def ancestors = self_and_ancestors[0...-1]
  def depth = ancestors.size

  # 브랜드 루트 = 트리 최상위 조상(자신이 루트면 자신). "팀"의 개념 단위(Stage 4 T1): 팀 멤버십 =
  # 이 루트 대상 product-scope role_assignment(teams 테이블 없음 — 기존 트리+스코프 기구 재사용).
  # self_and_ancestors[0]가 곧 루트(체인 head). 단일 노드 해석용 — 목록 렌더는 ReviewInboxPresenter의
  # in-memory 맵 walk가 별도(그쪽은 프리로드 맵으로 N+1 0건, 여기는 .parent walk라 리스트에 부적합).
  def brand_root = self_and_ancestors.first

  # 씨앗 제품 id들의 self+자손 id 집합 — (id, parent_id) 1회 로드 후 in-memory 확장(노드별 children
  # 재귀 없음 → N+1 0건). 테넌트 RLS 컨텍스트 내에서 동작. 스코프 서브트리 계산 단일 출처:
  # ProductPolicy::Scope(가시성)·members 스코프 로스터(T3)·브랜드 페이지 트리/멤버 요약(T4) 공용.
  def self.subtree_ids(seed_ids)
    seed_ids = Array(seed_ids).compact.map(&:to_i) # 파라미터(문자열 id)도 안전 — pluck는 정수라 타입 정합 필수
    return [] if seed_ids.empty?

    by_parent = Hash.new { |h, k| h[k] = [] }
    where(tenant_id: Current.tenant_id).pluck(:id, :parent_id).each { |id, pid| by_parent[pid] << id }
    visited = Set.new
    stack = seed_ids.dup
    until stack.empty?
      id = stack.pop
      next unless visited.add?(id)

      stack.concat(by_parent[id])
    end
    visited.to_a
  end

  # 트리 사전순(pre-order) 평탄화 → [[node, depth], …] (대시보드 트리 행·스코프 select·상위 후보 공용).
  # 평탄 컬렉션 1회를 parent_id로 그룹핑해 in-memory로 walk — :children 연관을 재귀 접근하지 않으므로
  # 하위 레벨(2+)에서 children를 재쿼리하던 잠복 N+1이 사라진다(Stage 3 리뷰어 실증 · members_controller의
  # 로컬 in-memory 우회를 이 메서드로 역-통합). 표시 루트 = 로드된 집합에서 부모가 집합 밖(또는 nil)인 노드
  # → 스코프 계정의 재루팅(부모 비가시)도 이 규칙이 그대로 처리(visible_roots 규칙 내포). nodes에 프리로드를
  # 실어 보내면 하위 노드도 같은 인스턴스라 프리로드가 유지되고, walk가 parent 타깃을 in-memory로 걸어
  # self_and_ancestors(node_path_label)의 조상 walk도 쿼리 0건이 된다(.children 경유 inverse_of :parent 대체).
  # 형제 정렬은 has_many :children(order :position, :id)와 동일 — 시드는 position 전부 지정이라 순서 무회귀.
  def self.tree_preorder(nodes = all)
    nodes = nodes.to_a
    in_set = nodes.map(&:id).to_set
    by_parent = nodes.group_by(&:parent_id)
    display_roots = nodes.select { |n| n.parent_id.nil? || in_set.exclude?(n.parent_id) }
    acc = []
    walk = lambda do |parent, siblings, level|
      siblings.sort_by { |n| [ n.position || 0, n.id ] }.each do |n|
        n.association(:parent).target = parent if parent # 조상 walk in-memory 보존(inverse_of :parent 대체)
        acc << [ n, level ]
        walk.call(n, by_parent[n.id] || [], level + 1)
      end
    end
    walk.call(nil, display_roots, 0)
    acc
  end

  private

  def parent_not_self_or_descendant
    return if parent_id.blank?
    if persisted? && self_and_descendant_ids.include?(parent_id)
      errors.add(:parent_id, "자기 자신이나 하위 폴더로 옮길 수 없습니다")
    elsif parent && !parent.folder?
      errors.add(:parent_id, "폴더만 상위가 될 수 있습니다")
    end
  end
end
