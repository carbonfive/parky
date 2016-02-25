require 'yaml'
require 'time'

class Parky::Config
  attr_reader :config, :pid_file

  def initialize(config_dir = nil)
    @dir = config_dir || "#{ENV['HOME']}/.parky"
    FileUtils.mkdir @dir unless File.directory? @dir
    @pid_file = "#{@dir}/pid"

    @timestamps = {}
    load_config :force => true
  end

  def slack_api_token
    @config[:slack_api_token]
  end

  def slack_reject_channels
    @config.fetch(:slack_reject_channels, '').split ','
  end

  def slack_accept_channels
    @config.fetch(:slack_accept_channels, '').split ','
  end

  def reload(options = {})
    options = { :force => false }.merge options
    load_config options
  end

  def log(msg, ex = nil)
    log = File.new(log_file, 'a')
    timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
    type = ex ? 'ERROR' : ' INFO'
    log.puts "#{type}  #{timestamp}  #{msg}"
    if ex
      log.puts ex.message
      log.puts("Stacktrace:\n" + ex.backtrace.join("\n"))
    end
    log.flush
  end

  private

  def load_config(options)
    @config = if_updated? config_file, options do
      YAML.load( IO.read(config_file) )
    end
    @config ||= {}
  end

  def config_file
    "#{@dir}/config.yml"
  end

  def log_file
    "#{@dir}/parky.log"
  end

  def if_updated?(file_name, options)
    return nil if ! File.exists? file_name

    file = File.new file_name
    last_read = @timestamps[file_name]
    stamp = file.mtime
    if options[:force] || last_read.nil? || stamp > last_read
      yield
    else
      nil
    end
  end
end
