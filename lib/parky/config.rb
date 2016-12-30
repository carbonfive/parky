module Parky
  module Config
    def spotnames
      ENV.fetch('SPOTS', '').split(',').map(&:strip)
    end

    def usernames
      spotnames.map do |spotname|
        spotname.split('-')[1]
      end.compact
    end

    def work_hours_only?
      ENV['WORK_HOURS_ONLY'] != 'false'
    end
  end
end
