module Parky

  class CLI
    def initialize(opts)
      @options = { :verbose => false }.merge opts
      config = Config.new()
      slackbot = Slackbot.new(config)
      daemon = Daemon.new(config, slackbot)
      @service = Service.new(config, daemon)
    end

    def run(params)
      @service.run
    end

    def start(params)
      @service.start
    end

    def stop(params)
      @service.stop
    end

    def restart(params)
      @service.restart
    end

    def status(params)
      @service.status
    end

  end
end
