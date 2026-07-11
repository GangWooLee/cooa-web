require "test_helper"

# DielineTextParser 순수 단위 — DB 무접촉. 입력은 pdftotext -raw 실측 출력을 본뜬 heredoc.
# (실제 dieline-01.pdf -raw 조각을 그대로 반영: db/demo/dieline.rb 생성물의 그리기 순서.)
class DielineTextParserTest < ActiveSupport::TestCase
  # 한글 도안 -raw 실측형: 헤더 "전성분 INGREDIENTS" 아래 성분 스택 → 섹션 브레이크 → 라벨(줄바꿈 분절) → 노이즈.
  KO_RAW = <<~TXT.freeze
    접착
    티트리 카밍 라인
    티트리 카밍
    토너
    30 ml
    COOA-JP-001
    COOA
    전성분 INGREDIENTS
    Zinc Oxide
    Centella Asiatica Extract
    Allantoin
    Panthenol
    표시사항 · 주의사항
    화장품 · 전성분 표기 준수
    MADE IN KOREA ·
    DISTRIBUTED BY COOA
    제조번호 LOT C260### /
    사용기한 별도 표기
    COOA-JP-001
    분리배출
    표시사항
    JP · 30 ml
    LOT C260-001
    화장품 · 전성분 표기 준수
    COOA
    단상자 전개도 · CARTON DIELINE
    티트리 카밍 토너 (COOA-JP-
    001)
    W×D×H 35 × 35 × 110 mm | SCALE 1:1
    재단선(cut) 접힘선(fold) 접착부(glue)
  TXT

  test "성분: 전성분 헤더 이후 연속 INCI 라인만 추출하고 섹션 브레이크에서 종료" do
    ings = DielineTextParser.parse(KO_RAW)[:ingredients]
    assert_equal [ "Zinc Oxide", "Centella Asiatica Extract", "Allantoin", "Panthenol" ],
                 ings.map { |i| i[:inci_name] }
    # canonical = 표기명 대문자화(db/demo/pools.rb INGREDIENTS canon 관례).
    assert_equal "CENTELLA ASIATICA EXTRACT", ings[1][:inci_canonical]
    # 섹션 브레이크 이후 라틴 라인(예: 폴백에서 나올 법한)이 성분에 새지 않음 — 헤더 다음 4개만.
    assert_equal 4, ings.size
  end

  test "성분: 영문 폴백 헤더 INGREDIENTS 도 수용" do
    txt = <<~TXT
      COOA
      INGREDIENTS
      Niacinamide
      Salicylic Acid
      Butylene Glycol
      LABELING & CAUTIONS
      LOT C260-001
    TXT
    ings = DielineTextParser.parse(txt)[:ingredients]
    assert_equal [ "Niacinamide", "Salicylic Acid", "Butylene Glycol" ], ings.map { |i| i[:inci_name] }
    assert_equal "SALICYLIC ACID", ings[1][:inci_canonical]
  end

  test "라벨: 패턴 라인 + 줄바꿈 분절 재결합 + 제품명 (CODE)" do
    contents = DielineTextParser.parse(KO_RAW)[:labels].map { |l| l[:content] }
    # 연결부호(·, /)로 끊긴 라벨이 논리 라인으로 재결합됨.
    assert_includes contents, "MADE IN KOREA · DISTRIBUTED BY COOA"
    assert_includes contents, "제조번호 LOT C260### / 사용기한 별도 표기"
    # 괄호 분절 제품명 "이름 (CODE)" 재결합.
    assert_includes contents, "티트리 카밍 토너 (COOA-JP-001)"
    # 용량·LOT·화장품 패턴.
    assert_includes contents, "화장품 · 전성분 표기 준수"
    assert_includes contents, "JP · 30 ml"
    assert_includes contents, "LOT C260-001"
    # text_type은 전부 label(PoC 한계).
    assert(DielineTextParser.parse(KO_RAW)[:labels].all? { |l| l[:text_type] == "label" })
  end

  test "노이즈: 접착·분리배출·워드마크·범례·치수·순수코드는 라벨/성분에서 배제" do
    parsed = DielineTextParser.parse(KO_RAW)
    all = (parsed[:labels].map { |l| l[:content] } + parsed[:ingredients].map { |i| i[:inci_name] })
    %w[접착 분리배출 COOA COOA-JP-001].each { |n| refute_includes all, n }
    refute(all.any? { |c| c.match?(/W×D×H|SCALE|재단선|DIELINE|전개도/) })
  end

  test "중복 제거: 동일 성분·동일 라벨 content는 1건" do
    txt = <<~TXT
      전성분 INGREDIENTS
      Panthenol
      Panthenol
      표시사항
      화장품 · 전성분 표기 준수
      화장품 · 전성분 표기 준수
    TXT
    parsed = DielineTextParser.parse(txt)
    assert_equal 1, parsed[:ingredients].size
    assert_equal 1, parsed[:labels].count { |l| l[:content] == "화장품 · 전성분 표기 준수" }
  end

  test "빈/헤더없음 입력: 안전하게 빈 결과" do
    assert_equal({ ingredients: [], labels: [] }, DielineTextParser.parse(""))
    assert_equal({ ingredients: [], labels: [] }, DielineTextParser.parse(nil))
    # 성분 헤더가 없으면 성분 0(라벨은 패턴만으로 독립 추출).
    assert_empty DielineTextParser.parse("30 ml\nLOT C260-001")[:ingredients]
  end
end
