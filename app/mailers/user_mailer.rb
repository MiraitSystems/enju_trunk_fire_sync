module EnjuTrunkFireSync
  class UserMailer < ActionMailer::Base
    default from: "notifications@example.jp"

    def notification_message(email, message, backtrace = [])
      @backtrace = backtrace 
      @message = message
      mail(to: email, subject: 'Notification Message from EnjuTrunkFireSync')
    end
  end
end
