module Split
  class GoalsCollection

    def initialize(experiment_name, goals=nil)
      @experiment_name = experiment_name
      @goals = goals
    end

    def load_from_redis
      Split.redis.lrange(goals_key, 0, -1)
    end

    def load_from_configuration
      goals = Split.configuration.experiment_for(@experiment_name)[:goals]

      if goals.nil?
        goals = []
      else
        goals.flatten
      end
    end

    def save
      return false if @goals.nil?
      @goals.reverse.each { |goal| Split.redis.lpush(goals_key, goal) }
    end

    def validate!
      unless @goals.nil? || @goals.kind_of?(Array)
        raise ArgumentError, 'Goals must be an array'
      end
    end

    def delete
      Split.redis.del(goals_key)
    end

    private

    def goals_key
      "#{@experiment_name}:goals"
    end
  end
end
