# ============================================================================
# COOA 데모 시드 — 화장품 규제 사전검토 워크벤치
#  · 제품은 자기참조 트리(노션형). 루트=상위 개념, 자식=국가/용량 변형.
#  · 규제 데이터는 cooa_obsidian 규제자료 CSV에서 추린 실제 fact_id/citation 기반.
#  · 히어로: 레티놀 3% 세럼 / 일본(CO0001) / 단상자 v5 → v6 비교.
# ============================================================================

puts "Clearing..."
[ScreeningFinding, ScreeningRun, AnnotationComment, Annotation, LabelText, Ingredient,
 ComponentVersion, Component, ProductMember, ProductProperty, Product, User,
 IngredientLimit, LabelRequirement, AdRiskExpression].each(&:delete_all)

# ── 사용자 / 팀 ─────────────────────────────────────────────────────────────
kim  = User.create!(name: "김쿠아", role: "designer", avatar_color: "#8e0300", email: "kim@cooa.dev")
song = User.create!(name: "송쿠아", role: "pm",       avatar_color: "#4f74e3", email: "song@cooa.dev")
lee  = User.create!(name: "이쿠아", role: "ra",       avatar_color: "#d65f9a", email: "lee@cooa.dev")
park = User.create!(name: "박쿠아", role: "scm",      avatar_color: "#5f9e57", email: "park@cooa.dev")
TEAM = [kim, song, lee, park]

# ── 규제 데이터 (실제 CSV 큐레이션) ─────────────────────────────────────────
puts "Regulatory facts..."
[
  { country: "JP", inci_canonical: "RETINOL", cas: "68-26-8", restriction_type: "max_concentration",
    max_pct: 1.0, max_pct_unit: "percent_w/w", category: "leave-on", status: "structured",
    fact_id: "jp-retinol", citation: "jp-mhlw-notification-331-2000#annex-2" },
  { country: "CN", inci_canonical: "RETINOL", cas: "0-00-0", restriction_type: "max_concentration",
    max_pct: 1.0, max_pct_unit: "percent", category: "leave-on", status: "unverified",
    fact_id: "cn-7950", citation: "cn-iecic-2021#entry-6162" },
  { country: "US", inci_canonical: "RETINOL", cas: "68-26-8", restriction_type: "unrestricted",
    max_pct: nil, category: "leave-on", status: "structured",
    fact_id: "us-retinol", citation: "us-fda-21cfr-700#cosmetic-boundary" },
  { country: "JP", inci_canonical: "NIACINAMIDE", cas: "98-92-0", restriction_type: "unrestricted",
    category: "all", status: "structured", fact_id: "jp-niac", citation: "jp-mhlw-notification-331-2000#annex-3" },
  { country: "US", inci_canonical: "NIACINAMIDE", cas: "98-92-0", restriction_type: "unrestricted",
    category: "all", status: "structured", fact_id: "us-niac", citation: "us-fda-21cfr-700#permitted" },
  { country: "CN", inci_canonical: "NIACINAMIDE", cas: "0-00-0", restriction_type: "unrestricted",
    category: "all", status: "unverified", fact_id: "cn-9147", citation: "cn-iecic-2021#entry-7359" },
  { country: "JP", inci_canonical: "SQUALANE", cas: "111-01-3", restriction_type: "unrestricted",
    category: "all", status: "structured", fact_id: "jp-squa", citation: "jp-mhlw-notification-331-2000#annex-3" },
  { country: "CN", inci_canonical: "SQUALANE", cas: "0-00-0", restriction_type: "max_concentration",
    max_pct: 48.98, max_pct_unit: "percent", category: "leave-on", status: "unverified",
    fact_id: "cn-5225", citation: "cn-iecic-2021#entry-3432" },
  { country: "JP", inci_canonical: "SODIUM HYALURONATE", cas: "9067-32-7", restriction_type: "unrestricted",
    category: "all", status: "structured", fact_id: "jp-hyal", citation: "jp-mhlw-notification-331-2000#annex-3" },
  { country: "US", inci_canonical: "SODIUM HYALURONATE", cas: "9067-32-7", restriction_type: "unrestricted",
    category: "all", status: "structured", fact_id: "us-hyal", citation: "us-fda-21cfr-700#permitted" },
  { country: "JP", inci_canonical: "MERCURY", cas: "7439-97-6", restriction_type: "banned",
    category: "all", status: "structured", fact_id: "jp-013", citation: "jp-mhlw-notification-331-2000#annex-1-banned" },
  { country: "US", inci_canonical: "HYDROQUINONE", cas: "123-31-9", restriction_type: "banned",
    category: "all", status: "unverified", fact_id: "us-166", citation: "us-fda-otc-monograph#hydroquinone-vacated-2020" },
  { country: "US", inci_canonical: "TRICLOSAN", cas: "3380-34-5", restriction_type: "banned",
    category: "all", status: "unverified", fact_id: "us-206", citation: "us-wa-sb-5703#phase-1" },
  { country: "CN", inci_canonical: "SALICYLIC ACID", cas: "69-72-7", restriction_type: "max_concentration",
    max_pct: 2.0, max_pct_unit: "percent", category: "leave-on", status: "unverified",
    fact_id: "cn-1400", citation: "cn-stsccr-2015#table-3-entry-7" }
].each { |a| IngredientLimit.create!(a) }

