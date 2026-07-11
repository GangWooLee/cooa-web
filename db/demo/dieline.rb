# 파라메트릭 단상자(carton) 전개도(dieline) PDF 생성기 — demo:assets 전용. box_v5.jpg 스타일의
# 인쇄용 도안을 프로그램으로 생성해 db/demo/assets/dieline-NN.pdf 로 떨어뜨린다(외부 스톡 라이선스 0).
# lib/tasks/demo.rake 가 `load` 로 적재해 Demo::Dieline.generate!(rng:) 호출.
#
# 기하: 본체 4패널 가로 배열[front|side|back|side] + 상/하 플랩(tuck/closure/dust) + 좌측 접착탭(glue tab,
# 사선 모서리). 실측 규격(W×D×H mm)으로 좌표를 계산한다. 선 규약 = 재단선(cut) 실선 검정 · 접힘선(fold)
# 점선 회색 · 접착탭 옅은 회색 채움+해칭. 모든 무작위는 호출측 고정 RNG 로만(연속 실행 결정적).
#
# 한글 폰트: ENV["DEMO_DIELINE_FONT"] → macOS 시스템 TTF 후보 → 없으면 Helvetica 폴백(라벨 영문·code).
# .ttc 는 prawn(ttfunk) 미지원이라 후보에서 제외 — .ttf 만. 생성은 폰트 유무와 무관하게 항상 성공한다.
require "prawn"
require "fileutils"
require_relative "pools"

