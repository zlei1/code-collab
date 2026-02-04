class RoomRunsController < ApplicationController
  before_action :require_login
  before_action :set_room

  def create
    require_room_access!(@room)
    RoomWorkspace.ensure!(@room)

    run = RoomRun.create!(room: @room, user: current_user, status: "queued")
    RoomRunJob.perform_later(run.id)

    ActionCable.server.broadcast(RoomRunChannel.stream_name(@room), { type: "run", run_id: run.id, status: run.status })
    render json: { run_id: run.id, status: run.status }
  end

  private

  def set_room
    @room = Room.find_by!(slug: params[:slug])
  end
end
