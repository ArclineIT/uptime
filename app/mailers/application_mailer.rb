class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("SMTP_FROM", "alerts@arclineit.com")
  layout "mailer"
end
