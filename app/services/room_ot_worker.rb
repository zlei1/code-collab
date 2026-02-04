require "json"

class RoomOTWorker
  DEFAULT_BLOCK_MS = 1000
  DEFAULT_COUNT = 100

  def self.run(shard_id: nil, block_ms: DEFAULT_BLOCK_MS, count: DEFAULT_COUNT)
    shard_id ||= ENV.fetch("OT_STREAM_SHARD_ID", "0").to_i
    shard_count = ENV.fetch("OT_STREAM_SHARDS", "1").to_i
    raise ArgumentError, "invalid shard id" if shard_id.negative? || shard_id >= shard_count

    new(shard_id, block_ms: block_ms, count: count).run
  end

  def initialize(shard_id, block_ms:, count:)
    @shard_id = shard_id
    @block_ms = block_ms
    @count = count
    @stream_key = RoomOTRedis.stream_key_for_shard(shard_id)
    @last_id = RoomOTRedis.stream_checkpoint(shard_id) || "0-0"
    @sessions = {}
  end

  def run
    Rails.logger.info("[RoomOTWorker] shard=#{@shard_id} stream=#{@stream_key} starting at #{@last_id}")
    loop do
      entries = read_stream
      next if entries.nil?

      entries.each do |_stream, messages|
        messages.each do |stream_id, fields|
          process(stream_id, normalize_fields(fields))
          @last_id = stream_id
          RoomOTRedis.update_stream_checkpoint(@shard_id, stream_id)
        end
      end
    rescue Redis::TimeoutError, RedisClient::ReadTimeoutError
      next
    end
  end

  private

  def read_stream
    OT_REDIS.call("XREAD", "BLOCK", @block_ms, "COUNT", @count, "STREAMS", @stream_key, @last_id)
  end

  def normalize_fields(fields)
    return fields if fields.is_a?(Hash)
    return {} unless fields.is_a?(Array)
    fields.each_slice(2).each_with_object({}) { |(k, v), h| h[k] = v }
  end

  def process(stream_id, fields)
    scope = fields.fetch("scope", "room")
    room_id = fields.fetch("room_id").to_i
    path = fields.fetch("path")
    client_id = fields.fetch("client_id")
    revision = fields.fetch("revision").to_i
    operation = JSON.parse(fields.fetch("operation"))
    selection = fields["selection"]
    selection = selection && !selection.empty? ? JSON.parse(selection) : nil

    wrapped = OT::WrappedOperation.new(
      OT::TextOperation.from_json(operation),
      selection ? OT::Selection.from_json(selection) : nil
    )

    room, session = fetch_session(scope, room_id, path)
    stream_name = stream_name_for(scope, room, path)

    session.synchronize do
      wrapped_prime = session.server.receive_operation(revision, wrapped)
      RoomOTRedis.persist_operation(
        room_id,
        path,
        session.document,
        session.revision,
        session.server.base_revision,
        wrapped_prime,
        stream_id
      )
      RoomOTRedis.set_client_selection(room_id, path, client_id, wrapped_prime.meta)
      RoomOTRedis.touch_client(room_id, path, client_id)
      RoomFiles.write(room, path, session.document) if scope == "room"

      ActionCable.server.broadcast(
        stream_name,
        { type: "ack", client_id: client_id }
      )
      ActionCable.server.broadcast(
        stream_name,
        {
          type: "operation",
          client_id: client_id,
          operation: wrapped_prime.wrapped.as_json,
          selection: wrapped_prime.meta&.as_json
        }
      )

      if session.server.compact!(RoomOTRedis::HISTORY_MAX)
        RoomOTRedis.compact_history(room_id, path, session.server.base_revision)
        ActionCable.server.broadcast(stream_name, { type: "resync" })
      end
    end
  rescue OT::Server::StaleRevision
    ActionCable.server.broadcast(stream_name_for(scope, room_id, path), { type: "resync", client_id: client_id })
  rescue StandardError => e
    Rails.logger.error("[RoomOTWorker] operation error: #{e.class} #{e.message}")
  end

  def fetch_session(scope, room_id, path)
    key = "#{scope}:#{room_id}:#{path}"
    cached = @sessions[key]
    return cached[:room], cached[:session] if cached

    if scope == "global"
      doc, rev, base_rev = RoomOTRedis.fetch_global_state
      operations = RoomOTRedis.load_history(room_id, path)
      if base_rev + operations.length != rev
        Rails.logger.warn("[RoomOTWorker] global history mismatch, forcing resync")
        operations = []
        base_rev = rev
        RoomOTRedis.compact_history(room_id, path, base_rev)
      end
      session = OT::Session.new(doc, operations, base_rev)
      @sessions[key] = { room: nil, session: session }
      return [ nil, session ]
    end

    room = Room.find(room_id)
    doc, rev, base_rev = RoomOTRedis.fetch_room_state(room, path)
    operations = RoomOTRedis.load_history(room_id, path)
    if base_rev + operations.length != rev
      Rails.logger.warn("[RoomOTWorker] room history mismatch, forcing resync room_id=#{room_id} path=#{path}")
      operations = []
      base_rev = rev
      RoomOTRedis.compact_history(room_id, path, base_rev)
    end
    session = OT::Session.new(doc, operations, base_rev)
    @sessions[key] = { room: room, session: session }
    [ room, session ]
  end

  def stream_name_for(scope, room_or_id, path)
    if scope == "global"
      CollaborationChannel::STREAM_NAME
    else
      room = room_or_id.is_a?(Room) ? room_or_id : Room.find(room_or_id)
      RoomCollabChannel.stream_name(room, path)
    end
  end
end
