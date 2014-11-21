class CreateSyncHistories < ActiveRecord::Migration
  def change
    create_table :sync_histories do |t|
      t.string :action_name, :null => false
      t.string :state, :null => false
      t.text :message
      t.integer :sync_version_id, :null => false

      t.timestamps
    end
    add_index :sync_histories, [:action_name, :state, :sync_version_id], :name => 'sync_histories_index_1'
  end
end
