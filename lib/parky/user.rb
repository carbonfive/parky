require 'tzinfo'

class Parky::User
  attr_accessor :user_id, :im_id, :last_ask, :last_answer

  def self.db=(db)
    @@db = db
  end

  def self.find(user_id)
    user = nil
    @@db.execute "select im_id, last_ask, last_answer from users where user_id = ?", [ user_id ] do |row|
      user = self.new user_id: user_id, im_id: row[0], last_ask: row[1], last_answer: row[2]
    end
    user
  end

  def initialize(attrs={})
    @user_id     = attrs[:user_id]
    @im_id       = attrs[:im_id]
    @last_ask    = attrs[:last_ask]
    @last_answer = attrs[:last_answer]

    @tz_la = TZInfo::Timezone.get 'America/Los_Angeles'
  end

  def save
    @@db.execute "delete from users where user_id = ?", [ @user_id ]
    @@db.execute "insert into users (user_id, im_id, last_ask, last_answer)
                  values (?, ?, ?, ?)", [ @user_id, @im_id, @last_ask, @last_answer ]
  end

  def reset
    @last_ask = nil
    @last_answer = nil
  end

  def has_been_asked_on?(time)
    return false unless @last_ask

    la_time = @tz_la.utc_to_local time.getgm
    la_last_ask = @tz_la.utc_to_local Time.at(@last_ask)
    la_time.strftime('%F') == la_last_ask.strftime('%F')
  end

  def should_ask_at?(time)
    is_work_hours?(time) && ! has_been_asked_on?(time)
  end

  def is_work_hours?(time)
    la_time = @tz_la.utc_to_local time.getgm
    return false if la_time.wday == 0 || la_time.wday == 6  # weekends
    la_time.hour >= 8 && la_time.hour <= 17
  end

  def parking_spot_status
    return 'unknown' unless @last_answer
    @last_answer == 'yes' ? 'in use' : 'available'
  end
end
