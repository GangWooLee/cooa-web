require "test_helper"

# 도안 텍스트 추출 체인(HTTP) — 업로드 → GET 추출 후보 → POST 확정 → 스크리닝 유입 → 재확정 no-op →
# viewer 네거티브 → poppler 부재 안내. 기본 로그인 = kim(owner, test_helper setup).
#
# 픽스처: test/fixtures/files/dieline_extract_sample.pdf — dieline 생성기의 Helvetica 영문 폴백(한글 폰트
#   서브셋 임베드 없음 = 공개 repo 재배포 무풍). 갱신 명령(font_path=nil 강제 → 영문/Helvetica):
#   bin/rails runner 'load Rails.root.join("db/demo/dieline.rb"); \
#     Demo::Dieline.render(Demo::Dieline.build_spec(0, Random.new(20260711), nil), \
#       Rails.root.join("test/fixtures/files/dieline_extract_sample.pdf").to_s)'
#   (주의: DEMO_DIELINE_FONT=/nonexistent 만으로는 시스템 한글 폰트가 여전히 잡혀 Helvetica 폴백이 안 됨 —
#    font_path=nil 직접 주입이 유일한 영문 폴백 경로다.)
class LabelExtractionTest < ActionDispatch::IntegrationTest
  FIXTURE = "dieline_extract_sample.pdf".freeze

  def kim = User.find_by!(email: "kim@cooa.dev")

  def hero_component
    Product.find_by!(code: "CO0001").components.find_by!(component_type: "outer_box")
  end

  # 새 버전에 dieline PDF를 첨부(hero 시드 버전은 정적 image_name이라 첨부 없음 → 추출 대상 아님).
  def version_with_dieline
    comp = hero_component
    v = comp.component_versions.create!(
      version_number: comp.component_versions.maximum(:version_number).to_i + 1,
      label: "[CO0001]", created_by: kim, current: false
    )
    v.artwork.attach(Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files", FIXTURE), "application/pdf"))
    v
  end

  test "GET 추출: 후보를 hidden+checkbox 폼으로 렌더" do
    v = version_with_dieline
    get extraction_component_version_path(v)
    assert_response :success
    # 영문 폴백 픽스처의 성분 후보(Niacinamide/Panthenol/Salicylic Acid/Butylene Glycol) hidden 필드.
    assert_select "input[name=?][value=?]", "ingredients[0][inci_name]", "Niacinamide"
    assert_select "input[name='ingredient_ids[]']", minimum: 4
    # 라벨 후보(LOT·용량·제품명 등) hidden 필드.
    assert_select "input[name='label_ids[]']", minimum: 1
    assert_select "input[name=?]", "labels[0][content]"
  end

  test "POST 확정→행 생성→스크리닝 유입, 재확정은 중복 가드로 no-op" do
    v = version_with_dieline
    params = {
      ingredient_ids: %w[0 1],
      ingredients: {
        "0" => { inci_name: "Niacinamide", inci_canonical: "NIACINAMIDE" },
        "1" => { inci_name: "Panthenol",   inci_canonical: "PANTHENOL" },
        "2" => { inci_name: "Salicylic Acid", inci_canonical: "SALICYLIC ACID" } # 미선택(체크 안 함)
      },
      label_ids: %w[0 1],
      labels: {
        "0" => { content: "LOT / EXP: SEE BOTTOM" },
        "1" => { content: "30 ml" }
      }
    }
    # 선택분만 생성: 성분 2 · 라벨 2 (Salicylic Acid는 미선택이라 제외).
    assert_difference [ "v.ingredients.count", "v.label_texts.count" ], 2 do
      post extraction_component_version_path(v), params: params
    end
    assert_redirected_to component_version_path(v)
    follow_redirect!
    assert_match(/성분 2건/, flash[:notice])
    assert_match(/라벨 2건/, flash[:notice])

    assert_equal [ "Niacinamide", "Panthenol" ], v.reload.ingredients.order(:position).pluck(:inci_name)
    refute_includes v.ingredients.pluck(:inci_name), "Salicylic Acid"
    assert v.label_texts.all? { |l| l.text_type == "label" }
    # country/language 관례(JP → ko).
    assert_equal "ko", v.label_texts.first.language

    # 확정 성분·라벨이 기존 계약 그대로 스크리닝에 유입.
    run = ScreeningService.new(v, "JP").run!(requested_by: kim)
    assert_equal "completed", run.status
    subjects = run.screening_findings.where(element_type: "ingredient").pluck(:subject)
    assert_includes subjects, "Niacinamide"
    assert_includes subjects, "Panthenol"

    # 재확정(동일 params) → 중복 가드로 미생성 + 스킵 보고.
    assert_no_difference [ "v.ingredients.count", "v.label_texts.count" ] do
      post extraction_component_version_path(v), params: params
    end
    follow_redirect!
    assert_match(/중복 4건/, flash[:notice])
  end

  test "viewer(yu)는 추출·확정 모두 차단(GET 303 · POST 403 · 미생성)" do
    v = version_with_dieline
    sign_in_as(Account.find_by!(email: "yu@cooa.dev"))

    get extraction_component_version_path(v)
    assert_response :see_other # GET html deny → root 리다이렉트(ApplicationController#deny_access)

    assert_no_difference "v.ingredients.count" do
      post extraction_component_version_path(v),
           params: { ingredient_ids: %w[0], ingredients: { "0" => { inci_name: "Niacinamide", inci_canonical: "NIACINAMIDE" } } }
    end
    assert_response :forbidden
  end

  test "pdftotext 부재(available? false) 시 후보 대신 안내 렌더" do
    v = version_with_dieline
    # minitest/mock가 이 번들(minitest 6)에 없어 클래스 메서드를 임시 교체·복원(edge_resubmit_test 관례).
    original = PdfTextExtractor.method(:available?)
    PdfTextExtractor.define_singleton_method(:available?) { false }
    begin
      get extraction_component_version_path(v)
    ensure
      PdfTextExtractor.define_singleton_method(:available?, original)
    end
    assert_response :success
    assert_includes response.body, "poppler"
    assert_select "input[name='ingredient_ids[]']", false, "부재 시 후보 폼은 렌더되지 않음"
  end

  test "첨부 없는 버전: no_artwork 안내" do
    comp = hero_component
    v = comp.component_versions.create!(
      version_number: comp.component_versions.maximum(:version_number).to_i + 1,
      label: "[CO0001]", created_by: kim, current: false
    )
    get extraction_component_version_path(v)
    assert_response :success
    assert_includes response.body, "도안 파일이 첨부"
  end
end