[
  { country: "JP", item: "재활용 마크(분리배출 표시)", match_keyword: "재활용|recycl|リサイクル|分別",
    location: "외포장", required_text: "용기 포장 재질 분리배출/재활용 식별 표시", fact_id: "jp-LR-recycle",
    citation: "jp-container-packaging-recycling-law#art-1" },
  { country: "JP", item: "製造販売業者(일본 책임자/DMAH) 명칭·주소", match_keyword: "製造販売業者|dmah|日本|made in japan",
    location: "직접용기+외포장", required_text: "일본 내 製造販売業者(또는 선임 DMAH) 명칭·주소", fact_id: "jp-LR-001",
    citation: "jp-mhlw-notice-220-2001#label-matrix", parent_law: "薬機法 §61(1)" },
  { country: "JP", item: "전성분 표시(全成分)", required_text: "모든 성분 표기(INCI/일본명)", fact_id: "jp-LR-007",
    citation: "jp-mhlw-notice-220-2001#all-ingredients", location: "직접용기" },
  { country: "US", item: "Responsible person 연락처(MoCRA)", required_text: "미국 내 주소/전화/웹 — 부작용 보고 채널",
    match_keyword: "responsible|usa|united states|new york|california|u.s.", fact_id: "us-LR-001",
    citation: "us-mocra-2022#sec-364e-labeling", location: "정보패널", parent_law: "21 USC §364e" },
  { country: "US", item: "Full ingredient list (INCI)", required_text: "전성분 INCI 표기(내림차순)",
    fact_id: "us-LR-005", citation: "us-21cfr-701.3", location: "정보패널" },
  { country: "CN", item: "全成分 + 注册证编号", required_text: "전성분 + (특수화장품)注册证编号",
    fact_id: "cn-LR-001", citation: "cn-order-727-2021#art-36", location: "직접용기+외포장" }
].each { |a| LabelRequirement.create!(a) }

