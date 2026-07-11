# 도안 추출 원문(PdfTextExtractor) → 성분/라벨 후보로 파싱하는 순수 함수. LLM·OCR·성분 사전 없음 —
# 단상자 전개도 텍스트의 관찰된 규칙성만 이용하는 휴리스틱 PoC다(실측 대상: db/demo/dieline.rb 생성물).
#   ⓐ 성분 = "전성분/INGREDIENTS" 헤더 이후 연속된 INCI형(라틴 Title-Case) 라인. 섹션 브레이크(전대문자
#      헤더·한글·기호 라인)나 빈 줄에서 종료 · inci_canonical 기준 중복 제거.
#   ⓑ 라벨 = 화장품·MADE IN·제조번호·LOT·사용기한·용량, 그리고 제품명 "이름 (CODE)" 패턴 라인. content 중복 제거.
#   ⓒ 노이즈(재단선 범례·치수·바코드 코드·접착부·워드마크 등)는 상수 필터로 배제.
# 한계(정직): text_type은 전부 "label" — 광고 문구/라벨 필수항목 세분류는 PoC 밖이다. 성분 canonical은
#   표기명 대문자화라, 식물성 INCI 매핑(예: "Tea Tree Leaf Oil" → "MELALEUCA ALTERNIFOLIA LEAF OIL")은
#   못 한다(사전이 필요). db/demo/pools.rb INGREDIENTS 튜플의 canonical(대문자) 관례를 따른다.
class DielineTextParser
  # 성분 섹션 헤더 — 한글 도안 "전성분 INGREDIENTS"·영문 폴백 "INGREDIENTS" 모두 이 토큰을 포함(dieline.rb
  # draw_side: head = kr ? "전성분 INGREDIENTS" : "INGREDIENTS"). 라벨 "…전성분 표기 준수"는 이 토큰이
  # 없어 헤더로 오인되지 않는다.
  INGREDIENTS_HEADER = /INGREDIENTS/i

  # 라벨 후보 패턴(라인에 하나라도 매칭되면 라벨) — 국문/영문 병행.
  LABEL_PATTERNS = [
    /화장품/,
    /제조번호/,
    /사용기한/, /\bEXP\b/i,        # 사용기한(KO) / expiry(EN)
    /\bLOT\b/i,
    /MADE\s+IN/i,
    /\b\d+\s?(?:ml|g)\b/i          # 용량(30 ml · 50 g)
  ].freeze

  # 제품명 타이틀 라인 "이름 (CODE)" — 코드는 대문자/숫자 토큰이 하이픈으로 이어진 형태(COOA-JP-001).
  PRODUCT_NAME = /\A\S.*\(\s*[A-Z0-9]{2,}(?:-[A-Z0-9]+)+\s*\)\s*\z/

  # 노이즈 — 접착부/분리배출/워드마크 단독 라인, 전개도·치수·범례, 순수 코드 라인(바코드 캡션).
  NOISE_PATTERNS = [
    /\A(?:GLUE|접착)\z/i,
    /\A(?:PET|분리배출)\z/i,
    /\ACOOA\z/i,
    /전개도|DIELINE/i,
    /W×D×H|SCALE/i,
    /재단선|접힘선|접착부|cut line|fold line|glue area/i,
    /\A[A-Z0-9]{2,}(?:-[A-Z0-9]+)+\z/   # 순수 코드(COOA-JP-001) — 라벨/성분 아님
  ].freeze

  class << self
    def parse(text)
      lines = join_wrapped(normalize(text))
      { ingredients: ingredients(lines), labels: labels(lines) }
    end

    private

    # 원문 → 라인 배열(폼피드 제거·양끝 공백 정리). 빈 줄은 보존한다(성분 블록의 "빈 줄 런 종료" 판정용).
    def normalize(text)
      text.to_s.split(/\r?\n/).map { |l| l.delete("\f").strip }
    end

    # 줄바꿈으로 조각난 라벨/제품명을 논리 라인으로 재결합. 트리거: 앞 줄이 연결부호(·, /)로 끝나거나,
    # 괄호가 안 닫혔거나("… (COOA-JP-"), 뒤 줄이 "("로 시작(영문 타이틀 "…001" + "(CODE)"). 앞 줄이 "-"로
    # 끝나면 공백 없이 이어붙여 코드가 쪼개지지 않게 한다("COOA-JP-" + "001)" → "COOA-JP-001)"). 성분 라인은
    # 이 트리거에 걸리지 않아(짧은 Title-Case) 블록이 훼손되지 않는다.
    def join_wrapped(lines)
      lines.each_with_object([]) do |line, out|
        if !line.empty? && !out.last.to_s.empty? && continuation?(out.last, line)
          sep = out.last.end_with?("-") ? "" : " "
          out[-1] = "#{out.last}#{sep}#{line}"
        else
          out << line
        end
      end
    end

    def continuation?(prev, cur)
      prev.match?(%r{[·/]\z}) || prev.count("(") > prev.count(")") || cur.start_with?("(")
    end

    # ⓐ 성분: 헤더 다음 줄부터 연속 INCI형 라인 수집(섹션 브레이크·빈 줄에서 종료). canonical 기준 중복 제거.
    def ingredients(lines)
      idx = lines.find_index { |l| l.match?(INGREDIENTS_HEADER) }
      return [] unless idx

      seen = []
      lines[(idx + 1)..].to_a.each_with_object([]) do |line, out|
        break out if line.empty? || !inci_line?(line)

        name  = line.squeeze(" ")
        canon = name.upcase
        next if seen.include?(canon)

        seen << canon
        out << { inci_name: name, inci_canonical: canon }
      end
    end

    # INCI형 = 라틴 대문자로 시작 · 라틴/숫자/공백/하이픈만 · 소문자 최소 1개(전대문자 섹션 헤더·순수 코드 배제).
    def inci_line?(line)
      line.match?(/\A[A-Z][A-Za-z0-9]*(?:[ \-][A-Za-z0-9]+)*\z/) && line.match?(/[a-z]/)
    end

    # ⓑ 라벨: 노이즈 제외 후 라벨 패턴 또는 제품명 패턴 매칭 라인. content 기준 중복 제거.
    def labels(lines)
      seen = []
      lines.each_with_object([]) do |line, out|
        next if line.empty? || noise?(line) || !label_line?(line)

        content = line.squeeze(" ")
        next if seen.include?(content)

        seen << content
        out << { content: content, text_type: "label" }
      end
    end

    def label_line?(line) = line.match?(PRODUCT_NAME) || LABEL_PATTERNS.any? { |p| line.match?(p) }
    def noise?(line) = NOISE_PATTERNS.any? { |p| line.match?(p) }
  end
end
