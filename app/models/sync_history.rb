class SyncHistory < ActiveRecord::Base
  attr_accessible :action_name, :state, :message, :sync_version_id
  validates_presence_of :action_name, :state, :sync_version_id
end