[
  { country: "JP", keyword_ko: "주름 개선 / 안티에이징", risk_level: "critical",
    keyword_native: "anti-aging|anti aging|アンチエイジング|シワ改善|주름 개선|주름개선",
    classification_trigger: "薬機法 — シワ改善 효능은 의약외품(医薬部外品) 승인 必須. 화장품 표방 불가.",
    fact_id: "jp-AR-004", citation: "jp-mhlw-notification-25-2009#art-1-no-26" },
  { country: "JP", keyword_ko: "미백 / 화이트닝", risk_level: "critical",
    keyword_native: "whitening|미백|美白|brightening claim",
    classification_trigger: "美白 효능 표방 시 의약외품 승인 必須(PMDA 심사).",
    fact_id: "jp-AR-003", citation: "jp-mhlw-notification-25-2009#art-1-no-26" },
  { country: "CN", keyword_ko: "의료작용(치료/약효/소염)", risk_level: "critical",
    keyword_native: "치료|치유|약효|소염|살균|医疗|治疗|修复|消炎",
    classification_trigger: "Order 727 §37(1) — 의료작용 명시·암시 절대 금지(라벨·광고).",
    fact_id: "cn-AR-001", citation: "cn-order-727-2021#art-37" },
  { country: "US", keyword_ko: "주름 '감소/개선' 단정 표현", risk_level: "high",
    keyword_native: "reduces wrinkles|eliminates wrinkles|cure",
    classification_trigger: "단정적 주름 '감소' 표현은 OTC drug 분류 위험(Tretinoin 등 Rx). 'appearance' 완곡표현은 화장품.",
    fact_id: "us-AR-aging", citation: "us-fda-otc-monograph#cosmetic-drug-boundary" }
].each { |a| AdRiskExpression.create!(a) }

# ── 헬퍼 ────────────────────────────────────────────────────────────────────
COMPONENT_TYPES = %w[outer_box container insert barcode etc]
NOTION = "https://app.notion.com/p/COOA-3566d4e9b4c180ba89d9f529822feca3"

def node(name:, parent: nil, code: nil, country: nil, channel: nil, owner: nil, deadline: nil, position: 0, kind: "item")
  Product.create!(name: name, parent: parent, code: code, country: country, channel: channel,
                  owner: owner, deadline: deadline, product_type: "기획", kind: kind,
                  notion_url: (code ? NOTION : nil), position: position)
end

def build_components(product, currents:, creator:, hero_type: nil)
  COMPONENT_TYPES.each_with_index do |type, i|
    comp  = product.components.create!(component_type: type, name: Component::TYPES[type], position: i)
    cur   = currents[type] || 1
    count = (type == hero_type ? cur + 1 : cur)
    (1..count).each do |n|
      img = ("cooa/box_v#{n >= cur + 1 ? 6 : 5}.jpg" if type == "outer_box")
      comp.component_versions.create!(version_number: n, label: "[#{product.code}]",
                                      image_name: img, created_by: creator, current: (n == cur))
    end
  end
end

def assign_team(product, team)
  { "designer" => team[0], "pm" => team[1], "ra" => team[2], "scm" => team[3] }.each do |role, user|
    product.product_members.create!(user: user, role: role)
  end
end

def seed_ingredients(version)
  [
    { inci_name: "Retinol", inci_canonical: "RETINOL", cas: "68-26-8", declared_pct: 3.0 },
    { inci_name: "Niacinamide", inci_canonical: "NIACINAMIDE", cas: "98-92-0" },
    { inci_name: "Squalane", inci_canonical: "SQUALANE", cas: "111-01-3" },
    { inci_name: "Sodium Hyaluronate", inci_canonical: "SODIUM HYALURONATE", cas: "9067-32-7" }
  ].each_with_index { |a, i| version.ingredients.create!(a.merge(position: i)) }
end

# ── 제품 트리 ───────────────────────────────────────────────────────────────
puts "Product tree..."
# 레티놀 3% 세럼 (루트) → 미국(폴더)→[30ml, 50ml], 일본(리프, 히어로)
retinol   = node(name: "레티놀 3% 세럼", position: 0, kind: "folder")
us_folder = node(name: "미국", parent: retinol, country: "US", position: 0, kind: "folder")
co0000    = node(name: "30ml", parent: us_folder, code: "CO0000", country: "US", channel: "Sephora",
                 owner: kim, deadline: Date.new(2026, 6, 21), position: 0)
co0000l   = node(name: "50ml", parent: us_folder, code: "CO0000L", country: "US", channel: "Sephora",
                 owner: kim, deadline: Date.new(2026, 6, 28), position: 1)
