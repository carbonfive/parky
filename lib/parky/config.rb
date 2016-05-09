module Parky
  module Config
    def usernames
      ENV.fetch('USERNAMES', '').split(',').map(&:strip)
    end

    def work_hours_only?
      ENV['WORK_HOURS_ONLY'] != 'false'
    end
  end
end
