require 'active_support/configurable'

module EnjuTrunkFireSync
  def self.configure(&block)
    yield @config ||= EnjuTrunkFireSync::Configuration.new
  end

  # Global settings for Kaminari
  def self.config
    @config
  end

  # need a Class for 3.0
  class Configuration #:nodoc:
    include ActiveSupport::Configurable
    config_accessor :ftp
    config_accessor :master
    config_accessor :slave
    config_accessor :message

    def param_name
      config.param_name.respond_to?(:call) ? config.param_name.call : config.param_name
    end

    # define param_name writer (copied from AS::Configurable)
    writer, line = 'def param_name=(value); config.param_name = value; end', __LINE__
    singleton_class.class_eval writer, __FILE__, line
    class_eval writer, __FILE__, line
  end

  # this is ugly. why can't we pass the default value to config_accessor...?
  configure do |config|
    config.ftp =  {site: 'localhost', user: 'vagrant', password: 'vagrant', directory: 'sync/slave'}
    config.master = {basedir: "/home/vagrant/sync/master"}
    config.slave = {basedir: "/home/vagrant/sync/slave"}
  end
end
