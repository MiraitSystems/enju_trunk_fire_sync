enju_trunk_fire_sync
====================

enju_trunk 用データ同期モジュール

## Installation

1. Add EnjuTrunkFireSync to your `Gemfile`.

    `gem 'enju_trunk_fire_sync', '~> 0.0.1'`

2. Add configuration to you `config/config.yml`.

~~~
sync:
  ftp:
    site: localhost
    user: vagrant
    password: vagrant
    directory: "sync/slave"
  master:
    base_directory: "/home/vagrant/sync/master"
  slave:
    base_directory: "/home/vagrant/sync/slave"
~~~




