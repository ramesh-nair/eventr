class User < ApplicationRecord

  has_many :user_groups, :class_name => "::GroupUser", :foreign_key => :user_id, dependent: :destroy
  has_many :credits
  has_many :groups, :through => :user_groups

  after_save :get_longlived_token
  after_create :add_user_to_sendbird

  ALLOWED_RSVP_STATES = ["attending","declined","maybe","not_replied","created"]
  NEARBY_EVENT_DISTANCE_RANGE = 30000
  NEARBY_EVENTS_APP_SERVER_URL = "https://nearby-events.herokuapp.com"

  def add_user_to_sendbird
    url = URI.parse("https://api.sendbird.com/v3/users")
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    request = Net::HTTP::Post.new(url)
    request["content-type"] = 'application/json'
    request["api-token"] = "#{ENV["SENDBIRD_APP_TOKEN"]}"
    request.body = "{\"user_id\":\"#{self.reload.uuid}\",\"nickname\":\"#{self.name}\",\"profile_url\":\"#{self.pic_url}\"}"
    response = http.request(request)
  end

  def get_longlived_token
    url = URI.parse("https://graph.facebook.com/oauth/access_token?grant_type=fb_exchange_token&client_id=#{ENV["FB_APP_ID"]}&client_secret=#{ENV["FB_APP_SECRET"]}&fb_exchange_token=#{self.fb_token}")
    response = Net::HTTP.get_response(url)
    if response.code == "200"
      parameters = Rack::Utils.parse_nested_query(response.body)
      long_token = parameters["access_token"]
      self.update_columns(:fb_token => long_token)
    end
  end 

  def logout access_token
    Redis.current.del("user:token:#{access_token}")
  end  

  def self.login_with_facebook token
    user = get_facebook_data token
    if user
      auth_token = create_access_token user.uuid
      return true, user, auth_token
    else
      return false, nil, nil
    end      
  end  

  def fetch_fb_event_list rsvp_state
    if ALLOWED_RSVP_STATES.include?rsvp_state
      url = "https://graph.facebook.com/v2.7/#{self.fb_id}/events/#{rsvp_state}?fields=id,name,cover,place,is_canceled,attending_count,maybe_count,interested_count,start_time,end_time&since=#{Date.today.to_s}&access_token=#{self.fb_token}"
      fb_api_call url
    else
      return "Please check the RSVP status of the event.", 400, {}
    end
  end

  def rsvp_event fb_event_id, rsvp_state
    if ALLOWED_RSVP_STATES.include?rsvp_state
      url = URI.parse("https://graph.facebook.com/v2.7/#{fb_event_id}/#{rsvp_state}?access_token=#{self.fb_token}")
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      request = Net::HTTP::Post.new(url)
      request["content-type"] = 'application/json'
      response = http.request(request)
      data = JSON.parse(response.body)
      (response.code=="200")? message="Success": message="Bad Request to FB"
      return message, response.code, data 
    else
      return "Please check the RSVP status of the event.", 400, {}
    end
  end

  def fetch_fb_event fb_event_id
    url = "https://graph.facebook.com/v2.7/#{fb_event_id}?fields=id,name,cover,description,place,is_canceled,is_viewer_admin,attending_count,maybe_count,interested_count,noreply_count,declined_count,owner,ticket_uri,start_time,end_time,timezone&access_token=#{self.fb_token}"
    message, code, data = fb_api_call url
    data["user_attending_event"] = user_event_rsvp? fb_event_id, "attending"
    data["user_interested_event"] = user_event_rsvp? fb_event_id, "maybe"
    return message, code, data
  end

  def user_event_rsvp? fb_event_id, state
    url = "https://graph.facebook.com/v2.7/#{fb_event_id}/#{state}/#{self.fb_id}?access_token=#{self.fb_token}"
    message, code, data = fb_api_call url
    rsvp_status = data["data"].first["rsvp_status"] rescue "entry_not_found"
    state="unsure" if state=="maybe"
    (rsvp_status == "#{state}")? true : false
  end

  def self.get_facebook_data token
    response = Net::HTTP.get_response(URI.parse("https://graph.facebook.com/v2.7/me?fields=name,email,picture.width(400)&access_token=#{token}"))
    data = JSON.parse(response.body)
    if response.code=="200"
      data["token"] = token
      self.create_user data 
    end
  end 

  def self.create_user data 
    user = self.find_or_initialize_by(:fb_id => data["id"])
    user.update_attributes(self.user_params(data))
    user.reload
  end  

  def self.create_access_token uuid
    access_token = SecureRandom.hex(16)
    Redis.current.set("user:token:#{access_token}", uuid)
    access_token
  end

  def self.get_user_from_token token
    uuid = Redis.current.get("user:token:#{token}")
    user = User.find_by_uuid(uuid) rescue nil
  end

  def nearby_events lat, lng
    city = find_city_based_on_location(lat,lng)
    url = "#{NEARBY_EVENTS_APP_SERVER_URL}/events?query=#{city}&lat=#{lat}&lng=#{lng}&distance=#{NEARBY_EVENT_DISTANCE_RANGE}&sort=popularity&since=#{Date.today.to_s}&accessToken=#{self.fb_token}"
    response = Net::HTTP.get_response(URI.parse(url))
    data = JSON.parse(response.body)
    if response.code=="200" 
      message="Success"
      code = "200" 
    else
      message = data["message"]["message"] || "Try again after a while"
      code = "400"
    end
    return message, code, data
  end

  def find_city_based_on_location lat,lng
    geo_localization = "#{lat},#{lng}"
    query = Geocoder.search(geo_localization).first
    query.city
  end

    private

    def self.user_params data
      {
        :fb_id => data["id"],
        :email => data["email"],
        :pic_url => (data["picture"]["data"]["url"] rescue nil),
        :fb_token => data["token"],
        :name => data["name"]
      }
    end

    def fb_api_call url
      response = Net::HTTP.get_response(URI.parse(url))
      data = JSON.parse(response.body)
      (response.code=="200")? message="Success": message=data["error"]["type"]
      return message, response.code, data
    end

end
