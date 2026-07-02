require "test_helper"

# 아트워크 검증(PDF 수용 + 이미지 공존). identify:false로 content_type 결정성 확보(Marcel 재판별 회피).
class ComponentVersionTest < ActiveSupport::TestCase
  def version_with(name, type, io: StringIO.new("x"))
    v = ComponentVersion.new(require_artwork: true)
    v.artwork.attach(io: io, filename: name, content_type: type, identify: false)
    v
  end

  test "PDF 아트워크 허용 + artwork_pdf?" do
    v = version_with("art.pdf", "application/pdf")
    v.valid?
    assert_empty v.errors[:artwork], "PDF는 허용되어야 함"
    assert v.artwork_pdf?
  end

  test "이미지 아트워크 허용(공존) — PDF 아님" do
    v = version_with("art.png", "image/png")
    v.valid?
    assert_empty v.errors[:artwork]
    refute v.artwork_pdf?
  end

  test "허용되지 않는 타입(gif) 거부" do
    v = version_with("art.gif", "image/gif")
    v.valid?
    assert v.errors[:artwork].any? { |m| m.include?("PDF") }, "형식 오류 메시지"
  end

  test "30MB 초과 거부" do
    v = version_with("big.pdf", "application/pdf")
    v.artwork.blob.define_singleton_method(:byte_size) { 31.megabytes } # 대용량 fixture 없이 크기 분기만 검증
    v.valid?
    assert v.errors[:artwork].any? { |m| m.include?("30MB") }, "크기 오류 메시지"
  end

  # ── 업로드 시점 PDF 프로브(SEC-2/F5) — pdfinfo 필요(없으면 생략 정책이라 skip) ──

  def upload_version_with(fixture)
    v = ComponentVersion.new(require_artwork: true)
    v.artwork.attach(Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files", fixture), "application/pdf"))
    v
  end

  test "프로브: 정상 PDF 통과 / 손상 PDF 거부 / 초대형 MediaBox(DoS 벡터) 거부" do
    skip "pdfinfo 없음(프로브 생략 정책)" unless PdfProbe.available?
    ok = upload_version_with("sample_artwork.pdf")
    ok.valid?
    assert_empty ok.errors[:artwork]

    corrupt = upload_version_with("corrupt.pdf")
    corrupt.valid?
    assert corrupt.errors[:artwork].any? { |m| m.include?("손상") }, "손상 PDF는 업로드 시점 거부"

    huge = upload_version_with("huge_page.pdf")
    huge.valid?
    assert huge.errors[:artwork].any? { |m| m.include?("비정상적으로") }, "초대형 페이지는 서버 래스터화 DoS 차단"
  end

  test "PdfProbe 서비스 단독: 판정 3종" do
    skip "pdfinfo 없음" unless PdfProbe.available?
    assert PdfProbe.check(Rails.root.join("test/fixtures/files/sample_artwork.pdf")).ok
    refute PdfProbe.check(Rails.root.join("test/fixtures/files/corrupt.pdf")).ok
    refute PdfProbe.check(Rails.root.join("test/fixtures/files/huge_page.pdf")).ok
  end
end
