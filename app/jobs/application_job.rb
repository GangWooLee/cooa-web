class ApplicationJob < ActiveJob::Base
  # 재시도는 "재실행하면 자연 소멸하는 일시적 오류"로만 한정한다(E6 · docs/error-handling.md). StandardError
  # 전반을 retry_on 하면 멱등하지 않은 잡이 중복 부작용을 낼 수 있어 금지. DB 데드락은 대표적 일시 오류 —
  # 폴리노미얼 백오프로 최대 3회 재시도하면 대개 해소된다.
  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 3

  # ActiveStorage 오류(IntegrityError=체크섬 불일치·FileNotFoundError·PreviewError 등)는 재시도하지 않는다 —
  # 손상/포맷 문제라 재실행해도 동일하게 실패한다(마스킹 금지, 표면화가 옳음). 클라우드 스토리지(S3) 전환으로
  # 네트워크 타임아웃 계열이 생기면 그때 그 예외로 한정해 retry_on을 추가한다.

  # 참조 레코드가 이미 사라진 잡(연쇄 삭제 등)은 역직렬화 불가 → 재시도 무의미하므로 조용히 폐기.
  discard_on ActiveJob::DeserializationError
end
