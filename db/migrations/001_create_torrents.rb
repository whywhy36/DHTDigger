Sequel.migration do
  up do
    create_table(:torrents) do
      primary_key :id
      String :name, :null => false
      String :files
      String :data_hash, :null => false
      String :length
      String :category
      String :magnet_uri, :null => false
      String :metadata, :null => false
      Integer :counter
      DateTime :create_at, :null => false
      DateTime :updated_at, :null => false
      TrueClass :blocked
    end
  end

  down do
    drop_table(:torrents)
  end
end