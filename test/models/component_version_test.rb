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

  test "0바이트(빈/잘린 업로드) 거부" do
    v = version_with("empty.pdf", "application/pdf", io: StringIO.new("")) # 타입 통과 후 크기 0에서 차단
    v.valid?
    assert v.errors[:artwork].any? { |m| m.include?("빈 파일") }, "0바이트는 거부(뷰어 빈화면·probe 오작동 상류 방어)"
  end

  test "파일명 극단(한글·특수문자·200자)은 업로드 검증을 깨지 않음(green)" do
    weird = version_with(%(한글 파일명 <>"'&.png), "image/png") # 내용은 유효(1B) — 파일명만 극단
    weird.valid?
    assert_empty weird.errors[:artwork], "특수문자 파일명이라도 내용이 유효하면 통과"

    long_name = version_with("#{"가" * 200}.png", "image/png")
    long_name.valid?
    assert_empty long_name.errors[:artwork], "초장문 파일명도 통과(파일명은 검증 대상 아님)"
  end

  # ── 업로드 시점 PDF 프로브(SEC-2/F5) — pdfinfo 필요(없으면 생략 정책이라 skip) ──

  def upload_version_with(fixture)
    v = ComponentVersion.new(require_artwork: true)
    v.artwork.attach(Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files", fixture), "application/pdf"))
    v
  end

  # 로컬은 pdfinfo 부재 시 skip(프로브 생략 정책 그대로) · CI는 부재를 flunk로 승격 —
  # poppler 미설치로 프로브 테스트가 조용히 통과(착시)하는 것을 CI에서 막는다(S4).
  def require_pdfinfo!
    return if PdfProbe.available?
    flunk("CI엔 poppler(pdfinfo) 필수 — 프로브 테스트가 조용히 skip되면 안 됨") if ENV["CI"]
    skip "pdfinfo 없음(프로브 생략 정책)"
  end

  test "프로브: 정상 PDF 통과 / 손상 PDF 거부 / 초대형 MediaBox(DoS 벡터) 거부" do
    require_pdfinfo!
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
    require_pdfinfo!
    assert PdfProbe.check(Rails.root.join("test/fixtures/files/sample_artwork.pdf")).ok
    refute PdfProbe.check(Rails.root.join("test/fixtures/files/corrupt.pdf")).ok
    refute PdfProbe.check(Rails.root.join("test/fixtures/files/huge_page.pdf")).ok
  end
end
