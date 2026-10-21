class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("SMTP_FROM", "alerts@arcline.it")
  layout "mailer"
end
