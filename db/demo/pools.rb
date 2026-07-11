# 이름 풀 — demo:bulk 전용(db/demo/bulk.rb가 require_relative). 한국 화장품 수출 브랜드가 실제로 쓸 법한
# 이름들. 시드(db/seeds.rb)가 쓰는 이름(레티놀 3% 세럼·비타민C 브라이트닝 앰플·시카 수딩 크림·CO****)과
# 겹치지 않게 구성한다. autoload 경로가 아니므로 상수 재정의 경고를 피하려 모듈 상수로 감싼다.
module Demo
  module Pools
    # 작업실(루트 브랜드 라인) — 신규 12개.
    ROOT_LINES = [
      "티트리 카밍 라인", "센텔라 리페어 라인", "히알루론 딥모이스처 라인", "나이아신 글로우 라인",
      "데일리 선케어 라인", "펩타이드 리프팅 라인", "AHA·BHA 클리어 라인", "마데카소사이드 수딩 라인",
      "콜라겐 탄력 라인", "프로폴리스 에너지 라인", "쌀겨 브라이트 라인", "어성초 진정 라인"
    ].freeze

    # 리프(SKU) 제품명 — 코드로 유니크를 보장하므로 이름은 트리 전반에서 반복돼도 무방.
    PRODUCT_ITEMS = [
      "티트리 카밍 토너", "선스틱 SPF50+ PA++++", "세라마이드 배리어 크림", "그린티 시드 세럼",
      "판테놀 수딩 젤", "히알루론 딥 앰플", "콜라겐 아이크림", "펩타이드 부스팅 에센스",
      "AHA 8% 필링 토너", "마데카 시카 크림", "프로폴리스 로얄 앰플", "쌀겨 효소 파우더워시",
      "어성초 진정 미스트", "무기자차 선크림 SPF50+", "달팽이 96 뮤신 에센스", "레티놀 0.1% 나이트크림",
      "비타민 B5 데일리 로션", "티트리 스팟 세럼", "센텔라 시카 밤", "PDRN 리페어 앰플",
      "24K 골드 하이드로겔 아이패치", "미로 콜라겐 마스크팩", "브라이트닝 토너 패드", "약산성 클렌징 폼",
      "쑥 진정 크림", "녹두 클레이 워시오프팩", "어성초 클렌징 오일", "히알루론 립 슬리핑마스크",
      "나이아신아마이드 10% 세럼", "세라마이드 크림 밤", "판테놀 수딩 앰플", "선쿠션 SPF50+"
    ].freeze

    # 중간 폴더 접미(브랜드 라인 아래 개발/채널 분기).
    MID_SUFFIXES = [ "수출", "리뉴얼 2026", "1차 개발", "기획세트", "레거시", "글로벌" ].freeze
    SUBFOLDER_LABELS = [ "1차 시안", "규제 반영본", "리뉴얼", "본품", "리필", "세트 구성" ].freeze
    VARIANT_SUFFIXES = [ "30ml", "50ml", "100ml", "본품", "리필", "미니", "기획", "대용량" ].freeze

    # 시장(국가) — 분포 JP:CN:US = 5:3:2 가중.
    MARKETS_WEIGHTED = %w[JP JP JP JP JP CN CN CN US US].freeze
    CHANNELS = [ "QTEN", "Qoo10", "Tmall", "JD.com", "Amazon", "Sephora", "Olive Young Global", "Watsons" ].freeze

    # 성분(정규화 자식 테이블 ingredients) — inci_name / inci_canonical / cas.
    INGREDIENTS = [
      [ "Centella Asiatica Extract", "CENTELLA ASIATICA EXTRACT", "84696-21-9" ],
      [ "Tea Tree Leaf Oil", "MELALEUCA ALTERNIFOLIA LEAF OIL", "68647-73-4" ],
      [ "Panthenol", "PANTHENOL", "81-13-0" ],
      [ "Adenosine", "ADENOSINE", "58-61-7" ],
      [ "Sodium Hyaluronate", "SODIUM HYALURONATE", "9067-32-7" ],
      [ "Niacinamide", "NIACINAMIDE", "98-92-0" ],
      [ "Ceramide NP", "CERAMIDE NP", "100403-19-8" ],
      [ "Madecassoside", "MADECASSOSIDE", "34540-22-2" ],
      [ "Propolis Extract", "PROPOLIS EXTRACT", "85665-41-4" ],
      [ "Glycerin", "GLYCERIN", "56-81-5" ],
      [ "Butylene Glycol", "BUTYLENE GLYCOL", "107-88-0" ],
      [ "Allantoin", "ALLANTOIN", "97-59-6" ],
      [ "Beta-Glucan", "BETA-GLUCAN", "9012-72-0" ],
      [ "Snail Secretion Filtrate", "SNAIL SECRETION FILTRATE", "" ],
      [ "Zinc Oxide", "ZINC OXIDE", "1314-13-2" ],
      [ "Titanium Dioxide", "TITANIUM DIOXIDE", "13463-67-7" ],
      [ "Salicylic Acid", "SALICYLIC ACID", "69-72-7" ],
      [ "Tocopherol", "TOCOPHEROL", "59-02-9" ]
    ].freeze

    # 라벨 문구(label) — 나라 무관 공통 표기.
    LABEL_CONTENTS = [
      "화장품 · 전성분 표기 준수",
      "제조번호 LOT C260### / 사용기한 별도 표기",
      "MADE IN KOREA · DISTRIBUTED BY COOA",
      "사용상의 주의사항: 직사광선을 피해 보관",
      "용기·포장 분리배출 표시 PET/유리/종이",
      "책임판매업자: (주)쿠아, 서울"
    ].freeze
    # 광고/표현(ad) — 일부는 스크리닝에서 걸릴 법한 경계 문구를 섞음.
    AD_CONTENTS = [
      "24시간 수분 지속 보습 케어",
      "저자극 테스트 완료 · 민감 피부 진정",
      "안티에이징 집중 케어 — 주름 개선",
      "미백 기능성 · 브라이트닝 케어",
      "피부 장벽 강화 · 재생 부스팅",
      "모공 타이트닝 · 매끈한 결 정돈",
      "SPF50+ PA++++ 강력 자외선 차단",
      "빠른 흡수 · 산뜻한 마무리"
    ].freeze
    INGREDIENT_LIST_PREFIX = "전성분: ".freeze

    # 어노테이션(피드백) 본문 + 답글.
    ANNOTATION_BODIES = [
      "전성분 표기 순서를 함량 내림차순으로 확인 부탁드립니다.",
      "폰트 크기가 규정 하한보다 작아 보입니다. 확대 검토 바랍니다.",
      "재활용(분리배출) 마크 위치 조정이 필요합니다.",
      "용량 표기 띄어쓰기가 두 칸입니다. 한 칸으로 수정해 주세요.",
      "Responsible Person 주소가 최신인지 재확인 바랍니다.",
      "성분명 오탈자가 있습니다(수정 요망).",
      "광고 문구가 의약외품 경계로 보입니다. RA 검토 필요합니다.",
      "바코드 여백(quiet zone)이 부족해 스캔 오류 우려됩니다.",
      "제조판매업자(DMAH) 표기가 누락되었습니다.",
      "이미지 해상도가 낮습니다. 인쇄용 원본으로 교체 바랍니다.",
      "성분 함량(%) 병기가 규정과 일치하는지 확인해 주세요.",
      "주의사항 문구가 현지 언어로 번역되어야 합니다."
    ].freeze
    ANNOTATION_REPLIES = [
      "확인했습니다. 다음 버전에 반영하겠습니다.",
      "반영 완료했습니다. 재검토 부탁드려요.",
      "RA 검토 후 회신드리겠습니다.",
      "디자인팀과 협의해 수정하겠습니다.",
      "규제 근거 확인했고, 문구 완화안으로 진행합니다.",
      "인쇄 원본 교체했습니다."
    ].freeze
    ANNOTATION_CATEGORIES = %w[오탈자 인허가 디자인 기타].freeze

    # 버전 변경 사유.
    CHANGE_REASONS = [
      "오탈자 수정", "전성분 순서 정정", "재활용 마크 추가", "인허가 반려 반영",
      "광고 문구 완화", "레이아웃 리뉴얼", "용량 표기 변경", "바코드 교체",
      "1차 시안", "색상 보정", "현지 언어 번역 반영", "제조판매업자 표기 추가"
    ].freeze
    # 정적 아트워크 이미지 파일명(시드와 동일 규약 — 첨부 없이 유효).
    IMAGE_NAMES = %w[cooa/box_v5.jpg cooa/box_v6.jpg].freeze

    # 스크리닝 요약(판정별).
    SCREENING_SUMMARIES = {
      "ok"        => "규제 사전검토 결과 위반 사항이 발견되지 않았습니다.",
      "warning"   => "일부 성분·표현에 주의가 필요합니다. RA 확인을 권장합니다.",
      "violation" => "금지 성분 또는 표현 위반이 감지되었습니다. 수정이 필요합니다.",
      "unable"    => "데이터 미검증 항목이 있어 자동 판단이 불가합니다. 수동 검토 필요."
    }.freeze
    # 스크리닝 finding 소재.
    FINDING_SUBJECTS = [
      "미백", "주름 개선", "안티에이징", "Salicylic Acid", "재활용 표기",
      "제조판매업자 표기", "전성분 표기", "의료작용 표현", "Titanium Dioxide", "responsible person"
    ].freeze
    FINDING_ISSUES = [
      "표방 시 의약외품 승인이 필요한 경계 표현입니다.",
      "라벨 필수 항목이 누락되었습니다.",
      "선언 농도가 현지 한도를 초과할 수 있습니다(데이터 미검증).",
      "금지 표현에 해당합니다. 삭제가 필요합니다.",
      "표기 위치·크기가 규정 요건을 충족하지 못합니다."
    ].freeze
    FINDING_CITATIONS = [
      "jp-mhlw-notification-25-2009#art-1-no-26",
      "cn-order-727-2021#art-37",
      "us-mocra-2022#sec-364e-labeling",
      "jp-container-packaging-recycling-law#art-1",
      "us-21cfr-701.3"
    ].freeze
    FINDING_ELEMENT_TYPES = %w[ingredient label ad design].freeze

    # 벌크 멤버 인명(20+).
    KOREAN_NAMES = %w[
      김서연 이준호 박지민 최유진 정민석 강하늘 조은비 윤도현 임세라 한지우
      오태양 서예린 신동혁 권나연 황시우 안소희 송재현 배수빈 문가영 류현우
      남지호 고은서 표지훈 차민서
    ].freeze
    # User.role 표시 enum(designer/pm/ra/scm) 순환용.
    USER_JOB_ROLES = %w[designer pm ra scm].freeze
    # Account 아바타 색(브랜드 스와치 — Account::AVATAR_SWATCHES와 정합).
    AVATAR_COLORS = %w[#8e0300 #b23a2e #c9822b #5f8f2e #2f6f6b #2d5a8e #5b3f8e #3d3d3d].freeze
  end
end
