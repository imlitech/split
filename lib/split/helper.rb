# frozen_string_literal: true
module Split
  module Helper
    module_function

    def get_request
      if Split.configuration.custom_request
        return Split.configuration.custom_request.call
      end
      return request
    end

    def ab_test(metric_descriptor, control = nil, *alternatives)
      begin
        experiment = ExperimentCatalog.find_or_initialize(metric_descriptor, control, *alternatives)
        alternative = if Split.configuration.enabled
          experiment.save
          trial = Trial.new(:user => ab_user, :experiment => experiment,
              :override => override_alternative(experiment.name), :exclude => exclude_visitor?,
              :disabled => split_generically_disabled?)
          alt = trial.choose!(self)
          alt ? alt.name : nil
        else
          control_variable(experiment.control)
        end
      rescue Errno::ECONNREFUSED, Redis::BaseError, SocketError => e
        raise(e) unless Split.configuration.db_failover
        Split.configuration.db_failover_on_db_error.call(e)

        if Split.configuration.db_failover_allow_parameter_override
          alternative = override_alternative(experiment.name) if override_present?(experiment.name)
          alternative = control_variable(experiment.control) if split_generically_disabled?
        end
      ensure
        alternative ||= control_variable(experiment.control)
      end

      if block_given?
        metadata = trial ? trial.metadata : {}
        yield(alternative, metadata)
      else
        alternative
      end
    end

    def reset!(experiment)
      ab_user.delete(experiment.key)
    end

    def finish_experiment(experiment, options = {:reset => true})
      return true if experiment.has_winner?
      should_reset = experiment.resettable? && options[:reset]
      if ab_user[experiment.finished_key] && !should_reset
        return true
      else
        alternative_name = ab_user[experiment.key]
        trial = Trial.new(:user => ab_user, :experiment => experiment,
              :alternative => alternative_name)
        trial.complete!(options[:goals], self)

        if should_reset
          reset!(experiment)
        else
          ab_user[experiment.finished_key] = true
        end
      end
    end

    def ab_finished(metric_descriptor, options = {:reset => true})
      return if exclude_visitor? || Split.configuration.disabled?
      metric_descriptor, goals = normalize_metric(metric_descriptor)
      experiments = Metric.possible_experiments(metric_descriptor)

      if experiments.any?
        experiments.each do |experiment|
          finish_experiment(experiment, options.merge(:goals => goals))
        end
      end
    rescue => e
      raise unless Split.configuration.db_failover
      Split.configuration.db_failover_on_db_error.call(e)
    end

    def finished(metric_descriptor, options = {:reset => true})
      warn 'DEPRECATION WARNING: finished method was renamed to ab_finished and will be removed in Split 2.0.0'
      ab_finished(metric_descriptor, options)
    end

    def override_present?(experiment_name)
      if Split.configuration.custom_override
        return Split.configuration.custom_override.call(experiment_name)
      end
      # Fetch from global params variable as fallback
      defined?(params) && params[experiment_name]
    end

    def override_alternative(experiment_name)
      if Split.configuration.custom_override
        return Split.configuration.custom_override.call(experiment_name)
      end
      # Fetch from global params variable as fallback
      params[experiment_name] if override_present?(experiment_name)
    end

    def split_generically_disabled?
      if Split.configuration.custom_override
        return Split.configuration.custom_override.call('SPLIT_DISABLE')
      end
      # Fetch from global params variable as fallback
      defined?(params) && params['SPLIT_DISABLE']
    end

    def begin_experiment(experiment, alternative_name = nil)
      warn 'DEPRECATION WARNING: begin_experiment is deprecated and will be removed from Split 2.0.0'
      alternative_name ||= experiment.control.name
      ab_user[experiment.key] = alternative_name
      alternative_name
    end

    def ab_user
      @ab_user ||= User.new(self)
    end

    def exclude_visitor?
      instance_eval(&Split.configuration.ignore_filter) || is_ignored_ip_address? || is_robot?
    end

    def is_robot?
      request = get_request
      defined?(request) && request.user_agent =~ Split.configuration.robot_regex
    end

    def is_ignored_ip_address?
      return false if Split.configuration.ignore_ip_addresses.empty?
      request = get_request
      Split.configuration.ignore_ip_addresses.each do |ip|
        return true if defined?(request) && (request.ip == ip || (ip.class == Regexp && request.ip =~ ip))
      end
      false
    end

    def active_experiments
      ab_user.active_experiments
    end

    def normalize_metric(metric_descriptor)
      if Hash === metric_descriptor
        experiment_name = metric_descriptor.keys.first
        goals = Array(metric_descriptor.values.first)
      else
        experiment_name = metric_descriptor
        goals = []
      end
      return experiment_name, goals
    end

    def control_variable(control)
      Hash === control ? control.keys.first.to_s : control.to_s
    end
  end
end