co0001    = node(name: "일본", parent: retinol, code: "CO0001", country: "JP", channel: "QTEN",
                 owner: kim, deadline: Date.new(2026, 7, 1), position: 1)

# 비타민C 브라이트닝 앰플 (루트) → 중국
vitc   = node(name: "비타민C 브라이트닝 앰플", position: 1, kind: "folder")
co0100 = node(name: "중국", parent: vitc, code: "CO0100", country: "CN", channel: "Tmall",
              owner: song, deadline: Date.new(2026, 8, 10), position: 0)

# 시카 수딩 크림 (루트) → 미국
cica   = node(name: "시카 수딩 크림", position: 2, kind: "folder")
co0200 = node(name: "미국", parent: cica, code: "CO0200", country: "US", channel: "Amazon",
              owner: lee, deadline: Date.new(2026, 9, 5), position: 0)

# 리프(SKU)에 팀 + 구성요소
[co0000, co0000l, co0001, co0100, co0200].each { |p| assign_team(p, TEAM) }

# 데모: 히어로에 커스텀 속성(Notion식)
co0001.product_properties.create!(name: "용량", value: "30ml", position: 0)
co0001.product_properties.create!(name: "제형", value: "세럼", position: 1)
build_components(co0000,  currents: { "outer_box" => 5, "container" => 6, "insert" => 2, "barcode" => 1, "etc" => 1 }, creator: kim)
build_components(co0000l, currents: { "outer_box" => 2, "container" => 1, "insert" => 1, "barcode" => 1, "etc" => 1 }, creator: kim)
build_components(co0001,  currents: { "outer_box" => 5, "container" => 6, "insert" => 2, "barcode" => 1, "etc" => 1 }, creator: kim, hero_type: "outer_box")
build_components(co0100,  currents: { "outer_box" => 3, "container" => 2, "insert" => 1, "barcode" => 1, "etc" => 1 }, creator: kim)
build_components(co0200,  currents: { "outer_box" => 2, "container" => 1, "insert" => 1, "barcode" => 1, "etc" => 1 }, creator: kim)

# ── 히어로 상세: CO0001(일본) 단상자 v5(현 위치) · v6(비교 대상) ─────────────
puts "Hero detail (CO0001/일본 outer_box)..."
hero = co0001.components.find_by(component_type: "outer_box")
v5 = hero.component_versions.find_by(version_number: 5)
v6 = hero.component_versions.find_by(version_number: 6)

{ 2 => "오탈자 수정", 3 => "인허가 반려 반영", 4 => "전성분에서 Retinol 옆에 (3%) 추가",
  5 => "전성분 3째줄 띄어쓰기 두 개 수정", 6 => "패키지 재활용 마크 추가" }.each do |n, reason|
  hero.component_versions.find_by(version_number: n)&.update!(change_reason: reason)
end

seed_ingredients(v5)
seed_ingredients(v6)

[
  { text_type: "ad", content: "Advanced Anti-Aging Formula — Promotes Cell Turnover, Reduces Fine Lines, Evens Skin Tone", language: "en", country: "JP" },
  { text_type: "ingredient_list", content: "Retinol (3%), Niacinamide, Squalane, Sodium Hyaluronate, Water, Glycerin", language: "en", country: "JP" },
  { text_type: "label", content: "3% RETINOL SERUM  30ml / 1.01 fl oz   DISTRIBUTED BY: COOA, Seoul, Korea   MADE IN KOREA   LOT# C240601  EXP 2027.06.01", language: "en", country: "JP" }
].each { |a| v5.label_texts.create!(a) }
[
  { text_type: "ad", content: "Advanced Anti Aging Formula — Promotes Cell Turnover, Reduces Fine Lines, Evens Skin Tone", language: "en", country: "JP" },
  { text_type: "ingredient_list", content: "Retinol (3%), Niacinamide, Squalane, Sodium Hyaluronate, Water, Glycerin", language: "en", country: "JP" },
  { text_type: "label", content: "3% RETINOL SERUM  30ml / 1.01 fl oz   분리배출 재활용 마크 PET   DISTRIBUTED BY: COOA, Seoul, Korea   MADE IN KOREA", language: "en", country: "JP" }
].each { |a| v6.label_texts.create!(a) }

