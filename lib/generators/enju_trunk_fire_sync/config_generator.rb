module EnjuTrunkFireSync
  module Generators
    class ConfigGenerator < Rails::Generators::Base
      source_root File.expand_path(File.join(File.dirname(__FILE__), 'templates'))

      desc "This generator copy an initializer file at config/initializers"
      def copy_config_file
        copy_file 'enju_trunk_fire_sync.rb', 'config/initializers/enju_trunk_fire_sync.rb'
      end
    end
  end
end
