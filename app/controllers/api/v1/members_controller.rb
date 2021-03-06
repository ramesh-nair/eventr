module Api::V1
  class MembersController < ApiController
    before_action :set_member, only: [:confirm_member,:make_admin,:mark_attendance]

    def confirm_member
      if current_user_is_group_admin?
        if params[:state].present?
          if @member.confirm_approval(params[:state].to_i)
            render json: {:data => build_member_hash(@member), :message=>"Success"}, status: 200
          else
            render json: {:data=>{},:message=>"#{@member.errors.full_messages}"}, status: 400
          end
        else
          render json: {:data=>{}, :message=>"Enter Correct Parameter(state)"}, status: 400
        end
      else
        render json: {:data=>{},:message=>"Only Group Admin/Owner can confirm members to the group"}, status: 400
      end
    end

    def make_admin
      if @member.group.owner_id == @current_user.id
        @member.update_attributes(:role=>1,:enabled=>true,:state=>1)
        render json: {:data => build_member_hash(@member), :message=>"Success"}, status: 200
      else
        render json: {:data=>{},:message=>"Only Owners can Make Admins"}, status: 400
      end
    end

    def mark_attendance
      if @member.group.owner_id == @current_user.id
        @member.user_attended_event
        render json: {:data=>build_member_hash(@member), :message=>"Success"}, status: 200
      else
        render json: {:data=>{},:message=>"Only Owners can Mark Attendance"}, status: 400
      end
    end

    private

    def set_member
      @member = GroupUser.find_by_uuid(params[:id])
      unless @member
        render json: {:message=>"No Group Member Found"}, status: 400 and return
      end
    end

    def build_members group
      members_array = Array.new
      group.members.each do |mem|
        data = build_member_hash(mem)
        members_array << data
      end
      members_array
    end

    def build_member_hash member
      data = Hash.new
      usr = member.user
      data["id"] = usr.id
      data["user_uuid"] = usr.uuid
      data["member_uuid"] = member.uuid
      data["fb_id"] = usr.fb_id
      data["name"] = usr.name
      data["email"] = usr.email
      data["status"] = member.state
      data["role"] = member.role
      data["enabled"] = member.enabled
      data["pic_url"] = usr.pic_url
      data["event_attended"] = member.event_attended
      data
    end

    def current_user_is_group_admin? 
      admin_member = @member.group.members.find_by(:user_id=>@current_user.id)
      if admin_member.role=="member"
        return false
      else
        return true
      end
    end

  end
end
