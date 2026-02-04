class RoomSignalChannel < ApplicationCable::Channel
  def subscribed
    @room = Room.find(params[:room_id])
    @presence_only = ActiveModel::Type::Boolean.new.cast(params[:presence_only])
    reject unless RoomMembership.exists?(room: @room, user: current_user)

    stream_from self.class.stream_name(@room)
    if @presence_only
      transmit({
        type: "presence",
        room_id: @room.id,
        users: RoomPresence.snapshot_users(@room.id)
      })
      return
    end

    transmit({ type: "welcome", client_id: connection.client_id })
    RoomPresence.join(@room.id, current_user, connection.client_id)
    RoomPresence.broadcast(@room)
  end

  def unsubscribed
    return unless @room
    return if @presence_only

    RoomPresence.leave(@room.id, current_user.id, connection.client_id)
    RoomPresence.broadcast(@room)
    ActionCable.server.broadcast(self.class.stream_name(@room), {
      type: "signal",
      sender_id: connection.client_id,
      payload: { type: "leave" }
    })
  end

  def signal(data)
    return if @presence_only

    payload = data["payload"]
    return if payload.blank?

    if %w[media join presence].include?(payload["type"])
      has_media = payload["has_media"]
      if has_media == true || has_media == false
        RoomPresence.set_media(@room.id, current_user.id, connection.client_id, has_media)
        RoomPresence.broadcast(@room)
      end
    end

    ActionCable.server.broadcast(self.class.stream_name(@room), {
      type: "signal",
      sender_id: connection.client_id,
      payload: payload
    })
  end

  def self.stream_name(room)
    "room_signal_#{room.id}"
  end
end
