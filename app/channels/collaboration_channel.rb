class CollaborationChannel < ApplicationCable::Channel
  STREAM_NAME = "collaboration"

  def subscribed
    stream_from STREAM_NAME

    room_id = RoomOTRedis::GLOBAL_ROOM_ID
    path = RoomOTRedis::GLOBAL_PATH
    RoomOTRedis.ensure_client(room_id, path, connection.client_id)
    doc, revision, _base_rev = RoomOTRedis.fetch_global_state
    transmit({
      type: "doc",
      client_id: connection.client_id,
      str: doc,
      revision: revision,
      clients: RoomOTRedis.clients_payload(room_id, path)
    })
  end

  def unsubscribed
    room_id = RoomOTRedis::GLOBAL_ROOM_ID
    path = RoomOTRedis::GLOBAL_PATH
    RoomOTRedis.remove_client(room_id, path, connection.client_id)
    ActionCable.server.broadcast(
      STREAM_NAME,
      { type: "client_left", client_id: connection.client_id }
    )
  end

  def operation(data)
    room_id = RoomOTRedis::GLOBAL_ROOM_ID
    path = RoomOTRedis::GLOBAL_PATH
    RoomOTRedis.enqueue_operation(
      room_id,
      path,
      connection.client_id,
      data["revision"].to_i,
      data["operation"],
      data["selection"],
      scope: "global"
    )
  rescue StandardError => e
    Rails.logger.error("[CollaborationChannel] operation error: #{e.class} #{e.message}")
  end

  def selection(data)
    room_id = RoomOTRedis::GLOBAL_ROOM_ID
    path = RoomOTRedis::GLOBAL_PATH
    selection = data["selection"] ? OT::Selection.from_json(data["selection"]) : nil
    RoomOTRedis.set_client_selection(room_id, path, connection.client_id, selection)
    RoomOTRedis.touch_client(room_id, path, connection.client_id)
    ActionCable.server.broadcast(
      STREAM_NAME,
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

    room_id = RoomOTRedis::GLOBAL_ROOM_ID
    path = RoomOTRedis::GLOBAL_PATH
    RoomOTRedis.set_client_name(room_id, path, connection.client_id, name)
    RoomOTRedis.touch_client(room_id, path, connection.client_id)
    ActionCable.server.broadcast(
      STREAM_NAME,
      { type: "set_name", client_id: connection.client_id, name: name }
    )
  end

  def resync
    room_id = RoomOTRedis::GLOBAL_ROOM_ID
    path = RoomOTRedis::GLOBAL_PATH
    RoomOTRedis.ensure_client(room_id, path, connection.client_id)
    doc, revision, _base_rev = RoomOTRedis.fetch_global_state
    transmit({
      type: "doc",
      client_id: connection.client_id,
      str: doc,
      revision: revision,
      clients: RoomOTRedis.clients_payload(room_id, path)
    })
  end
end