module Demo
  module Dieline
    include Demo::Pools
    module_function

    OUTPUT_COUNT = 24
    MM = 2.834645669 # 1mm → pt(1/72in). 프롤로그 좌표는 mm 로 계산 후 pt 로 변환.

    # 폰트 후보(우선순위) — 존재 + prawn 임베드 가능(font_embeddable?)을 모두 통과한 최초 파일. .ttc(AppleSDGothicNeo
    # 등)는 prawn(ttfunk) 미지원이라 제외 — .ttf 만. 제약: AppleGothic/AppleMyungjo 는 존재하나 ttfunk 1.8 이
    # OS/2 테이블 서브셋에서 예외를 던진다(실측 2026-07) → 임베드 검증에서 걸러지고 Arial Unicode 로 폴백한다.
    # Arial Unicode 는 한글 포함 전(全) 유니코드 커버리지라 실 사용 폰트. 재배포 리스크는 산출물 gitignore 로 차단.
    FONT_CANDIDATES = [
      "/Library/Fonts/Arial Unicode.ttf",
      "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
      "/System/Library/Fonts/Supplemental/AppleGothic.ttf",
      "/System/Library/Fonts/Supplemental/AppleMyungjo.ttf"
    ].freeze

    # 규격 프리셋 [W, D, H(mm), 용량표기] — 화장품 단상자 실측 대역. 24종이 순환(8×3)하며 이름·색으로 구분.
    DIMENSIONS = [
      [ 35, 35, 110, "30 ml" ],   # 세럼/앰플(장신)
      [ 40, 40, 120, "50 ml" ],
      [ 55, 55, 90,  "100 ml" ],
      [ 60, 60, 60,  "50 g" ],    # 크림 자(정육면체형)
      [ 70, 70, 75,  "75 g" ],
      [ 50, 30, 150, "120 ml" ],  # 슬림 장신(튜브 박스)
      [ 45, 45, 100, "50 ml" ],
      [ 80, 55, 45,  "12 g" ]     # 광폭 저상(팔레트형)
    ].freeze

    MARKETS = %w[JP CN US].freeze

    # 폰트 미검출 시 쓰는 ASCII 라벨 풀(한글 대체) — 생성 무조건 성공을 위한 안전판.
    ASCII_LABELS  = [ "MADE IN KOREA", "DIST. BY COOA, SEOUL", "LOT / EXP: SEE BOTTOM",
                      "STORE AWAY FROM SUNLIGHT", "FOR EXTERNAL USE ONLY" ].freeze
    ASCII_LINE    = "COOA SKINCARE LINE".freeze

    def default_dir
      defined?(Rails) ? Rails.root.join("db/demo/assets").to_s : File.expand_path("assets", __dir__)
    end

    # ENV 우선 → 후보 중 존재+임베드가능 최초 파일. 하나도 없으면 nil(Helvetica 폴백 → 라벨 영문·code).
    def resolve_font
      env = ENV["DEMO_DIELINE_FONT"].to_s
      candidates = env.empty? ? FONT_CANDIDATES : [ env ] + FONT_CANDIDATES
      candidates.find { |p| File.file?(p) && font_embeddable?(p) }
    end

    # 실제 서브셋 임베드(작은 PDF 렌더)까지 강행해 검증한다 — 존재 확인만으로는 ttfunk 미지원 폰트(AppleGothic
    # OS/2 등)에서 실렌더 시 크래시. 여기서 걸러 생성이 항상 성공하도록 보장.
    def font_embeddable?(path)
      pdf = Prawn::Document.new(page_size: [ 120, 60 ], margin: 0)
      pdf.font_families.update("KR" => { normal: path, bold: path })
      pdf.font "KR"
      pdf.text_box "가나다 ABC", at: [ 4, 50 ], width: 110, height: 40, size: 9
      pdf.render
      true
    rescue StandardError
      false
    end

    # 진입점. rng = 고정 시드 Random. 반환 { count:, font_path:, dir: } 를 rake 가 리포트.
    def generate!(rng:, count: OUTPUT_COUNT, dir: default_dir)
      font_path = resolve_font
      FileUtils.mkdir_p(dir)
      written = 0
      count.times do |i|
        spec = build_spec(i, rng, font_path)
        render(spec, File.join(dir, format("dieline-%02d.pdf", i + 1)))
        written += 1
      end
      { count: written, font_path: font_path, dir: dir }
    end

    # ── 스펙 생성(1개 도안의 모든 파라미터·표시 문자열 확정) ────────────────────────
    def build_spec(index, rng, font_path)
      kr = !font_path.nil?
      w, d, h, volume = DIMENSIONS[index % DIMENSIONS.length]
      market = MARKETS[index % MARKETS.length]
      color  = AVATAR_COLORS[index % AVATAR_COLORS.length].delete("#") # prawn 색은 "#" 없는 6자리 hex
      code   = format("COOA-%s-%03d", market, index + 1)

      ings = INGREDIENTS.sample(4, random: rng).map(&:first)
      labels = (kr ? LABEL_CONTENTS : ASCII_LABELS).sample(3, random: rng)
      {
        kr: kr, font_path: font_path,
        w: w, d: d, h: h, volume: volume, market: market, color: color, code: code,
        line_name: kr ? ROOT_LINES[index % ROOT_LINES.length] : ASCII_LINE,
        prod_name: kr ? PRODUCT_ITEMS[index % PRODUCT_ITEMS.length] : format("CARTON %s", code),
        ings: ings, labels: labels,
        bars: Array.new(46) { [ 1, 1, 2, 3 ].sample(random: rng) }      # 바코드 모듈 폭 패턴
      }
    end

    # ── 렌더(1개 PDF) ────────────────────────────────────────────────────────────
    def render(spec, path)
      g = geometry(spec)
      pdf = Prawn::Document.new(page_size: [ g[:page_w], g[:page_h] ], margin: 0)
      if spec[:font_path]
        pdf.font_families.update("KR" => { normal: spec[:font_path], bold: spec[:font_path] })
        pdf.font "KR"
      end

      draw_body_frame(pdf, g)
      draw_glue_tab(pdf, g, spec)
      draw_flaps(pdf, g)
      draw_panel_content(pdf, g, spec)
      draw_title_block(pdf, g, spec)

      pdf.render_file(path)
    end

    # 모든 좌표를 pt 로 미리 계산. 원점=페이지 좌하단. 본체 하단 yb, 상단 yt.
    def geometry(spec)
      w = spec[:w] * MM
      d = spec[:d] * MM
      h = spec[:h] * MM
      glue_w = [ [ spec[:d] * 0.4, 8 ].max, 16 ].min * MM
      flap_h = [ [ spec[:d], 22 ].max, 55 ].min * MM
      tuck_h = flap_h * 0.5

      margin = 14 * MM
      title_band = 26 * MM

      art_w = glue_w + 2 * w + 2 * d
      art_h = h + 2 * (flap_h + tuck_h)

      page_w = art_w + 2 * margin
      page_h = art_h + 2 * margin + title_band

      xg = margin                 # 접착탭 좌단
      x0 = xg + glue_w            # front 좌단(= 접착탭 접힘선)
      x1 = x0 + w                 # front|side1
      x2 = x1 + d                 # side1|back
      x3 = x2 + w                 # back|side2
      x4 = x3 + d                 # 우측 재단선(자유 모서리)

      yb = margin + title_band + (flap_h + tuck_h) # 본체 하단(접힘선)
      yt = yb + h                                  # 본체 상단(접힘선)

      {
        page_w: page_w, page_h: page_h, margin: margin, title_band: title_band,
        w: w, d: d, h: h, glue_w: glue_w, flap_h: flap_h, tuck_h: tuck_h,
        xg: xg, x0: x0, x1: x1, x2: x2, x3: x3, x4: x4, yb: yb, yt: yt,
        # 패널 [좌x, 우x, 종류(상/하)] — front|side1|back|side2
        panels: [
          [ x0, x1, :front ], [ x1, x2, :side ], [ x2, x3, :back ], [ x3, x4, :side ]
        ]
      }
    end

    # ── 선 헬퍼: 재단선(실선 검정) / 접힘선(점선 회색) ─────────────────────────────
    def cut_line(pdf, a, b)
      pdf.undash
      pdf.line_width = 0.9
      pdf.stroke_color "111111"
      pdf.stroke_line(a, b)
    end

    def fold_line(pdf, a, b)
      pdf.line_width = 0.5
      pdf.stroke_color "8a8a8a"
      pdf.dash(3, space: 2.2)
      pdf.stroke_line(a, b)
      pdf.undash
    end

    # ── 본체 4패널 프레임(외곽 재단·내부 접힘) ────────────────────────────────────
    def draw_body_frame(pdf, g)
      yb = g[:yb]
      yt = g[:yt]
      # 상/하 접힘선(본체↔플랩) — x0..x4 전폭
      fold_line(pdf, [ g[:x0], yt ], [ g[:x4], yt ])
      fold_line(pdf, [ g[:x0], yb ], [ g[:x4], yb ])
      # 좌 접힘선(본체↔접착탭)
      fold_line(pdf, [ g[:x0], yb ], [ g[:x0], yt ])
      # 내부 세로 접힘선 x1,x2,x3
      [ g[:x1], g[:x2], g[:x3] ].each { |x| fold_line(pdf, [ x, yb ], [ x, yt ]) }
      # 우측 재단선(자유 모서리)
      cut_line(pdf, [ g[:x4], yb ], [ g[:x4], yt ])
    end

    # ── 접착탭(사선 모서리 사다리꼴) — 옅은 회색 채움 + 해칭 ──────────────────────
    def draw_glue_tab(pdf, g, spec)
      bev = [ g[:glue_w] * 0.9, g[:h] * 0.12 ].min
      xg = g[:xg]
      x0 = g[:x0]
      yb = g[:yb]
      yt = g[:yt]
      poly = [ [ x0, yt ], [ xg, yt - bev ], [ xg, yb + bev ], [ x0, yb ] ]

      pdf.fill_color "efe6e6"
      pdf.fill { pdf.polygon(*poly) }

      # 해칭(사선) — 접착부 텍스처
      draw_hatch(pdf, xg, x0, yb + bev, yt - bev)

      # 재단선(사선 top/bottom + 좌측 세로) — 좌 접힘선(x0)은 본체가 이미 그림
      cut_line(pdf, [ x0, yt ], [ xg, yt - bev ])
      cut_line(pdf, [ xg, yt - bev ], [ xg, yb + bev ])
      cut_line(pdf, [ xg, yb + bev ], [ x0, yb ])

      # 라벨(접착부) — 세로 중앙
      label = spec[:kr] ? "접착" : "GLUE"
      pdf.fill_color "b08a8a"
      pdf.text_box label, at: [ xg, (yb + yt) / 2 + 20 ], width: g[:glue_w], height: 40,
                          size: 6, align: :center, valign: :center, rotate: 90,
                          overflow: :shrink_to_fit
    end

    # 사각 영역에 45° 해칭선을 채운다(접착부 텍스처).
    def draw_hatch(pdf, x_lo, x_hi, y_lo, y_hi)
      pdf.line_width = 0.3
      pdf.stroke_color "d8c6c6"
      pdf.undash
      span = y_hi - y_lo
      x = x_lo - span
      step = 4 * MM
      while x < x_hi
        ax = [ x, x_lo ].max
        ay = y_lo + (ax - x)
        bx = [ x + span, x_hi ].min
        by = y_lo + (bx - x)
        pdf.stroke_line([ ax, ay ], [ bx, by ]) if by <= y_hi && ay >= y_lo
        x += step
      end
    end

    # ── 상/하 플랩(패널별 tuck 텅/closure/dust) ──────────────────────────────────
    def draw_flaps(pdf, g)
      # 상단: front=tuck 텅, side=dust 사다리꼴, back=closure 사각
      types_top    = { front: :tuck, side: :dust, back: :closure }
      # 하단: back=tuck 텅(교대), 나머지 동일 규칙
      types_bottom = { front: :closure, side: :dust, back: :tuck }
      g[:panels].each do |xa, xb, kind|
        draw_flap(pdf, g, xa, xb, +1, types_top[kind])
        draw_flap(pdf, g, xa, xb, -1, types_bottom[kind])
      end
    end

    # dir=+1 상단(위로), -1 하단(아래로). base_y=본체 접힘선. 종류별 외곽 재단선.
    def draw_flap(pdf, g, xa, xb, dir, type)
      base_y = dir.positive? ? g[:yt] : g[:yb]
      fh = g[:flap_h]
      outer = base_y + dir * fh
      width = xb - xa

      case type
      when :closure
        cut_line(pdf, [ xa, base_y ], [ xa, outer ])
        cut_line(pdf, [ xb, base_y ], [ xb, outer ])
        cut_line(pdf, [ xa, outer ], [ xb, outer ])
      when :dust
        bev = width * 0.18
        cut_line(pdf, [ xa, base_y ], [ xa + bev, outer ])
        cut_line(pdf, [ xa + bev, outer ], [ xb - bev, outer ])
        cut_line(pdf, [ xb - bev, outer ], [ xb, base_y ])
      when :tuck
        tw = width * 0.72
        tl = xa + (width - tw) / 2.0
        tr = tl + tw
        outer2 = outer + dir * g[:tuck_h]
        tb = [ g[:tuck_h] * 0.4, tw * 0.15 ].min
        # 플랩 외곽(좌/우 세로 + 상변은 텅 밑변 제외 재단)
        cut_line(pdf, [ xa, base_y ], [ xa, outer ])
        cut_line(pdf, [ xb, base_y ], [ xb, outer ])
        cut_line(pdf, [ xa, outer ], [ tl, outer ])
        cut_line(pdf, [ tr, outer ], [ xb, outer ])
        # 텅 밑변 = 접힘선
        fold_line(pdf, [ tl, outer ], [ tr, outer ])
        # 텅(사선 모서리)
        cut_line(pdf, [ tl, outer ], [ tl, outer2 - dir * tb ])
        cut_line(pdf, [ tl, outer2 - dir * tb ], [ tl + tb, outer2 ])
        cut_line(pdf, [ tl + tb, outer2 ], [ tr - tb, outer2 ])
        cut_line(pdf, [ tr - tb, outer2 ], [ tr, outer2 - dir * tb ])
        cut_line(pdf, [ tr, outer2 - dir * tb ], [ tr, outer ])
      end
    end

    # ── 패널 콘텐츠(제품명·성분·라벨·바코드·code) ────────────────────────────────
    def draw_panel_content(pdf, g, spec)
      pad = 3 * MM
      front = g[:panels][0]
      side1 = g[:panels][1]
      back  = g[:panels][2]
      side2 = g[:panels][3]

      draw_front(pdf, g, spec, front[0], front[1], pad)
      draw_side(pdf, g, spec, side1[0], side1[1], pad, primary: true)
      draw_back(pdf, g, spec, back[0], back[1], pad)
      draw_side(pdf, g, spec, side2[0], side2[1], pad, primary: false)
    end

    def draw_front(pdf, g, spec, xa, xb, pad)
      w = xb - xa - 2 * pad
      x = xa + pad
      top = g[:yt] - pad
      panel_h = g[:yt] - g[:yb]
      bar_h = 9 * MM

      # 라인명 컬러 바
      pdf.fill_color spec[:color]
      pdf.fill_rectangle([ x, top ], w, bar_h)
      pdf.fill_color "ffffff"
      pdf.text_box spec[:line_name], at: [ x + 3, top - 3 ], width: w - 6, height: bar_h - 4,
                   size: 7.5, valign: :center, overflow: :shrink_to_fit

      # 제품명(대) + 용량 — 이름 박스를 패널 높이에 비례해 좁혀 짧은 박스에서도 하단 바코드와 겹치지 않게.
      name_h = [ 16 * MM, panel_h * 0.20 ].min
      name_top = top - bar_h - 6
      pdf.fill_color "3d3d3d"
      pdf.text_box spec[:prod_name], at: [ x, name_top ], width: w, height: name_h,
                   size: 13, leading: 2, overflow: :shrink_to_fit
      pdf.fill_color spec[:color]
      pdf.text_box spec[:volume], at: [ x, name_top - name_h - 2 ], width: w, height: 6 * MM,
                   size: 10, overflow: :shrink_to_fit

      # 바코드(바 only) + code 캡션(하단 고정)
      bc_h = 8 * MM
      bc_top = g[:yb] + pad + 11 * MM
      draw_barcode(pdf, spec, x, bc_top, [ w, 42 * MM ].min, bc_h)
      pdf.fill_color "3d3d3d"
      pdf.text_box spec[:code], at: [ x, bc_top - bc_h - 1 ], width: w, height: 6 * MM,
                   size: 7, overflow: :shrink_to_fit

      # COOA 워드마크 — 용량과 바코드 사이 여백이 충분할 때만(짧은 박스는 생략).
      vol_bottom = name_top - name_h - 8 * MM
      if vol_bottom - bc_top > 12 * MM
        pdf.fill_color "8e0300"
        pdf.text_box "COOA", at: [ x, (vol_bottom + bc_top) / 2 + 4 * MM ], width: w,
                     height: 8 * MM, size: 11, align: :center, overflow: :shrink_to_fit
      end
    end

    def draw_side(pdf, g, spec, xa, xb, pad, primary:)
      w = xb - xa - 2 * pad
      x = xa + pad
      top = g[:yt] - pad
      pdf.fill_color "3d3d3d"

      if primary
        head = spec[:kr] ? "전성분 INGREDIENTS" : "INGREDIENTS"
        body = spec[:ings].join("\n")
      else
        head = spec[:kr] ? "표시사항" : "PRODUCT INFO"
        body = ([ "#{spec[:market]} · #{spec[:volume]}", "LOT C260-#{spec[:code][-3..]}" ] + spec[:labels].first(2)).join("\n")
      end
      pdf.fill_color spec[:color]
      pdf.text_box head, at: [ x, top ], width: w, height: 6 * MM, size: 6.5, overflow: :shrink_to_fit
      pdf.fill_color "555555"
      pdf.text_box body, at: [ x, top - 7 * MM ], width: w, height: g[:h] - 16 * MM,
                   size: 6, leading: 2, overflow: :shrink_to_fit
    end

    def draw_back(pdf, g, spec, xa, xb, pad)
      w = xb - xa - 2 * pad
      x = xa + pad
      top = g[:yt] - pad

      head = spec[:kr] ? "표시사항 · 주의사항" : "LABELING & CAUTIONS"
      pdf.fill_color spec[:color]
      pdf.text_box head, at: [ x, top ], width: w, height: 6 * MM, size: 7, overflow: :shrink_to_fit
      pdf.fill_color "555555"
      # 라벨 텍스트 높이 = 상단 헤딩~하단 바코드 사이로 제한(짧은 박스면 shrink_to_fit 축소).
      body_h = [ (g[:yt] - g[:yb]) - 32 * MM, 8 * MM ].max
      pdf.text_box spec[:labels].join("\n"), at: [ x, top - 8 * MM ], width: w, height: body_h,
                   size: 6.5, leading: 2.5, overflow: :shrink_to_fit

      # 바코드(바 only) + code 캡션(하단 고정) — 우측 여백을 확보해 분리배출 마크와 겹치지 않게.
      bc_w = [ [ w - 13 * MM, 40 * MM ].min, 16 * MM ].max
      bc_h = 8 * MM
      bc_top = g[:yb] + pad + 11 * MM
      draw_barcode(pdf, spec, x, bc_top, bc_w, bc_h)
      pdf.fill_color "3d3d3d"
      pdf.text_box spec[:code], at: [ x, bc_top - bc_h - 1 ], width: bc_w, height: 6 * MM,
                   size: 7, overflow: :shrink_to_fit

      # 분리배출 마크 자리표시(삼각형) — 바코드 우측 여백에.
      draw_recycle_mark(pdf, x + w - 6 * MM, bc_top - 2 * MM, 3.2 * MM, spec[:kr] ? "분리배출" : "PET")
    end

    # 바코드 자리표시: 폭 패턴대로 세로 막대만(캡션 code 는 호출측이 바로 밑에 그린다).
    def draw_barcode(pdf, spec, x, y_top, w, h)
      pdf.undash
      pdf.fill_color "111111"
      unit = w / spec[:bars].sum.to_f
      cursor = x
      spec[:bars].each_with_index do |mod, i|
        bw = unit * mod
        pdf.fill_rectangle([ cursor, y_top ], bw, h) if i.even?
        cursor += bw
      end
    end

    def draw_recycle_mark(pdf, cx, cy, r, label)
      pdf.undash
      pdf.line_width = 0.7
      pdf.stroke_color "3d3d3d"
      pdf.stroke { pdf.polygon([ cx, cy + r ], [ cx - r * 0.87, cy - r * 0.5 ], [ cx + r * 0.87, cy - r * 0.5 ]) }
      pdf.fill_color "3d3d3d"
      pdf.text_box label, at: [ cx - r * 1.8, cy - r - 1 ], width: r * 3.6, height: 8,
                   size: 5, align: :center, overflow: :shrink_to_fit
    end

    # ── 하단 타이틀 블록(치수·범례) ──────────────────────────────────────────────
    def draw_title_block(pdf, g, spec)
      y_top = g[:margin] + g[:title_band] - 4 * MM
      left = g[:margin]
      full = g[:page_w] - 2 * g[:margin]

      pdf.fill_color "8e0300"
      pdf.text_box "COOA", at: [ left, y_top ], width: 40 * MM, height: 8 * MM,
                   size: 16, overflow: :shrink_to_fit
      pdf.fill_color "3d3d3d"
      sub = spec[:kr] ? "단상자 전개도 · CARTON DIELINE" : "CARTON DIELINE"
      pdf.text_box sub, at: [ left, y_top - 7 * MM ], width: 70 * MM, height: 6 * MM,
                   size: 8, overflow: :shrink_to_fit

      # 중앙: 제품명 + code
      pdf.text_box "#{spec[:prod_name]}  (#{spec[:code]})", at: [ left + 55 * MM, y_top ],
                   width: full - 55 * MM - 60 * MM, height: 6 * MM, size: 8, overflow: :shrink_to_fit

      # 우측: 치수 + 스케일
      dims = format("W×D×H  %d × %d × %d mm    |    SCALE 1:1", spec[:w], spec[:d], spec[:h])
      pdf.text_box dims, at: [ left, y_top ], width: full, height: 6 * MM,
                   size: 8, align: :right, overflow: :shrink_to_fit

      # 범례(재단/접힘/접착)
      leg_y = y_top - 14 * MM
      cut_line(pdf, [ left, leg_y ], [ left + 10 * MM, leg_y ])
      pdf.fill_color "3d3d3d"
      pdf.text_box spec[:kr] ? "재단선(cut)" : "cut line", at: [ left + 12 * MM, leg_y + 3 ],
                   width: 34 * MM, height: 6 * MM, size: 7, overflow: :shrink_to_fit
      fold_line(pdf, [ left + 48 * MM, leg_y ], [ left + 58 * MM, leg_y ])
      pdf.text_box spec[:kr] ? "접힘선(fold)" : "fold line", at: [ left + 60 * MM, leg_y + 3 ],
                   width: 34 * MM, height: 6 * MM, size: 7, overflow: :shrink_to_fit
      pdf.fill_color "efe6e6"
      pdf.fill_rectangle([ left + 96 * MM, leg_y + 2.5 * MM ], 8 * MM, 4 * MM)
      pdf.fill_color "3d3d3d"
      pdf.text_box spec[:kr] ? "접착부(glue)" : "glue area", at: [ left + 106 * MM, leg_y + 3 ],
                   width: 34 * MM, height: 6 * MM, size: 7, overflow: :shrink_to_fit
    end
  end
end
