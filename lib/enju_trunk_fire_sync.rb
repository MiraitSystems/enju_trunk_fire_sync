require "enju_trunk_fire_sync/engine"

spec = Gem::Specification.find_by_name("enju_trunk_fire_sync")
gem_root = spec.gem_dir
gem_lib = gem_root + "/lib"
gem_mailer = gem_root + "/app/mailers"

$:.unshift(gem_mailer) if File.directory?(gem_mailer) && !$:.include?(gem_mailer)

require "user_mailer"

module ActionMailer
end

# load modules
require "enju_trunk_fire_sync/config"
