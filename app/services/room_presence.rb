require "json"

class RoomPresence
  CLIENT_TTL = ENV.fetch("ROOM_PRESENCE_TTL", "300").to_i

  class << self
    def join(room_id, user, client_id)
      payload = build_entry(user).merge(
        has_media: false,
        seen_at: Time.now.to_i
      )
      OT_REDIS.hset(key(room_id), client_id, JSON.generate(payload))
    end

    def leave(room_id, _user_id, client_id)
      OT_REDIS.hdel(key(room_id), client_id)
    end

    def set_media(room_id, user_id, client_id, has_media)
      payload = fetch_payload(room_id, client_id)
      return if payload.empty?
      return if payload["user_id"].to_i != user_id

      payload["has_media"] = has_media
      payload["seen_at"] = Time.now.to_i
      OT_REDIS.hset(key(room_id), client_id, JSON.generate(payload))
    end

    def snapshot_clients(room_id)
      data = fetch_all(room_id)
      data.map do |client_id, payload|
        {
          client_id: client_id,
          user_id: payload["user_id"],
          label: payload["label"],
          email: payload["email"],
          has_media: payload["has_media"],
        }
      end.sort_by { |entry| entry[:label].to_s.downcase }
    end

    def snapshot_users(room_id)
      data = fetch_all(room_id)
      grouped = data.values.group_by { |payload| payload["user_id"] }
      grouped.map do |user_id, entries|
        {
          user_id: user_id,
          label: entries.first["label"],
          email: entries.first["email"],
          has_media: entries.any? { |payload| payload["has_media"] },
        }
      end.sort_by { |entry| entry[:label].to_s.downcase }
    end

    def snapshot_users_for_rooms(room_ids)
      room_ids.index_with { |room_id| snapshot_users(room_id) }
    end

    def broadcast(room)
      room_id = room.id
      clients = snapshot_clients(room_id)
      users = snapshot_users(room_id)
      ActionCable.server.broadcast(RoomSignalChannel.stream_name(room), {
        type: "presence",
        clients: clients,
        room_id: room_id,
        users: users,
      })
    end

    private

    def key(room_id)
      "presence:room:#{room_id}"
    end

    def fetch_all(room_id)
      now = Time.now.to_i
      cutoff = now - CLIENT_TTL
      OT_REDIS.hgetall(key(room_id)).each_with_object({}) do |(client_id, raw), result|
        payload = JSON.parse(raw) rescue nil
        next if payload.nil?
        seen_at = payload["seen_at"].to_i
        if seen_at > 0 && seen_at < cutoff
          OT_REDIS.hdel(key(room_id), client_id)
          next
        end
        result[client_id] = payload
      end
    end

    def fetch_payload(room_id, client_id)
      raw = OT_REDIS.hget(key(room_id), client_id)
      return {} if raw.nil? || raw.empty?

      JSON.parse(raw)
    rescue JSON::ParserError
      {}
    end

    def build_entry(user)
      {
        "user_id" => user.id,
        "label" => label_for(user),
        "email" => user.email.to_s,
      }
    end

    def label_for(user)
      display = user.respond_to?(:display_name) ? user.display_name.to_s.strip : ""
      return user.email.to_s if display.blank?
      "#{display} - #{user.email}"
    end
  end
end
