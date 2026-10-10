class AlertMailer < ApplicationMailer
  def alert(recipients, subject, body)
    mail(to: recipients, subject: subject) { |format| format.text { render plain: body } }
  end
end