# ── 어노테이션(바운딩박스 피드백) — v5에 제기, 일부 v6에서 반영확인 ──
def annotate(version, seq:, box:, category:, by:, body:, before: nil, after: nil,
             attachment: nil, resolved_in: nil, resolved_by: nil)
  a = version.annotations.create!(
    seq: seq, box_x: box[0], box_y: box[1], box_w: box[2], box_h: box[3],
    category: category, before_text: before, after_text: after, created_by: by, position: seq,
    status: (resolved_in ? "resolved" : "open"),
    resolved_in_version: resolved_in, resolved_by: resolved_by,
    resolved_at: (resolved_in ? Time.current : nil)
  )
  a.comments.create!(author: by, body: body, attachment_name: attachment)
  a
end

annotate(v5, seq: 1, box: [23, 57, 13, 4], category: "오탈자", by: song,
         body: "용량 표시에서 띄어쓰기가 2개 되어 있는 것 같아서 확인 부탁드립니다!",
         before: "30ml  /  1.01 fl oz", after: "30ml / 1.01 fl oz", resolved_in: v6, resolved_by: kim)
annotate(v5, seq: 2, box: [63, 52, 9, 4], category: "오탈자", by: lee,
         body: "전성분 'Acid' 뒤 온점(.) 추가 확인 부탁드립니다.",
         before: "Acid", after: "Acid.", resolved_in: v6, resolved_by: kim)
a3 = annotate(v5, seq: 3, box: [48, 49, 10, 4], category: "오탈자", by: lee,
              body: "Squalane 옆에 쉼표 붙여주세요!",
              before: "Squalane", after: "Squalane,", resolved_in: v6, resolved_by: kim)
a3.comments.create!(author: kim, body: "v6에서 쉼표 반영했습니다. 확인 부탁드려요.")
annotate(v5, seq: 4, box: [69.5, 70.5, 9, 6], category: "인허가", by: park,
         body: "재활용 표기(분리배출 마크) 표시 필요합니다!", attachment: "EU 재활용 표기.png",
         resolved_in: v6, resolved_by: kim)
annotate(v5, seq: 5, box: [62.5, 63.5, 17, 6], category: "인허가", by: lee,
         body: "일본 수출용은 製造販売業者(또는 선임 DMAH) 명칭·주소가 필수입니다. 현재 'MADE IN KOREA'만 있어 미반영입니다.")

# ── 미국 30ml(CO0000) 단상자 v5 — 대조군(대체로 적합) ───────────────────────
us5 = co0000.components.find_by(component_type: "outer_box").component_versions.find_by(version_number: 5)
seed_ingredients(us5)
[
  { text_type: "ad", content: "Advanced Anti-Aging Formula — Promotes Cell Turnover, Helps reduce the appearance of fine lines", language: "en", country: "US" },
  { text_type: "ingredient_list", content: "Retinol (3%), Niacinamide, Squalane, Sodium Hyaluronate, Water, Glycerin", language: "en", country: "US" },
  { text_type: "label", content: "3% RETINOL SERUM 1.01 fl oz (30 mL)  Responsible Person: COOA USA, New York, NY  Recyclable PET  Distributed in the United States", language: "en", country: "US" }
].each { |a| us5.label_texts.create!(a) }

# ── 사전 스크리닝 ───────────────────────────────────────────────────────────
ScreeningService.new(v5,  "JP").run!(requested_by: lee)   # 일본: 위반
ScreeningService.new(us5, "US").run!(requested_by: lee)   # 미국: 적합

puts "Seed done: users=#{User.count} products=#{Product.count}(roots=#{Product.roots.count}) " \
     "components=#{Component.count} versions=#{ComponentVersion.count} " \
     "limits=#{IngredientLimit.count} ad=#{AdRiskExpression.count} runs=#{ScreeningRun.count}"
