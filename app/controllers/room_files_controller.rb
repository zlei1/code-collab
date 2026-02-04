class RoomFilesController < ApplicationController
  before_action :require_login
  before_action :set_room

  def index
    require_room_access!(@room)
    RoomWorkspace.ensure!(@room)
    render json: { tree: RoomFiles.tree(@room) }
  end

  def show
    require_room_access!(@room)
    RoomWorkspace.ensure!(@room)
    content = RoomFiles.read(@room, params[:path])
    render json: { path: params[:path], content: content }
  rescue RoomFiles::BinaryFileError
    render json: { error: "Binary file not supported" }, status: :unprocessable_entity
  rescue RoomFiles::NotFoundError
    render json: { error: "File not found" }, status: :not_found
  end

  private

  def set_room
    @room = Room.find_by!(slug: params[:slug])
  end
end
