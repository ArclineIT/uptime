class AlertChannelsController < ApplicationController
  before_action :set_channel, only: %i[ edit update destroy test ]

  def index
    @channels = AlertChannel.ordered
  end

  def new
    @channel = AlertChannel.new(kind: "discord")
  end

  def create
    @channel = AlertChannel.new(channel_params)

    if @channel.save
      redirect_to alert_channels_path, notice: "#{@channel.name} added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @channel.update(channel_params)
      redirect_to alert_channels_path, notice: "#{@channel.name} updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @channel.destroy
    redirect_to alert_channels_path, notice: "#{@channel.name} deleted.", status: :see_other
  end

  def test
    @channel.deliver("[TEST] arcline-uptime", "[TEST] arcline-uptime\nThis is a test alert for the #{@channel.name} channel.")
    redirect_to alert_channels_path, notice: "Test alert sent to #{@channel.name}."
  rescue Notifiers::Error => e
    redirect_to alert_channels_path, alert: "Test alert failed: #{e.message}"
  end

  private
    def set_channel
      @channel = AlertChannel.find(params[:id])
    end

    # A blank token on edit keeps the stored one, so it never has to be shown.
    def channel_params
      permitted = params.expect(alert_channel: [ :name, :kind, :url, :token, :priority, :recipients ])
      permitted.delete(:token) if permitted[:token].blank? && @channel&.persisted?
      permitted
    end
end
