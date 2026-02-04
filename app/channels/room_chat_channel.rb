class RoomChatChannel < ApplicationCable::Channel
  def subscribed
    @room = Room.find(params[:room_id])
    reject unless RoomMembership.exists?(room: @room, user: current_user)

    stream_from self.class.stream_name(@room)
    transmit({ type: "history", messages: history_payload })
  end

  def message(data)
    content = data["content"].to_s.strip
    return if content.empty?

    message = @room.room_messages.create!(user: current_user, content: content)
    ActionCable.server.broadcast(self.class.stream_name(@room), {
      type: "message",
      message: {
        id: message.id,
        user_id: current_user.id,
        user: current_user.display_name.presence || current_user.email,
        content: message.content,
        created_at: message.created_at.iso8601
      }
    })
  end

  def self.stream_name(room)
    "room_chat_#{room.id}"
  end

  private

  def history_payload
    @room.room_messages.order(created_at: :asc).last(50).map do |message|
      {
        id: message.id,
        user_id: message.user_id,
        user: message.user.display_name.presence || message.user.email,
        content: message.content,
        created_at: message.created_at.iso8601
      }
    end
  end
end
