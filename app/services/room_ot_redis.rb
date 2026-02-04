require "json"
require "zlib"

class RoomOTRedis
  STREAM_SHARDS = ENV.fetch("OT_STREAM_SHARDS", "1").to_i
  HISTORY_MAX = ENV.fetch("OT_HISTORY_MAX", "5000").to_i
  CLIENT_TTL = ENV.fetch("OT_CLIENT_TTL", "300").to_i
  GLOBAL_ROOM_ID = 0
  GLOBAL_PATH = "__global__"

  def self.state_key(room_id, path)
    "ot:state:#{room_id}:#{path}"
  end

  def self.history_key(room_id, path)
    "ot:history:#{room_id}:#{path}"
  end

  def self.clients_key(room_id, path)
    "ot:clients:#{room_id}:#{path}"
  end

  def self.stream_key(room_id, path)
    shard = shard_for(room_id, path)
    stream_key_for_shard(shard)
  end

  def self.stream_key_for_shard(shard)
    "ot:ops:#{shard}"
  end

  def self.stream_checkpoint_key(shard)
    "ot:ops:#{shard}:checkpoint"
  end

  def self.shard_for(room_id, path)
    return 0 if STREAM_SHARDS <= 1

    Zlib.crc32("#{room_id}:#{path}") % STREAM_SHARDS
  end

  def self.fetch_room_state(room, path)
    key = state_key(room.id, path)
    data = OT_REDIS.hgetall(key)
    return state_from_hash(data) unless data.empty?

    doc = RoomFiles.read(room, path)
    OT_REDIS.hset(key, "doc", doc, "rev", 0, "base_rev", 0)
    [ doc, 0, 0 ]
  rescue RoomFiles::NotFoundError
    RoomFiles.write(room, path, "")
    OT_REDIS.hset(key, "doc", "", "rev", 0, "base_rev", 0)
    [ "", 0, 0 ]
  end

  def self.fetch_global_state
    key = state_key(GLOBAL_ROOM_ID, GLOBAL_PATH)
    data = OT_REDIS.hgetall(key)
    return state_from_hash(data) unless data.empty?

    OT_REDIS.hset(key, "doc", "", "rev", 0, "base_rev", 0)
    [ "", 0, 0 ]
  end

  def self.save_state(room_id, path, doc, revision, base_revision, stream_id: nil)
    key = state_key(room_id, path)
    if stream_id
      OT_REDIS.hset(key, "doc", doc, "rev", revision, "base_rev", base_revision, "last_id", stream_id)
    else
      OT_REDIS.hset(key, "doc", doc, "rev", revision, "base_rev", base_revision)
    end
  end

  def self.load_history(room_id, path)
    raw = OT_REDIS.lrange(history_key(room_id, path), 0, -1)
    raw.filter_map do |entry|
      payload = JSON.parse(entry)
      operation = OT::TextOperation.from_json(payload.fetch("operation"))
      selection = payload["selection"] ? OT::Selection.from_json(payload["selection"]) : nil
      OT::WrappedOperation.new(operation, selection)
    rescue JSON::ParserError, KeyError
      nil
    end
  end

  def self.append_history(room_id, path, wrapped)
    payload = {
      "operation" => wrapped.wrapped.as_json,
      "selection" => wrapped.meta&.as_json
    }
    OT_REDIS.rpush(history_key(room_id, path), JSON.generate(payload))
  end

  def self.persist_operation(room_id, path, doc, revision, base_revision, wrapped, stream_id)
    payload = {
      "operation" => wrapped.wrapped.as_json,
      "selection" => wrapped.meta&.as_json
    }
    OT_REDIS.multi do |multi|
      multi.hset(state_key(room_id, path), "doc", doc, "rev", revision, "base_rev", base_revision, "last_id", stream_id)
      multi.rpush(history_key(room_id, path), JSON.generate(payload))
    end
  end

  def self.compact_history(room_id, path, base_revision)
    OT_REDIS.multi do |multi|
      multi.hset(state_key(room_id, path), "base_rev", base_revision)
      multi.del(history_key(room_id, path))
    end
  end

  def self.ensure_client(room_id, path, client_id)
    key = clients_key(room_id, path)
    return if OT_REDIS.hexists(key, client_id)

    payload = { "seen_at" => Time.now.to_i }
    OT_REDIS.hset(key, client_id, JSON.generate(payload))
  end

  def self.touch_client(room_id, path, client_id)
    payload = fetch_client_payload(room_id, path, client_id)
    payload["seen_at"] = Time.now.to_i
    write_client_payload(room_id, path, client_id, payload)
  end

  def self.remove_client(room_id, path, client_id)
    OT_REDIS.hdel(clients_key(room_id, path), client_id)
  end

  def self.set_client_name(room_id, path, client_id, name)
    payload = fetch_client_payload(room_id, path, client_id)
    payload["name"] = name
    payload["seen_at"] = Time.now.to_i
    write_client_payload(room_id, path, client_id, payload)
  end

  def self.set_client_selection(room_id, path, client_id, selection)
    payload = fetch_client_payload(room_id, path, client_id)
    if selection
      payload["selection"] = selection.as_json
      payload["seen_at"] = Time.now.to_i
    else
      payload.delete("selection")
    payload["seen_at"] = Time.now.to_i
    end
    write_client_payload(room_id, path, client_id, payload)
  end

  def self.clients_payload(room_id, path)
    now = Time.now.to_i
    cutoff = now - CLIENT_TTL
    OT_REDIS.hgetall(clients_key(room_id, path)).each_with_object({}) do |(client_id, raw), result|
      payload = JSON.parse(raw) rescue {}
      seen_at = payload["seen_at"].to_i
      if seen_at > 0 && seen_at < cutoff
        OT_REDIS.hdel(clients_key(room_id, path), client_id)
        next
      end
      result[client_id] = payload
    end
  end

  def self.enqueue_operation(room_id, path, client_id, revision, operation, selection, scope: "room")
    payload = {
      "scope" => scope,
      "room_id" => room_id,
      "path" => path,
      "client_id" => client_id,
      "revision" => revision,
      "operation" => JSON.generate(operation),
      "selection" => selection ? JSON.generate(selection) : ""
    }
    OT_REDIS.xadd(stream_key(room_id, path), payload)
  end

  def self.stream_checkpoint(shard)
    OT_REDIS.get(stream_checkpoint_key(shard))
  end

  def self.update_stream_checkpoint(shard, stream_id)
    OT_REDIS.set(stream_checkpoint_key(shard), stream_id)
  end

  def self.fetch_client_payload(room_id, path, client_id)
    raw = OT_REDIS.hget(clients_key(room_id, path), client_id)
    return {} if raw.nil? || raw.empty?

    JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end

  def self.write_client_payload(room_id, path, client_id, payload)
    OT_REDIS.hset(clients_key(room_id, path), client_id, JSON.generate(payload))
  end

  def self.state_from_hash(data)
    [ data.fetch("doc", ""), data.fetch("rev", "0").to_i, data.fetch("base_rev", "0").to_i ]
  end
  private_class_method :fetch_client_payload, :write_client_payload, :state_from_hash
end
