class RoomRunChannel < ApplicationCable::Channel
  def subscribed
    @room = Room.find(params[:room_id])
    reject unless RoomMembership.exists?(room: @room, user: current_user)

    stream_from self.class.stream_name(@room)
  end

  def self.stream_name(room)
    "room_run_#{room.id}"
  end
end
