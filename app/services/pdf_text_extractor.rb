# 도안(PDF) 텍스트 레이어 추출기 — PdfProbe(app/services/pdf_probe.rb)의 프로세스 실행 패턴을 복제한다.
# pdftotext -raw(포플러)로 벡터 PDF의 임베드 텍스트를 뽑는다. -raw는 그리기 순서(draw order)대로 블록을
# 이어붙여, 단상자 전개도처럼 컬럼이 흩어진 레이아웃에서 -layout(좌표 정렬·컬럼 좌우 혼선)보다 성분 블록의
# 연속성이 좋다(실측 2026-07-11 · db/demo/assets/dieline-01.pdf: -layout은 전성분↔표시사항 컬럼이 뒤섞이나
# -raw는 헤더 아래 성분이 연속 라인으로 떨어진다). OCR 아님 — 텍스트 레이어가 없는 스캔/래스터 PDF는 빈
# 문자열이 나온다(호출부가 "후보 0" 빈 상태로 처리).
# pdftotext 부재 시 :unavailable 반환(호출부 안내용) — poppler 미설치 dev를 우아하게 생략(PdfProbe 동형).
class PdfTextExtractor
  TIMEOUT_SECS = 5

  # command -v 메모이즈(PdfProbe.available?와 동일 관례). system은 false를 캐시하지 않지만(||=), 부재
  # 환경에서 매 호출 재검사는 무해하고, 테스트는 이 술어를 스텁해 :unavailable 경로를 검증한다.
  def self.available? = @available ||= system("command -v pdftotext > /dev/null 2>&1")

  # 성공 → 추출 원문(String) · pdftotext 부재 → :unavailable · 실패/타임아웃/손상 → nil.
  def self.extract(path)
    return :unavailable unless available?

    run_with_timeout([ "pdftotext", "-raw", path.to_s, "-" ]) # "-" = stdout
  end

  # popen + 자체 데드라인 — PdfProbe.run_with_timeout 복제(macOS엔 timeout(1) 부재). 단상자 도안의 텍스트는
  # 수백 바이트라 파이프 버퍼(64KB) 안 — 프로세스가 먼저 종료한 뒤 읽어도 유실 없음(대용량 다페이지는 범위 밖).
  def self.run_with_timeout(cmd)
    r, w = IO.pipe
    pid = Process.spawn(*cmd, out: w, err: File::NULL)
    w.close
    deadline = Time.now + TIMEOUT_SECS
    status = nil
    while Time.now < deadline
      _, status = Process.waitpid2(pid, Process::WNOHANG)
      break if status
      sleep 0.05
    end
    if status.nil?
      Process.kill("KILL", pid) rescue nil
      Process.waitpid(pid) rescue nil
      r.close
      return nil
    end
    out = r.read
    r.close
    status.success? ? out : nil
  rescue Errno::ENOENT
    nil
  end
end
