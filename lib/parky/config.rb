require 'yaml'
require 'time'
require 'sqlite3'

class Parky::Config
  attr_reader :config, :pid_file

  def initialize(config_dir = nil)
    @dir = config_dir || "#{ENV['HOME']}/.parky"
    FileUtils.mkdir @dir unless File.directory? @dir
    @pid_file = "#{@dir}/pid"
    @db = init_db

    @timestamps = {}
    load_config :force => true
  end

  def init_db
    db = SQLite3::Database.new "#{@dir}/parky.db"
    tables = []
    db.execute "select name from sqlite_master where type='table'" do |row|
      tables << row[0]
    end
    unless tables.include? 'users'
      puts "Creating 'users' table"
      db.execute <<-SQL
create table users (
  user_id     varchar(20),
  im_id       varchar(20),
  last_ask    int,
  last_answer varchar(20)
);
SQL
    end
    db
  end

  def get_dbuser(user_id)
    user = nil
    @db.execute "select im_id, last_ask, last_answer from users where user_id = ?", [ user_id ] do |row|
      user = Parky::User.new user_id: user_id, im_id: row[0], last_ask: row[1], last_answer: row[2]
    end
    user
  end

  def save_dbuser(user)
    @db.execute "delete from users where user_id = ?", [ user.user_id ]
    @db.execute "insert into users (user_id, im_id, last_ask, last_answer)
                 values (?, ?, ?, ?)", [ user.user_id, user.im_id, user.last_ask, user.last_answer ]
  end

  def users
    @users || @users = Parky::Users.new()
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

  def slackbot_id
    @config[:slack_bot_id]
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
