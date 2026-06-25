class AddDataIntegrityIndexes < ActiveRecord::Migration[8.1]
  # 앱에서만 보장하던 무결성 일부를 DB로 승격(시드/콘솔/임포트·동시성 백스톱).
  # 제외(의도):
  #  · current 단일성 → with_lock + enforce_single_current가 이미 원자 보장. 부분유니크 인덱스는
  #    "새 버전 current=1 저장 → 이후 형제 해제" 순서상 2행이 잠시 공존해 충돌 → 저장흐름 재구성 위험.
  #  · (product_id, role) 유니크 → 동일 역할(예: 담당자) 복수 인원을 막아버림(정당한 케이스).
  def up
    # 품목코드 유일(빈값 제외) — 라벨 "[#{code}]" 식별자 신뢰성(모델 검증의 DB 백스톱)
    add_index :products, :code, unique: true, where: "code IS NOT NULL AND code != ''",
              name: "idx_unique_product_code"
    # 버전번호: 컴포넌트당 유일(재현가능 보장) — 기존 비유니크 인덱스 교체
    remove_index :component_versions, name: "index_component_versions_on_component_id_and_version_number"
    add_index :component_versions, [ :component_id, :version_number ], unique: true,
              name: "index_component_versions_on_component_id_and_version_number"
    # 규제 fact (국가, INCI) 유일 — 중복 적재 시 findings 이중계산 방지 — 기존 비유니크 교체
    remove_index :ingredient_limits, name: "index_ingredient_limits_on_country_and_inci_canonical"
    add_index :ingredient_limits, [ :country, :inci_canonical ], unique: true,
              name: "index_ingredient_limits_on_country_and_inci_canonical"
  end

  def down
    remove_index :ingredient_limits, name: "index_ingredient_limits_on_country_and_inci_canonical"
    add_index :ingredient_limits, [ :country, :inci_canonical ],
              name: "index_ingredient_limits_on_country_and_inci_canonical"
    remove_index :component_versions, name: "index_component_versions_on_component_id_and_version_number"
    add_index :component_versions, [ :component_id, :version_number ],
              name: "index_component_versions_on_component_id_and_version_number"
    remove_index :products, name: "idx_unique_product_code"
  end
end
