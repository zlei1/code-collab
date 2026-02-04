class RoomsController < ApplicationController
  before_action :require_login
  before_action :set_room_by_slug, only: %i[show join update]

  def index
    @rooms = current_user.rooms.order(created_at: :desc)
  end

  def new
    @room = Room.new
    @scaffolds = Scaffolds::Catalog.all
  end

  def create
    @room = Room.new(room_params.merge(owner: current_user))
    @scaffolds = Scaffolds::Catalog.all

    if @room.save
      RoomMembership.create!(room: @room, user: current_user, role: "owner")
      RoomWorkspace.ensure!(@room)
      redirect_to room_path(@room.slug), notice: "Room created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    require_room_access!(@room)
    RoomWorkspace.ensure!(@room)
    @scaffold = Scaffolds::Catalog.find(@room.template_key)
    @share_url = "#{request.base_url}#{room_path(@room.slug)}"
  end

  def join
    if request.get?
      return redirect_to room_path(@room.slug) if @room.users.exists?(id: current_user.id)
      return
    end

    # For now, skip password verification as it was removed from the database
    # Later we might add share-specific password verification here
    RoomMembership.find_or_create_by!(room: @room, user: current_user) do |membership|
      membership.role = "member"
    end
    redirect_to room_path(@room.slug), notice: "Joined room."
  end

  def update
    return head :forbidden unless @room.owner == current_user

    if @room.update(room_params)
      render json: { message: "Room updated successfully." }
    else
      render json: { error: @room.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  private

  def room_params
    params.require(:room).permit(:name, :template_key)
  end

  def set_room_by_slug
    @room = Room.find_by!(slug: params[:slug])
  end
end
