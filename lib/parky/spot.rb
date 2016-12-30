require 'tzinfo'

module Parky
  class Spot
    attr_reader :number, :owner_id

    @@config = @@db = nil

    def self.decorator=(decorator)
      @@decorator = decorator
    end

    def self.config=(config)
      @@config = config
    end

    def self.db
      return @@db if @@db
      @@db = @@config.db
      initialize_table
      @@db
    end

    def self.initialize_table
      self.db.exec <<-SQL
create table if not exists spots (
  number       integer not null,
  owner_id     varchar(20),
  claimed_at   timestamp,
  claimer_id   varchar(20)
);
SQL
    end

    def self.find_claimed_by(user)
      result = db.exec_params "select * from spots where claimer_id = $1", [ user.slack_id ]
      return nil if result.ntuples == 0
      hydrate(result).select { |s| s.was_claimed_on? Time.now }
    end

    def self.find(query)
      return nil unless query
      if query.is_a? Numeric
        result = db.exec_params "select * from spots where number = $1", [ query ]
      else
        id = query.is_a?(String) ? query : query.slack_id
        result = db.exec_params "select * from spots where owner_id = $1", [ id ]
      end
      return nil if result.ntuples == 0
      hydrate(result)[0]
    end

    def self.hydrate(result)
      result.map do |row|
        self.new number:     row['number'],
                 owner_id:   row['owner_id'],
                 claimed_at: row['claimed_at'],
                 claimer_id: row['claimer_id']
      end
    end

    def initialize(attrs={})
      @number     = attrs[:number]
      @owner_id   = attrs[:owner_id]
      @claimed_at = attrs[:claimed_at]
      @claimer_id = attrs[:claimer_id]
      @timezone   = attrs[:timezone] || 'America/Los_Angeles'
    end

    def owner
      Slacky::User.find @owner_id
    end

    def username
      @owner_id ? owner.username : ''
    end

    def claimer
      Slacky::User.find @claimer_id
    end

    def label
      if @owner_id
        "#{owner.username}'s spot"
      else
        "spot #{@number}"
      end
    end

    def claimed_by(user)
      @claimer_id = user.slack_id
      @claimed_at = Time.now
    end

    def unclaim
      @claimer_id = nil
      @claimed_at = nil
    end

    def tz
      TZInfo::Timezone.get @timezone
    end

    def was_claimed_on?(time)
      return false unless @claimed_at
      tz_time = tz.utc_to_local time.getgm
      tz_claimed = tz.utc_to_local DateTime.parse(@claimed_at)
      tz_time.strftime('%F') == tz_claimed.strftime('%F')
    end

    def status
      return "claimed by #{claimer.username}" if @claimed_at
      return "available" unless @owner_id
      owner.tap do |owner|
        return "unknown" unless owner.has_been_asked_on?(Time.now) && owner.last_answer
        return ( owner.last_answer.downcase == 'yes' ? 'in use' : 'available' )
      end
    end

    def save
      Spot.db.exec_params "delete from spots where number = $1", [ @number ]
      Spot.db.exec_params "insert into spots (number, owner_id, claimed_at, claimer_id) values ($1, $2, $3, $4)",
                          [ @number, @owner_id, @claimed_at, @claimer_id ]
      self
    end

  end
end
