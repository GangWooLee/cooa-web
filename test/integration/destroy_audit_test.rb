require "test_helper"

# B4 — products#destroy / components#destroy previously left NO audit trail (a gap: every other domain
# mutation records to audit_logs). These now emit an allow row whose `after` summarizes what the cascade
# removed. kim = owner (manage_product/upload_version) with a linked domain User → passes require_domain_actor.
class DestroyAuditTest < ActionDispatch::IntegrationTest
  test "products#destroy records product.destroy audit with cascade summary" do
    product = Product.find_by!(code: "CO0001") # hero — has components + versions in its subtree
    subtree = Product.subtree_ids(product.id)
    expected_descendants = subtree.size - 1
    expected_components = Component.where(product_id: subtree).count

    assert_difference -> { AuditLog.where(action: "product.destroy", outcome: "allow").count }, 1 do
      delete product_path(product)
    end

    log = AuditLog.where(action: "product.destroy").order(:tenant_seq).last
    assert_equal "Product", log.resource_type
    assert_equal product.id, log.resource_id
    assert_equal expected_descendants, log.after["descendants"]
    assert_equal expected_components, log.after["components"]
    assert_operator log.after["versions"].to_i, :>=, 0
  end

  test "components#destroy records component.destroy audit with version count" do
    component = Product.find_by!(code: "CO0001").components.find_by!(component_type: "outer_box")
    expected_versions = component.component_versions.count
    assert_operator expected_versions, :>, 0, "fixture should have versions to make the count meaningful"

    assert_difference -> { AuditLog.where(action: "component.destroy", outcome: "allow").count }, 1 do
      delete component_path(component)
    end

    log = AuditLog.where(action: "component.destroy").order(:tenant_seq).last
    assert_equal "Component", log.resource_type
    assert_equal component.id, log.resource_id
    assert_equal expected_versions, log.after["versions"]
  end

  # E4: an unbridged account (owner rights, no domain User) is blocked before the audit write — the guard
  # prevents AuditLog.record!'s fail-closed raise from turning into a 500, and nothing is destroyed/recorded.
  test "unbridged account is blocked (403) with no destroy and no audit" do
    Account.find_by!(email: "kim@cooa.dev").update_columns(user_id: nil)
    product = Product.find_by!(code: "CO0001")

    assert_no_difference [ "AuditLog.count", "Product.count" ] do
      delete product_path(product)
    end
    assert_response :forbidden
  end
end
