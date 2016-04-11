module Parky
  module Config
    def usernames
      @config[:usernames]
    end

    def work_hours_only?
      @config[:work_hours_only]
    end
  end
end
