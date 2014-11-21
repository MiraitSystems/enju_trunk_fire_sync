# -*- encoding: utf-8 -*-
class SyncHistoriesController < ApplicationController
  load_and_authorize_resource
  before_filter :check_client_ip_address

  def index
  end

  def show
  end

end
