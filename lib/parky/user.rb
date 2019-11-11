require 'tzinfo'

module Parky
  module User
    def self.holidays=(holidays)
      @@holidays = holidays
    end

    def holidays
      @@holidays
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

    def claim(spot)
      spot.claimed_by self
      spot.save
    end

    def unclaim_spot
      spots = Spot.find_claimed_by self, false
      spots.each do |spot|
        spot.unclaim
        spot.save
      end
    end

    def find_claimer
      spot = Spot.find self
      spot && spot.claimer
    end

    def tz
      @tz ||= TZInfo::Timezone.get timezone
    end

    def to_tz(time)
      tz.utc_to_local time.utc
    end

    def has_been_asked_on?(time)
      return false unless last_ask
      tz_time = to_tz time
      tz_last_ask = to_tz Time.at(last_ask)
      tz_time.strftime('%F') == tz_last_ask.strftime('%F')
    end

    def should_ask_at?(time)
      is_work_hours?(time) && ! has_been_asked_on?(time)
    end

    def is_work_hours?(time)
      tz_time = to_tz time
      return false if tz_time.wday == 0 || tz_time.wday == 6  # weekends
      tz_time.hour >= 7 && tz_time.hour <= 15
    end

    def is_holiday?(time)
      tz_time = to_tz time
      day = tz_time.strftime '%F'
      holidays.any? { |h| h['start_date'] <= day && h['end_date'] >= day }
    end
  end
end
