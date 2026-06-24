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
    "spark"        => '<path d="M12 3v4M12 17v4M3 12h4M17 12h4M5.6 5.6l2.8 2.8M15.6 15.6l2.8 2.8M18.4 5.6l-2.8 2.8M8.4 15.6l-2.8 2.8"/>'
  }.freeze

  def ui_icon(name, size: 20, stroke: 1.7, klass: nil)
    paths = ICON_PATHS[name.to_s]
    return "".html_safe unless paths
    content_tag :svg, paths.html_safe,
                xmlns: "http://www.w3.org/2000/svg", width: size, height: size,
                viewBox: "0 0 24 24", fill: "none", stroke: "currentColor",
                "stroke-width": stroke, "stroke-linecap": "round", "stroke-linejoin": "round",
                class: ["inline-block shrink-0", klass].compact.join(" ")
  end

  # 버전 칩 (그라데이션 사각형 + V#)
  def version_chip(text, size: 28, active: true)
    base = active ? "bg-cooa-gradient text-white border border-transparent" : "bg-white border-2 border-line text-ink"
    content_tag :span, text,
                class: "#{base} inline-flex items-center justify-center rounded-md font-bold leading-none",
                style: "width:#{size}px;height:#{size}px;font-size:#{(size * 0.46).round}px"
  end

  # 담당자 아바타 (이름 첫 글자 + 브랜드 컬러)
  def avatar(user, size: 26, ring: true)
    return "".html_safe unless user
    content_tag :span, user.name.to_s.first,
                class: "inline-flex items-center justify-center rounded-full font-bold text-white #{'ring-2 ring-white' if ring}",
                style: "width:#{size}px;height:#{size}px;font-size:#{(size * 0.42).round}px;background:#{user.avatar_color}",
                title: "#{user.name} #{user.role_short}"
  end

  # 조상 경로 브레드크럼 (루트 › … › 현재 [› trailing])
  def node_breadcrumb(product, trailing: nil)
    sep = content_tag(:span, "›", class: "px-1 text-line")
    crumbs = product.self_and_ancestors.map { |a| link_to(a.name, product_path(a), class: "text-line hover:text-cooa") }
    crumbs << content_tag(:span, trailing, class: "text-ink") if trailing.present?
    safe_join(crumbs, sep)
  end

  # 4-enum 판정 알약
  def decision_pill(decision)
    m = Decidable::DECISIONS[decision] || Decidable::DECISIONS["unable"]
    content_tag :span, class: "inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-[13px] font-bold",
                       style: "color:#{m[:color]};background:#{m[:bg]}" do
      concat ui_icon(m[:icon], size: 15, stroke: 2.2)
      concat m[:label]
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

  IMG_RATIO = 2048.0 / 1118.0 # 박스 전개도 가로/세로 비

  # 어노테이션 → 아트워크 뷰어 박스 배열
  def annotation_boxes(annotations)
    annotations.map { |a| { seq: a.seq, x: a.box_x, y: a.box_y, w: a.box_w, h: a.box_h, color: a.box_color, label: a.seq } }
  end

  # 스크리닝 finding → 박스 배열 (박스 지정된 것만)
  def finding_boxes(findings)
    findings.select(&:boxed?).each_with_index.map do |f, i|
      { seq: i + 1, finding_id: f.id, x: f.box_x, y: f.box_y, w: f.box_w, h: f.box_h, color: f.decision_meta[:color], label: i + 1 }
    end
  end

  # 박스 영역만 확대해 보여주는 크롭 배경 스타일 (이전|현재 비교용)
  def crop_style(image_name, x, y, w, h)
    return "" if image_name.blank?
    w = w.to_f; h = h.to_f; x = x.to_f; y = y.to_f
    return "" if w <= 0 || h <= 0
    posx = w >= 100 ? 0 : (x / (100 - w) * 100).round(2)
    posy = h >= 100 ? 0 : (y / (100 - h) * 100).round(2)
    "background-image:url('#{image_path(image_name)}');" \
      "background-size:#{(10000.0 / w).round(2)}% #{(10000.0 / h).round(2)}%;" \
      "background-position:#{posx}% #{posy}%;background-repeat:no-repeat;" \
      "aspect-ratio:#{(w * IMG_RATIO / h).round(3)};min-height:84px"
  end

  # 박스 영역 크롭 배경(경로 직접) — 썸네일 필름스트립용. size/position만 반환.
  def crop_bg(image_src, x, y, w, h)
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
