class IncidentsController < ApplicationController
  def index
    @incidents = Incident.recent.includes(:monitor).limit(100)
  end
end
