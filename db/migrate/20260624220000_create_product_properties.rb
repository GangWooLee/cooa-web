class CreateProductProperties < ActiveRecord::Migration[8.1]
  def change
    create_table :product_properties do |t|
      t.references :product, null: false, foreign_key: true
      t.string  :name, null: false
      t.string  :value
      t.integer :position, default: 0
      t.timestamps
    end
    add_index :product_properties, [ :product_id, :position ]
  end
end
