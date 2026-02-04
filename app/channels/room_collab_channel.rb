require "base64"

class RoomCollabChannel < ApplicationCable::Channel
  def subscribed
    @room = Room.find(params[:room_id])
    @path = params[:path].to_s
    reject unless RoomMembership.exists?(room: @room, user: current_user)

    RoomWorkspace.ensure!(@room)
    stream_from self.class.stream_name(@room, @path)

    RoomOTRedis.ensure_client(@room.id, @path, connection.client_id)
    doc, revision, _base_rev = RoomOTRedis.fetch_room_state(@room, @path)
    transmit({
      type: "doc",
      client_id: connection.client_id,
      str: doc,
      revision: revision,
      clients: RoomOTRedis.clients_payload(@room.id, @path)
    })
  end

  def unsubscribed
    RoomOTRedis.remove_client(@room.id, @path, connection.client_id)
    ActionCable.server.broadcast(
      self.class.stream_name(@room, @path),
      { type: "client_left", client_id: connection.client_id }
    )
  end

  def operation(data)
    RoomOTRedis.enqueue_operation(
      @room.id,
      @path,
      connection.client_id,
      data["revision"].to_i,
      data["operation"],
      data["selection"],
      scope: "room"
    )
  rescue StandardError => e
    Rails.logger.error("[RoomCollabChannel] operation error: #{e.class} #{e.message}")
  end

  def selection(data)
    selection = data["selection"] ? OT::Selection.from_json(data["selection"]) : nil
    RoomOTRedis.set_client_selection(@room.id, @path, connection.client_id, selection)
    RoomOTRedis.touch_client(@room.id, @path, connection.client_id)
    ActionCable.server.broadcast(
      self.class.stream_name(@room, @path),
      {
        type: "selection",
        client_id: connection.client_id,
        selection: selection&.as_json
      }
    )
  end

  def set_name(data)
    name = data["name"].to_s.strip
    return if name.empty?

    RoomOTRedis.set_client_name(@room.id, @path, connection.client_id, name)
    RoomOTRedis.touch_client(@room.id, @path, connection.client_id)
    ActionCable.server.broadcast(
      self.class.stream_name(@room, @path),
      { type: "set_name", client_id: connection.client_id, name: name }
    )
  end

  def resync
    RoomOTRedis.ensure_client(@room.id, @path, connection.client_id)
    doc, revision, _base_rev = RoomOTRedis.fetch_room_state(@room, @path)
    transmit({
      type: "doc",
      client_id: connection.client_id,
      str: doc,
      revision: revision,
      clients: RoomOTRedis.clients_payload(@room.id, @path)
    })
  end

  def self.stream_name(room, path)
    encoded = Base64.urlsafe_encode64(path)
    "room_collab_#{room.id}_#{encoded}"
  end
end
