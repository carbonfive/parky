require 'tzinfo'

module Parky
  module User
    def find_claimer
      claimers = Slacky::User.find_by_data "-> 'claimed' = '\"#{@slack_id}\"'"
      claimers.select! { |u| u.was_claimed_on? Time.now }
      return nil if claimers.length == 0
      return claimers[0] if claimers.length == 1
      puts "Ruh hoh: #{claimers}"
      claimers[0]
    end

    def last_ask
      data['last_ask']
    end

    def last_ask=(last_ask)
      data['last_ask'] = last_ask
    end

    def last_answer
      data['last_answer']
    end

    def last_answer=(last_answer)
      data['last_answer'] = last_answer
    end

    def claim(user)
      data['claimed_at'] = Time.now.to_i
      data['claimed'] = user.slack_id
    end

    def unclaim
      data.delete 'claimed_at'
      data.delete 'claimed'
    end

    def tz
      @tz ||= TZInfo::Timezone.get timezone
    end

    def was_claimed_on?(time)
      return false unless data['claimed_at']
      tz_time = tz.utc_to_local time.getgm
      tz_claimed = tz.utc_to_local Time.at(data['claimed_at'])
      tz_time.strftime('%F') == tz_claimed.strftime('%F')
    end

    def has_been_asked_on?(time)
      return false unless last_ask
      tz_time = tz.utc_to_local time.getgm
      tz_last_ask = tz.utc_to_local Time.at(last_ask)
      tz_time.strftime('%F') == tz_last_ask.strftime('%F')
    end

    def should_ask_at?(time)
      is_work_hours?(time) && ! has_been_asked_on?(time)
    end

    def is_work_hours?(time)
      tz_time = tz.utc_to_local time.getgm
      return false if tz_time.wday == 0 || tz_time.wday == 6  # weekends
      tz_time.hour >= 8 && tz_time.hour <= 17
    end

    def parking_spot_status
      return 'unknown' unless has_been_asked_on? Time.now
      return 'unknown' unless last_answer
      status = last_answer.downcase == 'yes' ? 'in use' : 'available'
      if status == 'available'
        claimer = find_claimer
        return "claimed by #{claimer.username}" if claimer
      end
      status
    end
  end
end
