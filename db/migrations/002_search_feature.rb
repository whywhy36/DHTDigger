# quick SQL search example:
# select name from ( select * from torrents, plainto_tsquery('nirvana') as q where (tsv @@ q)) as t1;

Sequel.migration do
  up do
    run 'alter table torrents add column tsv tsvector;'
    run 'create index tsv_index on torrents using gin(tsv);'
    run "update torrents set tsv = to_tsvector(coalesce(name, ''));"
    run p %{
create function torrents_search_trigger() RETURNS trigger AS $$
	begin
		new.tsv := to_tsvector(coalesce(new.name, ''));
		return new;
	end
$$ LANGUAGE plpgsql;
    }
    run 'create trigger tsvectorupdate before insert or update on torrents for each row execute procedure torrents_search_trigger();'
  end

  down do
    run 'drop trigger if exists tsvectorupdate on torrents;'
    run 'drop function if exists torrents_search_trigger();'
    run 'drop index tsv_index'
    drop_column :torrents, :tsv
  end
end