module UiHelper
  # 인라인 SVG 아이콘 (lucide 스타일, currentColor 상속)
  ICON_PATHS = {
    "search"       => '<circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/>',
    "bell"         => '<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0"/>',
    "clock"        => '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    "caret"        => '<path d="m6 9 6 6 6-6"/>',
    "settings"     => '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 8 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H2a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 3.6 8a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H8a1.65 1.65 0 0 0 1-1.51V2a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V8a1.65 1.65 0 0 0 1.51 1H22a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>',
    "grid"         => '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
    "layers"       => '<path d="m12 2 9 5-9 5-9-5 9-5Z"/><path d="m3 12 9 5 9-5"/><path d="m3 17 9 5 9-5"/>',
    "folder"       => '<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
    "doc"          => '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/>',
    "user"         => '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="10" r="3"/><path d="M6.5 18.5a6 6 0 0 1 11 0"/>',
    "plus"         => '<path d="M12 5v14M5 12h14"/>',
    "minus"        => '<path d="M5 12h14"/>',
    "plus_circle"  => '<circle cx="12" cy="12" r="9"/><path d="M12 8v8M8 12h8"/>',
    "filter"       => '<path d="M3 4h18l-7 8v6l-4 2v-8Z"/>',
    "sort"         => '<path d="M3 6h12M3 12h9M3 18h6"/><path d="m17 9 3-3 3 3"/><path d="M20 6v12"/>',
    "check"        => '<path d="M20 6 9 17l-5-5"/>',
    "warn"         => '<path d="M12 9v4M12 17h.01"/><path d="M10.3 3.9 2 18a2 2 0 0 0 1.7 3h16.6a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0Z"/>',
    "x"            => '<path d="M18 6 6 18M6 6l12 12"/>',
    "x_circle"     => '<circle cx="12" cy="12" r="9"/><path d="m15 9-6 6M9 9l6 6"/>',
    "check_circle" => '<circle cx="12" cy="12" r="9"/><path d="m8.5 12 2.5 2.5 4.5-4.5"/>',
    "question"     => '<circle cx="12" cy="12" r="9"/><path d="M9.1 9a3 3 0 0 1 5.8 1c0 2-3 3-3 3"/><path d="M12 17h.01"/>',
    "calendar"     => '<rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/><path d="m9 16 2 2 4-4"/>',
    "pin"          => '<path d="M12 21s-7-6.3-7-11a7 7 0 0 1 14 0c0 4.7-7 11-7 11Z"/><circle cx="12" cy="10" r="2.5"/>',
    "comment"      => '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2Z"/>',
    "external"     => '<path d="M15 3h6v6"/><path d="M10 14 21 3"/><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>',
    "upload"       => '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="M7 9l5-5 5 5"/><path d="M12 4v12"/>',
    "spark"        => '<path d="M12 3v4M12 17v4M3 12h4M17 12h4M5.6 5.6l2.8 2.8M15.6 15.6l2.8 2.8M18.4 5.6l-2.8 2.8M8.4 15.6l-2.8 2.8"/>',
    "pencil"       => '<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z"/>',
    "trash"        => '<path d="M3 6h18"/><path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/><path d="M10 11v6M14 11v6"/>',
    "dots"         => '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
    "panel-left"   => '<rect width="18" height="18" x="3" y="3" rx="2"/><path d="M9 3v18"/>',
    "logout"       => '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="m16 17 5-5-5-5"/><path d="M21 12H9"/>'
  }.freeze

  # 장식용 아이콘은 기본 aria-hidden(a11y-6) — 접근성 트리에서 무명 노출 방지. 의미를 단독 전달하는
  # 아이콘(라벨 없는 곳)만 decorative: false로 opt-out하고 호출부에서 aria-label/title로 이름을 준다.
  def ui_icon(name, size: 20, stroke: 1.7, klass: nil, decorative: true)
    paths = ICON_PATHS[name.to_s]
    return "".html_safe unless paths
    content_tag :svg, paths.html_safe,
                xmlns: "http://www.w3.org/2000/svg", width: size, height: size,
                viewBox: "0 0 24 24", fill: "none", stroke: "currentColor",
                "stroke-width": stroke, "stroke-linecap": "round", "stroke-linejoin": "round",
                "aria-hidden": (decorative ? "true" : nil),
                class: [ "inline-block shrink-0", klass ].compact.join(" ")
  end

  # 버전 칩 (그라데이션 사각형 + V#)
  def version_chip(text, size: 28, active: true)
    base = active ? "bg-cooa-gradient text-white border border-transparent" : "bg-white border-2 border-line text-ink"
    content_tag :span, text,
                class: "#{base} inline-flex items-center justify-center rounded-md font-bold leading-none",
                style: "width:#{size}px;height:#{size}px;font-size:#{(size * 0.46).round}px"
  end

  # 담당자 아바타 (이름 첫 글자 + 브랜드 컬러). User·Account 다형(name/avatar_color/role_short 리졸버).
  # 표시 정체성이 없으면(이름 blank — 예: user 미연결 계정) 구 semantics대로 아무것도 렌더하지 않는다(리뷰 F3).
  def avatar(user, size: 26, ring: true)
    initial = user&.name.to_s.first
    return "".html_safe if initial.blank?
    content_tag :span, initial,
                class: "inline-flex items-center justify-center rounded-full font-bold text-white #{'ring-2 ring-white' if ring}",
                style: "width:#{size}px;height:#{size}px;font-size:#{(size * 0.42).round}px;background:#{user.avatar_color}",
                title: [ user.name, user.role_short ].compact.join(" ")
  end

  # 가시 조상 체인 (Stage 2 D3 브랜드명 유출 차단): 스코프 한정 계정에는 policy-가시 조상만 남긴다.
  # 가시성은 하향 서브트리 폐포라 가시 조상은 self로 끝나는 연속 접미부 → select(가시)가 곧 그 접미부.
  # tenant-wide/데모 User(visible_product_id_set=nil)엔 no-op(전체 반환) → 무회귀·추가쿼리 0.
  def visible_ancestors(node)
    chain = node.self_and_ancestors
    set = visible_product_id_set
    return chain if set.nil?

    chain.select { |a| set.include?(a.id) }
  end

  # 전체 경로 라벨(가시 조상만) — 드로어 "경로"·트리 data-node-path 공용. 모델 path_label과 달리 액터
  # 가시성 인지(권한 없는 상위 브랜드명 비노출).
  def node_path_label(node) = visible_ancestors(node).map(&:name).join(" › ")

  # 조상 경로 브레드크럼 (루트 › … › 현재 [› trailing]) — 가시 조상만
  #  · 폴더 세그먼트 → 대시보드(해당 폴더 펼침)  · 리프 세그먼트 → 드로어
  def node_breadcrumb(product, trailing: nil)
    sep = content_tag(:span, "›", class: "px-1 text-muted")
    crumbs = visible_ancestors(product).map do |a|
      href = a.folder? ? root_path(focus: a.id) : product_path(a)
      link_to(a.name, href, class: "text-muted hover:text-cooa")
    end
    crumbs << content_tag(:span, trailing, class: "text-ink") if trailing.present?
    safe_join(crumbs, sep)
  end

  # 국가 인라인 편집용 옵션(라벨=한글, 값=코드) — 표시(country_label)와 일관, 저장은 코드(JP/CN/US/KR)
  def country_options
    [ [ "— 미지정 —", "" ] ] + ApplicationRecord::COUNTRY_LABELS.map { |code, label| [ label, code ] }
  end

  # 노드 삭제 확인 문구(폴더/리프) — 단일 출처(대시보드 행·드로어·사이드바 컨텍스트 메뉴 공용)
  def delete_confirm(node)
    if node.folder?
      "'#{node.name}' 및 모든 하위 항목·구성요소·버전·피드백이 영구 삭제됩니다. 계속할까요?"
    else
      "'#{node.name}' 및 모든 구성요소·버전·피드백이 삭제됩니다. 계속할까요?"
    end
  end

  # 4-enum 판정 알약
  def decision_pill(decision)
    m = Decidable::DECISIONS[decision] || Decidable::DECISIONS["unable"]
    text_color = m[:text] || m[:color]
    content_tag :span, class: "inline-flex items-center gap-1.5 rounded-full border px-3 py-1 text-body font-bold",
                       style: "color:#{text_color};background:#{m[:bg]};border-color:#{m[:color]}" do
      concat content_tag(:span, ui_icon(m[:icon], size: 15, stroke: 2.2), style: "color:#{m[:color]}")
      concat m[:label]
    end
  end

  # 피드백 상태 알약 (3중 신호: 아이콘 + 라벨 + 색). decision_pill과 동형. extra로 정렬 유틸(ml-auto 등) 흡수.
  def annotation_status_pill(annotation, extra: nil)
    m = annotation.status_meta
    text_color = m[:text] || m[:color]
    content_tag :span, class: [ "inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-caption font-bold", extra ].compact.join(" "),
                       style: "color:#{text_color};background:#{m[:bg]};border-color:#{m[:color]}" do
      concat content_tag(:span, ui_icon(m[:icon], size: 11, stroke: 2.4), style: "color:#{m[:color]}")
      concat m[:label]
    end
  end

  # ── 표준 버튼 (단일 진실원) ────────────────────────────────────────────────
  # radius rounded-lg 1종 · size별 padding/텍스트 고정 · disabled · focus-visible 링 내장.
  # 브랜드 그라데이션 프라이머리는 홈 "새 작업실" 히어로 1곳만 예외(여기 미포함).
  BTN_BASE = "inline-flex items-center justify-center rounded-lg font-semibold transition cursor-pointer " \
             "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cooa/50 focus-visible:ring-offset-1 " \
             "disabled:pointer-events-none disabled:opacity-50"
  BTN_VARIANTS = {
    primary:   "bg-cooa text-white hover:bg-cooa-dark",              # 채움 · 주요 CTA
    secondary: "border border-cooa bg-white text-cooa hover:bg-accent", # 아웃라인 · 보조 액션(로그인 등)
    ghost:     "text-muted hover:bg-tint hover:text-ink",            # 무테 저강도 · 취소/닫기/부차
    danger:    "border border-warn bg-white text-warn hover:bg-warn hover:text-white", # 파괴적
    ok:        "border border-ok-strong bg-ok-soft text-ink hover:bg-white" # 확인/반영(그린 아웃라인·ink 라벨)
  }.freeze
  BTN_SIZES = { sm: "gap-1 px-3 py-1.5 text-meta", md: "gap-1.5 px-4 py-2 text-body" }.freeze

  # 클래스 문자열만 반환 — button_to / f.submit / submit_tag 등 자체 폼·메서드가 필요한 버튼류에서 직접 사용.
  def ui_button_classes(variant: :primary, size: :md, extra: nil)
    [ BTN_BASE, BTN_VARIANTS.fetch(variant), BTN_SIZES.fetch(size), extra ].compact.join(" ")
  end

  # 표준 버튼. href: → <a>(link_to) · 그 외 → <button>(기본 type="button"). 블록(아이콘+라벨) 지원.
  def ui_button(label = nil, variant: :primary, size: :md, **opts, &block)
    klass = ui_button_classes(variant:, size:, extra: opts.delete(:class))
    body  = block ? capture(&block) : label
    if (href = opts.delete(:href))
      link_to body, href, class: klass, **opts
    else
      opts[:type] ||= "button"
      button_tag body, class: klass, **opts
    end
  end

  # 아이콘 단독 버튼 정본 — 정사각 히트영역(28px) + 아이콘(기본 16) · ghost 톤 · focus-visible 링 · aria-label 필수.
  # href: → <a>(link_to) · 그 외 → <button>. title은 opts로 병기 가능(툴팁). ui_button과 동형 API.
  ICON_BTN_BASE = "inline-flex h-7 w-7 shrink-0 items-center justify-center rounded-lg transition cursor-pointer " \
                  "text-muted hover:bg-tint hover:text-ink " \
                  "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cooa/50 focus-visible:ring-offset-1 " \
                  "disabled:pointer-events-none disabled:opacity-50"
  def icon_button(icon, aria_label:, size: 16, stroke: 1.7, **opts)
    klass = [ ICON_BTN_BASE, opts.delete(:class) ].compact.join(" ")
    body  = ui_icon(icon, size: size, stroke: stroke)
    opts[:"aria-label"] = aria_label
    if (href = opts.delete(:href))
      link_to body, href, class: klass, **opts
    else
      opts[:type] ||= "button"
      button_tag body, class: klass, **opts
    end
  end

  # 아트워크 URL 해석(단일 진실원): 업로드 첨부(ActiveStorage) > 정적 에셋(image_name) > nil.
  # rails_blob_path(루트상대)로 host 불필요 — <img src>·background-image:url() 모두 호환.
  # (url_for/rails_blob_url은 view에서 host 필요 → 사용 금지)
  def artwork?(version)
    version && (version.artwork.attached? || version.image_name.present?)
  end

  def artwork_src(version)
    return nil unless version
    return rails_blob_path(version.artwork, only_path: true) if version.artwork.attached?
    image_path(version.image_name) if version.image_name.present?
  end

  # 래스터가 필요한 보조 UI(미니맵·필름스트립 크롭) 전용 소스. 메인 뷰어는 artwork_src(원본)를 쓰고
  # PDF는 PDF.js 캔버스로 렌더하지만, CSS background-crop·<img>는 래스터를 요구하므로 PDF는 poppler
  # preview PNG(representation)로, 이미지는 원본 그대로 반환. preview 불가(poppler 부재 등)면 nil.
  def artwork_thumb_src(version)
    return nil unless version
    return artwork_src(version) unless version.artwork_pdf?
    return nil unless version.artwork.representable?
    # 명명 variant(:thumb) — 모델의 preprocessed 선언과 동일 키를 써야 선생성 캐시가 적중(PERF-2)
    rails_representation_path(version.artwork.representation(:thumb), only_path: true)
  end

  IMG_RATIO = 2048.0 / 1118.0 # 박스 전개도 가로/세로 비

  # 어노테이션 → 아트워크 뷰어 박스 배열
  def annotation_boxes(annotations)
    annotations.map do |a|
      { seq: a.seq, x: a.box_x, y: a.box_y, w: a.box_w, h: a.box_h, color: a.box_color,
        fill: "color-mix(in srgb, #{a.box_color} 12%, transparent)", label: a.seq }
    end
  end

  # 스크리닝 finding → 박스 배열 (박스 지정된 것만)
  def finding_boxes(findings)
    findings.select(&:boxed?).each_with_index.map do |f, i|
      color = f.decision_meta[:color]
      { seq: i + 1, finding_id: f.id, x: f.box_x, y: f.box_y, w: f.box_w, h: f.box_h,
        color:, fill: "color-mix(in srgb, #{color} 12%, transparent)", label: i + 1 }
    end
  end

  # 박스 영역 크롭 배경(경로 직접) — 썸네일 필름스트립용. size/position만 반환.
  def crop_bg(image_src, x, y, w, h)
    return "" if image_src.blank?
    w = w.to_f; h = h.to_f; x = x.to_f; y = y.to_f
    return "" if w <= 0 || h <= 0
    posx = w >= 100 ? 0 : (x / (100 - w) * 100).round(2)
    posy = h >= 100 ? 0 : (y / (100 - h) * 100).round(2)
    "background-image:url('#{image_src}');" \
      "background-size:#{(10000.0 / w).round(2)}% #{(10000.0 / h).round(2)}%;" \
      "background-position:#{posx}% #{posy}%;background-repeat:no-repeat"
  end

  # 박스 종횡비 (썸네일 width 계산용)
  def box_aspect(w, h)
    h = h.to_f
    return 1.0 if h <= 0
    (w.to_f * IMG_RATIO / h).round(3)
  end
end
