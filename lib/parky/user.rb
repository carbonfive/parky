require 'tzinfo'

module Parky
  module User
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

    def claim(spot)
      spot.claimed_by self
      spot.save
    end

    def unclaim_spot
      spots = Spot.find_claimed_by self
      spots.each do |spot|
        spot.unclaim
        spot.save
      end
    end

    def tz
      @tz ||= TZInfo::Timezone.get timezone
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
  end
end
