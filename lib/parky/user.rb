require 'tzinfo'

class Parky::User
  attr_accessor :user_id, :im_id, :last_ask, :last_answer

  def initialize(attrs={})
    @user_id     = attrs[:user_id]
    @im_id       = attrs[:im_id]
    @last_ask    = attrs[:last_ask]
    @last_answer = attrs[:last_answer]
  end

  def has_been_asked_on?(time)
    return false unless @last_ask

    la = TZInfo::Timezone.get 'America/Los_Angeles'
    la_time = la.utc_to_local time.getgm
    la_last_ask = la.utc_to_local Time.at(@last_ask)
    la_time.strftime('%F') == la_last_ask.strftime('%F')
  end

  def parking_spot_status
    return 'unknown' unless @last_answer
    @last_answer == 'yes' ? 'in use' : 'available'
  end
end
