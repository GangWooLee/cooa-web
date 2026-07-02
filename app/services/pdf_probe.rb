# 업로드 시점 PDF 개봉 검사(SEC-2/F5): pdfinfo(포플러, 래스터화 없이 헤더/메타만 — 수 ms)로
#  - 손상/비-PDF(파싱 실패) → 거부: 뷰어 빈화면·representation 500의 상류 차단
#  - 암호화 PDF → 거부: PDF.js·pdftoppm 모두 열 수 없어 하류 전면 실패
#  - 초대형 MediaBox → 거부: 수백 바이트 PDF가 [0 0 100000 100000] 선언만으로 서버 pdftoppm
#    래스터화(72dpi 기가픽셀)를 유발하는 자원고갈 DoS 벡터 제거(클라 8192 캡은 서버를 못 지킴)
# pdfinfo 부재 시 프로브 생략(기존 동작 유지) — Dockerfile엔 poppler-utils 포함, dev는 R8 문서 참조.
class PdfProbe
  MAX_PAGE_PTS = 14_400 # PDF 스펙 상한(200in) — 실무 포장 도면도 이 안
  TIMEOUT_SECS = 5

  Result = Struct.new(:ok, :error, keyword_init: true)

  def self.available? = @available ||= system("command -v pdfinfo > /dev/null 2>&1")

  def self.check(path)
    return Result.new(ok: true) unless available?

    out = run_with_timeout([ "pdfinfo", path.to_s ])
    return Result.new(ok: false, error: "손상되었거나 열 수 없는 PDF입니다") if out.nil?
    return Result.new(ok: false, error: "암호로 보호된 PDF는 지원되지 않습니다") if out.match?(/^Encrypted:\s+yes/i)

    if (m = out.match(/^Page size:\s+([\d.]+)\s+x\s+([\d.]+)/i))
      w, h = m[1].to_f, m[2].to_f
      if w > MAX_PAGE_PTS || h > MAX_PAGE_PTS
        return Result.new(ok: false, error: "페이지 크기가 비정상적으로 큽니다(#{w.round}×#{h.round}pt)")
      end
    end
    Result.new(ok: true)
  end

  # popen + 데드라인 — macOS엔 timeout(1)이 없어 자체 감시. 초과/실패는 nil(=열 수 없음 취급).
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
